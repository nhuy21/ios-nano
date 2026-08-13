//
//  WithdrawView.swift
//  nano ewallet
//
//  Mirror WithdrawScreen.kt — rút tiền về TK ngân hàng. Đã liên kết
//  (wallet.accNo/bankNo) -> card readonly; chưa liên kết -> cho chọn bank + nhập
//  STK, verify tên chủ TK qua BE trước khi cho rút (chỉ dùng cho lần này, không
//  ghi vào wallets). PIN xác thực khi vượt ngưỡng dùng chung PinEntrySheet.
//

import SwiftUI
import Combine

/// Bảng màu riêng của màn rút tiền — mirror các hằng Wd* trong WithdrawScreen.kt.
private enum WdColor {
    static let green = Color(hex: 0x00A85E)
    static let greenDark = Color(hex: 0x007E47)
    static let ink = Color(hex: 0x111C17)
    static let muted = Color(hex: 0x8A9990)
    static let line = Color(hex: 0xEEF1EF)
    static let fieldGray = Color(hex: 0xF1F3F5)
    static let amountBg = Color(hex: 0xF6F6F7)
    static let error = Color(hex: 0xE5484D)
    static let disabled = Color(hex: 0xDDE1E6)
}

@MainActor
struct WithdrawView: View {
    let onBack: () -> Void
    let onSuccess: (TransferSuccessInfo) -> Void

    @StateObject private var wallet = WalletStore.shared
    @StateObject private var bankCache = BankCache.shared

    @State private var amountText = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    @State private var pendingTransactionId: String?
    /// Mốc bắt đầu gọi API rút tiền — để biên lai hiện thời gian xử lý thật.
    @State private var submitStartedAt: Date?
    @State private var pinError: String?

    /// Xác thực bằng Face ID thay vì nhập mật khẩu — xem `BiometricAuthSheet`.
    @State private var useBiometric = BiometricKeyStore.hasKey()
    @State private var biometricError: String?

    // Nhánh chưa liên kết ngân hàng — chọn bank + nhập STK, verify trước khi rút.
    @State private var selectedBin: String?
    @State private var accountNumber = ""
    @State private var accType = 0
    @State private var manualHolderName = ""
    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var lastLookedUp: (bin: String, account: String, accType: Int)?
    @State private var showAllBanks = false

    /// Bàn phím số tự vẽ của ô SỐ TIỀN đang hiện hay không. Không phải `@FocusState` vì bàn
    /// phím này là SwiftUI thuần — không có `TextField` nào để mà focus.
    @State private var isAmountFocused = false
    @FocusState private var isAccountFocused: Bool

    private let idempotencyKey = TransferService.newIdempotencyKey()

    /// `amountText` chứa chuỗi ĐÃ format ("1.000.000") nên phải lọc chữ số.
    private var amount: Int64 { amountText.amountValue }

    private var isLinked: Bool {
        !(wallet.accNo ?? "").isEmpty && !(wallet.bankNo ?? "").isEmpty
    }

    private var linkedBankName: String {
        BankCache.shared.bank(bin: wallet.bankNo)?.shortName ?? "Ngân hàng"
    }

    private var sortedBanks: [Bank] {
        bankCache.banks.sorted { a, b in
            let priority = ["Vietcombank", "BIDV", "VietinBank", "Agribank", "Techcombank",
                             "MBBank", "ACB", "VPBank", "TPBank", "Sacombank"]
            let ia = priority.firstIndex(of: a.shortName) ?? Int.max
            let ib = priority.firstIndex(of: b.shortName) ?? Int.max
            return ia < ib
        }
    }

    private var hasBeneficiary: Bool {
        isLinked || (selectedBin != nil && !accountNumber.isEmpty && !manualHolderName.isEmpty)
    }

    private var overLimit: Bool {
        if let balance = wallet.balance { return amount > balance }
        return false
    }

    private var overMaxPerWithdraw: Bool { amount > TransferLimits.faceFixed }

