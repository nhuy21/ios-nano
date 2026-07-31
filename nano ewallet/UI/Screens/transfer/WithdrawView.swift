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

@MainActor
struct WithdrawView: View {
    let onBack: () -> Void
    let onSuccess: (TransferSuccessInfo) -> Void

    /// Hạn mức 1 lần rút — mirror MAX_AMOUNT_PER_WITHDRAW (WithdrawScreen.kt), khớp
    /// wallets.limitFace mặc định phía BE (Bảo Kim từ chối thẳng nếu vượt, mã lỗi 128).
    private static let maxAmountPerWithdraw: Int64 = 10_000_000

    @StateObject private var wallet = WalletStore.shared
    @StateObject private var bankCache = BankCache.shared

    @State private var amountText = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    @State private var pendingTransactionId: String?
    @State private var pinError: String?

    // Nhánh chưa liên kết ngân hàng — chọn bank + nhập STK, verify trước khi rút.
    @State private var selectedBin: String?
    @State private var accountNumber = ""
    @State private var accType = 0
    @State private var manualHolderName = ""
    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var lastLookedUp: (bin: String, account: String, accType: Int)?
    @State private var showAllBanks = false

    @FocusState private var isAmountFocused: Bool
    @FocusState private var isAccountFocused: Bool

    private let idempotencyKey = TransferService.newIdempotencyKey()

    private var amount: Int64 { Int64(amountText) ?? 0 }

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

    private var overMaxPerWithdraw: Bool { amount > Self.maxAmountPerWithdraw }

    private var canContinue: Bool { amount > 0 && !overMaxPerWithdraw && hasBeneficiary }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    destinationSection
                    amountSection
                    if let errorMessage {
                        FieldError(message: errorMessage, alignment: .leading)
                    }
                }
                .padding(16)
            }
            continueBar
        }
        .background(Color(hex: 0xF7F8FA))
        .task {
            await wallet.refresh()
            _ = await bankCache.get()
        }
        .sheet(isPresented: $showAllBanks) {
            BankPickerSheet(banks: sortedBanks, selectedBin: $selectedBin, onDismiss: { showAllBanks = false })
        }
        .sheet(isPresented: pendingTransactionIdBinding) {
            PinEntrySheet(
                amountText: Int(amount).vndFormatted,
                recipientName: isLinked ? linkedBankName : (bankCache.bank(bin: selectedBin)?.shortName ?? "Ngân hàng"),
                onSubmit: submitPin,
                onCancel: { pendingTransactionId = nil },
                externalError: $pinError
            )
        }
        .onChange(of: selectedBin) { _, _ in runLookupIfNeeded() }
    }

    private var pendingTransactionIdBinding: Binding<Bool> {
        Binding(get: { pendingTransactionId != nil }, set: { if !$0 { pendingTransactionId = nil } })
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text("RÚT TIỀN")
                .font(AppFont.beVietnamPro(15, .bold))
                .foregroundStyle(.white)
                .tracking(2)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x2ECB6E), Color(hex: 0x00A24A)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Đích rút

    @ViewBuilder
    private var destinationSection: some View {
        if isLinked {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Rút về")
                HStack(spacing: 12) {
                    Circle()
                        .fill(AppColor.brandSoft)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Text(String(linkedBankName.prefix(1)).uppercased())
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AppColor.brand)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wallet.accName ?? "Tài khoản của bạn")
                            .font(AppFont.beVietnamPro(15, .semibold))
                            .foregroundStyle(AppColor.payInk)
                        Text("\(linkedBankName) • \(wallet.accNo ?? "")")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColor.payMuted)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        } else {
            manualDestinationSection
        }
    }

    private var manualDestinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FieldLabel(text: "Ngân hàng").padding(.bottom, 0)
                Spacer()
                Button("Xem tất cả") { showAllBanks = true }
                    .buttonStyle(.plain)
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
                .numericKeyboardToolbar(label: "Xong") { isAccountFocused = false }
                .onChange(of: isAccountFocused) { wasFocused, isFocused in
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
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isSelected ? .white : AppColor.payInk)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.clear : AppColor.payInputBorder, lineWidth: 1)
                    }
                Text(bank.shortName)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.payInk)
                    .lineLimit(1)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
    }

    // MARK: - Số tiền

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Số tiền")
            AppTextField(
                text: amountFieldBinding, placeholder: "0",
                keyboardType: .numberPad, submitLabel: .done, digitsOnly: true
            )
            .focused($isAmountFocused)
            .numericKeyboardToolbar(label: "Xong") { isAmountFocused = false }

            if overMaxPerWithdraw {
                FieldError(message: "Số tiền rút tối đa 1 lần là 10.000.000đ", alignment: .leading)
            } else if overLimit {
                FieldError(message: "Số tiền vượt quá số dư khả dụng", alignment: .leading)
            }
        }
    }

    private var amountFieldBinding: Binding<String> {
        Binding(
            get: { amount > 0 ? Int(amount).vndFormatted.replacingOccurrences(of: " đ", with: "") : "" },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                amountText = String(digits.prefix(9))
            }
        )
    }

    // MARK: - Continue

    private var continueBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(AppColor.line).frame(height: 1)
            PrimaryButton(
                title: "Rút tiền", loadingTitle: "Đang xử lý...",
                isLoading: isSubmitting, isEnabled: canContinue
            ) {
                Task { await submitWithdraw() }
            }
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
                manualHolderName = try await BankService.lookupAccount(bin: bin, accountNumber: accountNumber)
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

        let accNo = isLinked ? (wallet.accNo ?? "") : accountNumber
        let bankNo = isLinked ? (wallet.bankNo ?? "") : (selectedBin ?? "")

        let request = WithdrawRequest(
            idempotencyKey: idempotencyKey, accNo: accNo, accType: isLinked ? 0 : accType,
            bankNo: bankNo, transAmount: Int(amount)
        )

        do {
            let result = try await TransferService.withdraw(request)
            await handleResult(result, accNo: accNo, bankNo: bankNo)
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Đã có lỗi xảy ra, vui lòng thử lại"
        }
    }

    private func submitPin(_ pin: String) async {
        guard let transactionId = pendingTransactionId else { return }
        let accNo = isLinked ? (wallet.accNo ?? "") : accountNumber
        let bankNo = isLinked ? (wallet.bankNo ?? "") : (selectedBin ?? "")
        do {
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
        await WalletStore.shared.refresh(force: true)
        let bankName = BankCache.shared.bank(bin: bankNo)?.shortName ?? "Ngân hàng"
        onSuccess(
            TransferSuccessInfo(
                amount: amount, recipientName: wallet.accName ?? "Tài khoản của bạn",
                recipientDetail: "\(bankName) • \(accNo)",
                noteLabel: "Nội dung", note: "Rút tiền về ngân hàng liên kết"
            )
        )
    }
}

#Preview {
    WithdrawView(onBack: {}, onSuccess: { _ in })
}