    private var canContinue: Bool { amount > 0 && !overMaxPerWithdraw && hasBeneficiary }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    destinationSection
                    amountSection
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }

            // Bàn phím số tự vẽ thay cho nút "Xác nhận" rời — nút hành động nằm luôn trong
            // bàn phím, giống màn chuyển ví. Bản CÓ phím "000" vì đây là ô nhập TIỀN.
            if isAmountFocused {
                NumericKeypad(
                    onDigit: appendDigits,
                    onBackspace: backspaceDigit,
                    onNext: { Task { await submitWithdraw() } },
                    nextTitle: "Xác nhận",
                    nextEnabled: canContinue && !isSubmitting
                )
            } else {
                continueBar
            }
        }
        // Kotlin để nền TRẮNG cho màn này (khác các màn chuyển tiền dùng xám nhạt).
        .screenBackground(Color.white)
        .dismissesCustomKeypadOnTap { isAmountFocused = false }
        .task {
            await wallet.refresh()
            _ = await bankCache.get()
        }
        .sheet(isPresented: $showAllBanks) {
            BankPickerSheet(banks: sortedBanks, selectedBin: $selectedBin, onDismiss: { showAllBanks = false })
        }
        .sheet(isPresented: pendingTransactionIdBinding) {
            if useBiometric {
                BiometricAuthSheet(
                    amountText: Int(amount).vndFormatted,
                    recipientName: pendingRecipientName,
                    onAuthenticate: submitBiometric,
                    onUsePassword: {
                        // Giữ pendingTransactionId — giao dịch còn hạn 120s bên BE.
                        biometricError = nil
                        useBiometric = false
                    },
                    onCancel: { pendingTransactionId = nil },
                    externalError: $biometricError
                )
            } else {
                PinEntrySheet(
                    amountText: Int(amount).vndFormatted,
                    recipientName: pendingRecipientName,
                    onSubmit: submitPin,
                    onCancel: { pendingTransactionId = nil },
                    externalError: $pinError
                )
            }
        }
        .onChangeCompat(of: selectedBin) { _, _ in runLookupIfNeeded() }
        .overlay { if isSubmitting { ProcessingOverlay() } }
        .overlay {
            if let errorMessage {
                TransferErrorOverlay(message: errorMessage, showIcon: false) {
                    self.errorMessage = nil
                }
            }
        }
    }

    private var pendingTransactionIdBinding: Binding<Bool> {
        Binding(get: { pendingTransactionId != nil }, set: { if !$0 { pendingTransactionId = nil } })
    }

    // MARK: - Header

    /// Header sáng, tiêu đề canh TRÁI cạnh nút back — mirror WithdrawScreen.kt, không
    /// phải dải gradient xanh với tiêu đề canh giữa như trước.
    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(WdColor.ink)
                    .frame(width: 40, height: 40)
                    .background(WdColor.fieldGray)
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Quay lại")

            Text("Rút tiền về ngân hàng")
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(WdColor.ink)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Đích rút

    @ViewBuilder
    private var destinationSection: some View {
        if isLinked {
            // Thẻ thông tin ngân hàng liên kết: nền gradient xanh nhạt -> trắng, viền
            // xanh 35%, key-value đầy đủ để đối soát. Mirror WithdrawScreen.kt.
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(WdColor.green)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "wallet.pass.fill")
                                .font(.system(size: 19))
                                .foregroundStyle(.white)
                        }
                    Text("Ngân hàng liên kết")
                        .font(AppFont.beVietnamPro(15, .bold))
                        .foregroundStyle(WdColor.greenDark)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)

                cardDivider
                infoRow(label: "Ngân hàng", value: linkedBankName)
                cardDivider
                infoRow(label: "Số tài khoản", value: wallet.accNo ?? "—")
                cardDivider
                infoRow(label: "Chủ tài khoản", value: wallet.accName ?? "—")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0xE6F7EE), .white],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(WdColor.green.opacity(0.35), lineWidth: 1)
            }
        } else {
            manualDestinationSection
        }
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(WdColor.green.opacity(0.15))
            .frame(height: 1)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(WdColor.muted)
            Text(value)
                .font(AppFont.beVietnamPro(13, .bold))
                .foregroundStyle(WdColor.ink)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 14)
    }

    private var manualDestinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FieldLabel(text: "Ngân hàng").padding(.bottom, 0)
                Spacer()
                Button("Xem tất cả") { showAllBanks = true }
                    .buttonStyle(PressableButtonStyle())
                    .font(AppFont.beVietnamPro(13, .semibold))
                    .foregroundStyle(AppColor.brand)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(sortedBanks.prefix(10)) { bank in
                        bankChip(bank)
                    }
                }
            }

            HStack(spacing: 0) {
                accTypeToggle(title: "Số tài khoản", index: 0)
                accTypeToggle(title: "Số thẻ", index: 1)
            }
            .padding(3)
            .background(Color(hex: 0xF1F3F5))
            .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: accType == 0 ? "Số tài khoản" : "Số thẻ")
                AppTextField(
                    text: $accountNumber, placeholder: "Nhập số tài khoản",
                    keyboardType: .numberPad, submitLabel: .done, digitsOnly: true
                )
                .focused($isAccountFocused)
                .onChangeCompat(of: isAccountFocused) { wasFocused, isFocused in
                    if wasFocused && !isFocused { runLookupIfNeeded() }
                }
            }

            if isLookingUp {
                HStack(spacing: 8) {
                    ProgressView().tint(AppColor.brand)
                    Text("Đang tra cứu tên chủ tài khoản...")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)
                }
            } else if let lookupError {
                FieldError(message: lookupError, alignment: .leading)
            } else if !manualHolderName.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tên chủ tài khoản")
                        .font(AppFont.beVietnamPro(12))
                        .foregroundStyle(AppColor.payMuted)
                    Text(manualHolderName)
                        .font(AppFont.beVietnamPro(15, .semibold))
                        .foregroundStyle(AppColor.payInk)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func bankChip(_ bank: Bank) -> some View {
        let isSelected = bank.bin == selectedBin
        return Button {
            selectedBin = bank.bin
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AppColor.brand : Color.white)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Text(bank.shortName.prefix(4))
                            .font(AppFont.beVietnamPro(11, .bold))
                            .foregroundStyle(isSelected ? .white : AppColor.payInk)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.clear : AppColor.payInputBorder, lineWidth: 1)
                    }
                Text(bank.shortName)
                    .font(AppFont.beVietnamPro(11))
                    .foregroundStyle(AppColor.payInk)
                    .lineLimit(1)
            }
            .frame(width: 64)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func accTypeToggle(title: String, index: Int) -> some View {
        let isSelected = accType == index
        return Button {
            accType = index
            manualHolderName = ""
            lastLookedUp = nil
            runLookupIfNeeded()
        } label: {
            Text(title)
                .font(AppFont.beVietnamPro(13, .semibold))
                .foregroundStyle(isSelected ? .white : AppColor.payMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? AppColor.brand : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Số tiền

    /// Ô số tiền kiểu Kotlin: hộp xám bo 14, số 22pt đậm, hậu tố "VNĐ" cố định bên phải,
    /// viền chuyển đỏ khi vượt số dư.
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Số tiền muốn rút")
                .font(AppFont.beVietnamPro(11, .medium))
                .foregroundStyle(WdColor.muted)
                .tracking(1.4)

            if let balance = wallet.balance {
                Text("Số dư khả dụng: \(Int(balance).vndGrouped) VNĐ")
                    .font(AppFont.beVietnamPro(13, .medium))
                    .foregroundStyle(WdColor.muted)
            }

            HStack(spacing: 8) {
                // Hiển thị thuần + con trỏ nháy tự vẽ, KHÔNG phải `TextField`: ô này dùng bàn
                // phím số tự vẽ (có phím "000" để gõ tắt hàng nghìn) nên không được để bàn
                // phím hệ thống bật lên đè lên nó.
                HStack(spacing: 1) {
                    if amountText.isEmpty {
                        Text("Nhập số tiền")
                            .font(AppFont.beVietnamPro(18))
                            .foregroundStyle(WdColor.muted)
                    } else {
                        Text(Int(amount).vndGrouped)
                            .font(AppFont.beVietnamPro(22, .bold))
                            .foregroundStyle(WdColor.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if isAmountFocused {
                        BlinkingCaret(color: WdColor.ink, height: 22)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    KeypadDismissGuard.markHandled()
                    isAmountFocused = true
                }

                Text("VNĐ")
                    .font(AppFont.beVietnamPro(16, .bold))
                    .foregroundStyle(WdColor.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(WdColor.amountBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(overLimit || overMaxPerWithdraw ? WdColor.error : WdColor.line, lineWidth: 1)
            }

            if overMaxPerWithdraw {
                Text("Số tiền rút tối đa 1 lần là 10.000.000đ")
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(WdColor.error)
            } else if overLimit {
                Text("Số tiền vượt quá số dư khả dụng")
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(WdColor.error)
            }

            amountSuggestionChips
        }
    }

    /// Gợi ý theo số ĐANG GÕ — xem `TransferLimits.amountSuggestions`.
    private var amountSuggestions: [Int64] {
        // Chưa gõ gì -> mệnh giá mặc định để chạm 1 phát là xong.
        guard amount > 0 else { return [10_000, 100_000, 1_000_000] }
        return TransferLimits.amountSuggestions(for: amount)
    }

    @ViewBuilder
    private var amountSuggestionChips: some View {
        if !amountSuggestions.isEmpty {
            HStack(spacing: 8) {
                ForEach(amountSuggestions, id: \.self) { value in
                    Button {
                        amountText = String(value)
                    } label: {
                        Text("\(Int(value).vndGrouped)đ")
                            .font(AppFont.beVietnamPro(13, .bold))
                            .foregroundStyle(WdColor.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .overlay {
                                Capsule().strokeBorder(WdColor.line, lineWidth: 1.5)
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
    }

    // MARK: - Nhập số tiền (bàn phím tự vẽ)

    private func appendDigits(_ digits: String) {
        // Chặn số 0 dẫn đầu và giới hạn 9 chữ số, giống các màn nhập tiền khác.
        let combined = amountText.isEmpty && digits.allSatisfy { $0 == "0" }
            ? ""
            : amountText + digits
        amountText = String(combined.prefix(9))
    }

    private func backspaceDigit() {
        guard !amountText.isEmpty else { return }
        amountText.removeLast()
    }


    // MARK: - Continue

    private var continueBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(WdColor.line).frame(height: 1)

            Button {
                Task { await submitWithdraw() }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        // Khi disable dùng chữ xám đậm (không phải trắng) để không chìm
                        // vào nền xám — mirror ghi chú trong WithdrawScreen.kt.
                        Text("Xác nhận")
                            .font(AppFont.beVietnamPro(16, .bold))
                            .foregroundStyle(canContinue ? Color.white : WdColor.muted)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(canContinue ? WdColor.green : WdColor.disabled)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canContinue || isSubmitting)
            .padding(16)
        }
        .background(Color.white)
    }

    // MARK: - Lookup (nhánh chưa liên kết)

    private func runLookupIfNeeded() {
        guard !isLinked, let bin = selectedBin, accountNumber.count >= 4 else { return }
        let key = (bin, accountNumber, accType)
        if let lastLookedUp, lastLookedUp == key { return }
        lastLookedUp = key
        lookupError = nil
        Task {
            isLookingUp = true
            defer { isLookingUp = false }
            do {
                manualHolderName = try await TransferService.verifyBeneficiary(
                    VerifyBeneficiaryRequest(accNo: accountNumber, bankNo: Int(bin), accType: accType)
                )
            } catch let error as APIError {
                manualHolderName = ""
                lookupError = error.message
            } catch {
                manualHolderName = ""
                lookupError = "Không tra cứu được tên chủ tài khoản"
            }
        }
    }

    // MARK: - Submit

    private func submitWithdraw() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let accNo = effectiveAccNo
        let bankNo = isLinked ? (wallet.bankNo ?? "") : (selectedBin ?? "")

        let request = WithdrawRequest(
            idempotencyKey: idempotencyKey, accNo: accNo, accType: isLinked ? 0 : accType,
            bankNo: bankNo, transAmount: Int(amount)
        )

        do {
            // Mốc đo thời gian xử lý THẬT để biên lai không phải bịa "2,0 giây".
            submitStartedAt = Date()
            let result = try await TransferService.withdraw(request)
            await handleResult(result, accNo: accNo, bankNo: bankNo)
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Đã có lỗi xảy ra, vui lòng thử lại"
        }
    }

    /// Số tài khoản nhận tiền rút: đã liên kết thì lấy từ ví, chưa thì lấy STK vừa nhập.
    /// Tách ra computed vì cả 3 chỗ (rút, xác thực PIN, xác thực Face ID) phải dùng CÙNG giá trị
    /// — chữ ký sinh trắc ký chính số này nên lệch một chỗ là BE verify sai.
    private var effectiveAccNo: String {
        isLinked ? (wallet.accNo ?? "") : accountNumber
    }

    private var pendingRecipientName: String {
        isLinked ? linkedBankName : (bankCache.bank(bin: selectedBin)?.shortName ?? "Ngân hàng")
    }

    /// Xác thực rút tiền bằng Face ID — ký số tiền + số tài khoản nhận.
    private func submitBiometric() async {
        guard let transactionId = pendingTransactionId else { return }
        let accNo = effectiveAccNo
        let bankNo = isLinked ? (wallet.bankNo ?? "") : (selectedBin ?? "")
        do {
            submitStartedAt = Date()
            let result = try await BiometricService.verifyTransfer(
                transactionId: transactionId,
                amount: amount,
                recipient: accNo
            )
            await handleResult(result, accNo: accNo, bankNo: bankNo)
        } catch BiometricKeyError.userCancelled {
            biometricError = nil
        } catch BiometricKeyError.keyInvalidated {
            BiometricKeyStore.deleteKey()
            useBiometric = false
            pinError = "Face ID đã thay đổi, vui lòng nhập mật khẩu và bật lại trong Cá nhân"
        } catch let error as BiometricKeyError {
            biometricError = error.localizedDescription
        } catch let error as APIError {
            // 403 = không thể sửa bằng quét lại (còn cooling-off, chưa đăng ký, bị khoá).
            if case .server(let code, let message) = error, code == 403 {
                useBiometric = false
                pinError = message
            } else {
                biometricError = error.message
            }
        } catch {
            biometricError = "Đã có lỗi xảy ra, vui lòng thử lại"
        }
    }

    private func submitPin(_ pin: String) async {
        guard let transactionId = pendingTransactionId else { return }
        let accNo = effectiveAccNo
        let bankNo = isLinked ? (wallet.bankNo ?? "") : (selectedBin ?? "")
        do {
            // Đo lại từ lúc gửi PIN — thời gian gõ PIN không phải thời gian xử lý.
            submitStartedAt = Date()
            let result = try await TransferService.verifyTransfer(
                VerifyTransferRequest(password: pin, transactionId: transactionId)
            )
            await handleResult(result, accNo: accNo, bankNo: bankNo)
        } catch let error as APIError {
            pinError = error.message
        } catch {
            pinError = "Đã có lỗi xảy ra, vui lòng thử lại"
        }
    }

    private func handleResult(_ result: TransferResult, accNo: String, bankNo: String) async {
        if result.isPending, let transactionId = result.transactionId {
            pendingTransactionId = transactionId
            return
        }
        pendingTransactionId = nil
        let elapsed = submitStartedAt.map { Date().timeIntervalSince($0) }
        await WalletStore.shared.refresh(force: true)
        let bankName = BankCache.shared.bank(bin: bankNo)?.shortName ?? "Ngân hàng"

        // Chèn lạc quan để Home/Lịch sử thấy giao dịch NGAY, không phải chờ một vòng gọi
        // API. Đặt ở đây nên phủ CẢ ba đường thành công (rút thẳng, PIN, Face ID) vì cả ba
        // đều đổ về hàm này. Không cần rollback: chỉ chạy khi BE đã xác nhận thành công,
        // và bản ghi thật từ server sẽ thay thế nó qua khử trùng `bkTransId` trong
        // `TransactionStore.prepend`.
        TransactionStore.shared.prepend(
            TransactionEntity(
                id: result.bkTransId ?? result.transId ?? UUID().uuidString,
                type: TransactionType.withdraw.rawValue,
                amount: String(amount),
                fee: result.feeAmount.map(String.init) ?? "0",
                description: nil,
                cachedBalanceAfter: nil,
                bkTransId: result.bkTransId ?? result.transId,
                benBankNo: bankNo,
                benAccNo: accNo,
                // Nhánh chưa liên kết rút về TK vừa nhập tay, tên chủ TK nằm ở
                // `manualHolderName` — lấy `wallet.accName` là tên của TK ĐÃ LIÊN KẾT, sai
                // người nhận trên dòng vừa chèn.
                benAccName: isLinked ? wallet.accName : manualHolderName,
                benBankName: bankName,
                status: TransactionStatus.success.rawValue,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
        )
        onSuccess(
            // Rút tiền cũng đổ về TK ngân hàng nên dùng nhánh `.bank` của biên lai.
            TransferSuccessInfo(
                kind: .bank, amount: amount,
                recipientName: wallet.accName ?? "Tài khoản của bạn",
                bankName: bankName, accountNumber: accNo,
                noteLabel: "Nội dung", note: "Rút tiền về ngân hàng liên kết",
                transactionCode: result.bkTransId ?? result.transId,
                elapsedSeconds: elapsed,
                isProcessing: result.status == "PENDING",
                feeAmount: result.feeAmount
            )
        )
    }
}

#Preview {
    WithdrawView(onBack: {}, onSuccess: { _ in })
}
