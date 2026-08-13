//
//  BankTransferView.swift
//  nano ewallet
//
//  Mirror TransferScreen.kt (nhánh chuyển khoản ngân hàng) — MỘT màn gộp người
//  nhận + số tiền + nội dung, thay cho 2 màn tách rời trước đây (chọn bank/STK rồi
//  mới sang màn nhập tiền). Cả hai ô số đều dùng bàn phím TỰ VẼ, nhưng khác bản: số
//  tài khoản dùng `PlainNumericKeypad` (không có phím "000" — số đếm từng chữ), số
//  tiền dùng `NumericKeypad` (có "000" để gõ tắt hàng nghìn).
//
//  2 chế độ trên cùng màn (mirror `recipientLocked` bên Kotlin):
//   - `initialDraft == nil`: nhập tay — chọn bank (mở sheet), gõ STK, tự tra tên.
//   - `initialDraft != nil`: người nhận đã có sẵn (QR / danh bạ / pay link) — thẻ
//     khoá, có thể kèm số tiền/nội dung cố định nếu QR "động".
//

import SwiftUI
import UIKit
import Combine

@MainActor
struct BankTransferView: View {
    let onBack: () -> Void
    let onHome: () -> Void
    var initialDraft: BankTransferDraft?
    let onSuccess: (TransferSuccessInfo) -> Void
    var onOpenContacts: () -> Void = {}

    private static let maxAmount: Int64 = 999_999_999
    private static let quickAmounts: [(label: String, value: Int64)] = [
        ("50k", 50_000), ("100k", 100_000), ("200k", 200_000), ("500k", 500_000),
    ]
    /// Neo cuộn tới phần số tiền khi bàn phím mở — xem `ScrollViewReader` trong `body`.
    private static let amountAnchor = "amountSection"
    private static let contentSuggestions = ["Chuyển tiền", "Trả tiền ăn", "Gửi tặng"]
    private static let bankPriority = [
        "Vietcombank", "BIDV", "VietinBank", "Agribank", "Techcombank",
        "MBBank", "ACB", "VPBank", "TPBank", "Sacombank",
    ]

    @StateObject private var bankCache = BankCache.shared
    @StateObject private var wallet = WalletStore.shared
    @StateObject private var authStore = AuthStore.shared
    @StateObject private var beneficiaryStore = BeneficiaryStore.shared

    private let recipientLocked: Bool
    private let amountEditable: Bool
    private let contentEditable: Bool
    private let payLinkToken: String?

    @State private var selectedBin: String?
    @State private var accountNumber: String
    @State private var accType: Int
    @State private var holderName: String
    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var lastLookedUp: (bin: String, account: String, accType: Int)?
    @State private var showBankSheet = false
    /// Bàn phím số tự vẽ của ô SỐ TÀI KHOẢN đang hiện hay không. Không phải `@FocusState` vì
    /// bàn phím này là SwiftUI thuần — `endEditing` ở tầng UIWindow không đụng tới được.
    /// Dùng bàn phím tự vẽ thay bàn phím hệ thống để có phím "Tiếp" ngay trong bàn phím.
    @State private var isAccountFocused = false

    /// Chỉ điều khiển bàn phím số tự vẽ của Ô SỐ TIỀN — số tài khoản có bàn phím riêng qua
    /// `isAccountFocused`, và là bản `Plain` không có phím "000".
    @State private var isAmountFocused = false

    @State private var amount: Int64
    @State private var content: String
    @FocusState private var isContentFocused: Bool

    /// Mặc định TẮT: chuyển khoản ngân hàng phần lớn là chuyển một lần cho người lạ (trả
    /// tiền hàng, chia hoá đơn), bật sẵn thì danh bạ đầy những tài khoản không bao giờ dùng
    /// lại. Muốn lưu thì bật — chủ động một chạm, hơn là phải nhớ tắt mỗi lần.
    @State private var saveRecipient = false

    @StateObject private var speech = SpeechRecognizerService()
    /// Báo ngắn khi nghe không ra số / mic không dùng được.
    @State private var voiceHint: String?
    /// Đang nhờ backend bóc lại số tiền sau khi regex trượt.
    @State private var isParsingSpeech = false

    @State private var pendingTransactionId: String?
    @State private var pinError: String?

    /// Xác thực giao dịch pending bằng Face ID thay vì nhập mật khẩu. Bật khi thiết bị đã đăng
    /// ký khoá sinh trắc; người dùng bấm "Dùng mật khẩu" thì tắt để rơi về `PinEntrySheet`.
    /// Chỉ đọc `hasKey()` (không gọi API, không bật Face ID) nên gán được ngay lúc dựng view.
    @State private var useBiometric = BiometricKeyStore.hasKey()
    @State private var biometricError: String?
    @State private var isSubmitting = false
    /// Mốc bắt đầu gọi API chuyển tiền — để biên lai hiện thời gian xử lý thật.
    @State private var submitStartedAt: Date?
    @State private var transferError: String?

    private let idempotencyKey = TransferService.newIdempotencyKey()

    init(
        onBack: @escaping () -> Void,
        onHome: @escaping () -> Void,
        initialDraft: BankTransferDraft? = nil,
        onSuccess: @escaping (TransferSuccessInfo) -> Void,
        onOpenContacts: @escaping () -> Void = {}
    ) {
        self.onBack = onBack
        self.onHome = onHome
        self.initialDraft = initialDraft
        self.onSuccess = onSuccess
        self.onOpenContacts = onOpenContacts

        recipientLocked = initialDraft != nil
        amountEditable = initialDraft?.amountEditable ?? true
        contentEditable = initialDraft?.contentEditable ?? true
        payLinkToken = initialDraft?.payLinkToken

        _selectedBin = State(initialValue: initialDraft?.bin)
        _accountNumber = State(initialValue: initialDraft?.accNo ?? "")
        _accType = State(initialValue: initialDraft?.accType ?? 0)
        _holderName = State(initialValue: initialDraft?.holderName ?? "")
        _amount = State(initialValue: initialDraft?.prefillAmount.map(Int64.init) ?? 0)
        _content = State(initialValue: initialDraft?.prefillContent ?? "")
    }

    // MARK: - Derived

    private var sortedBanks: [Bank] {
        bankCache.banks.sorted { a, b in
            let ia = Self.bankPriority.firstIndex(of: a.shortName) ?? Int.max
            let ib = Self.bankPriority.firstIndex(of: b.shortName) ?? Int.max
            return ia < ib
        }
    }

    private var selectedBank: Bank? { bankCache.banks.first { $0.bin == selectedBin } }

    /// Người nhận đã nằm trong danh bạ -> ẩn luôn toggle "Lưu vào danh bạ".
    /// Khớp theo CẢ số tài khoản LẪN ngân hàng: cùng một dãy số vẫn là hai người khác nhau
    /// ở hai nhà băng khác nhau.
    private var alreadySaved: Bool {
        beneficiaryStore.beneficiaries.contains {
            $0.type == .bankAccount && $0.accNo == accountNumber && $0.bankNo == selectedBin
        }
    }

    private var bankNameForSubmit: String { selectedBank?.shortName ?? initialDraft?.bankName ?? "Ngân hàng" }

    private var recipientReady: Bool {
        recipientLocked || (selectedBin != nil && !accountNumber.isEmpty && !holderName.isEmpty)
    }
    /// Số tiền chuyển tối thiểu. Chặn ở đây thay vì để backend từ chối: người dùng gõ số rồi
    /// bấm Tiếp tục, chờ một lượt gọi API mới biết là không được — mà lỗi từ server lại là
    /// câu chung chung.
    ///
    /// LƯU Ý cho ai sửa sau: hiện KHÔNG có ngưỡng này ở backend, nên đây là chặn CHỈ Ở APP.
    /// Các đường vào khác — trợ lý giọng nói, OneTouch điền sẵn, link nhận tiền — nếu không
    /// đi qua màn này thì vẫn gửi được số nhỏ hơn. Muốn chắc thì phải đặt ở backend.
    private static let minAmount: Int64 = 2_000

    /// Chuyển được khi số tiền ĐẠT MỨC TỐI THIỂU và đã có người nhận. Phải chặn cả nút chứ
    /// không chỉ hiện chữ đỏ: để nút bấm được thì cảnh báo thành ra trang trí, người dùng vẫn
    /// đi tiếp rồi bị server từ chối bằng một câu chung chung.
    private var canContinue: Bool { amount >= Self.minAmount && recipientReady }

    /// Dưới mức tối thiểu. Chỉ tính khi ĐÃ gõ số: lúc ô còn trống thì chưa có gì sai, hiện
    /// cảnh báo ngay là mắng người dùng trước khi họ kịp làm gì.
    private var belowMin: Bool { amount > 0 && amount < Self.minAmount }

    private var overLimit: Bool {
        guard amount > 0, let balance = wallet.balance else { return false }
        return amount > balance
    }

    /// Ưu tiên cảnh báo TỐI THIỂU khi cả hai cùng đúng. Hai điều kiện này chồng nhau được: số
    /// dư dưới 2.000đ thì gõ số nào cũng vừa dưới mức tối thiểu vừa vượt số dư. Lúc đó "Số
    /// tiền tối thiểu" nói đúng việc phải làm hơn là "Vượt số dư".
    private var amountWarning: String? {
        if belowMin { return "Số tiền tối thiểu là \(Int(Self.minAmount).vndFormatted)" }
        if overLimit { return "Vượt số dư" }
        return nil
    }

    private var defaultContent: String {
        let sender = authStore.userFullName?.trimmingCharacters(in: .whitespaces)
        guard let sender, !sender.isEmpty else { return "Chuyển tiền qua ví Nano" }
        return "\(sender) chuyển tiền qua ví Nano"
    }

    private var effectiveContent: String {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Chuyen tien" : trimmed
    }

    private var amountText: String { amount == 0 ? "" : Int(amount).vndGrouped }

    private var amountFontSize: CGFloat {
        switch amount == 0 ? 1 : String(amount).count {
        case ...3: return 44
        case 4...5: return 40
        case 6...7: return 34
        case 8: return 30
        default: return 26
        }
    }

    /// Gõ số ngắn (1-3 chữ số) -> gợi ý thêm số 0 thay vì phải gõ hết, mirror Kotlin.
    private var amountSuggestions: [Int64] {
        guard (1...999).contains(amount) else { return [] }
        // Lọc CẢ HAI đầu: gợi ý dưới mức tối thiểu thì app tự đề xuất một số rồi tự chặn —
        // gõ "1" sẽ gợi ý 1.000, mà 1.000 nay dưới ngưỡng, nhìn như app lỗi.
        return [amount * 1_000, amount * 10_000, amount * 100_000]
            .filter { $0 >= Self.minAmount && $0 <= Self.maxAmount }
    }

    private var bankSheetBinding: Binding<String?> {
        Binding(
            get: { selectedBin },
            set: { newBin in
                if newBin != selectedBin {
                    holderName = ""; lookupError = nil; lastLookedUp = nil
                }
                selectedBin = newBin
            }
        )
    }

    private var pendingTransactionIdBinding: Binding<Bool> {
        Binding(get: { pendingTransactionId != nil }, set: { if !$0 { pendingTransactionId = nil } })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // `ScrollViewReader` để cuộn tới phần số tiền khi bàn phím mở: bàn phím số tự vẽ
            // chiếm 216pt ở đáy, không cuộn thì nó che mất hàng chips gợi ý ngay dưới ô —
            // người dùng không biết là có gợi ý.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        sourceAccountCard
                        recipientCard
                        amountSection
                            .id(Self.amountAnchor)
                        contentSection
                        // Chỉ hiện khi đã chọn đủ ngân hàng + số TK và người nhận CHƯA có
                        // trong danh bạ — bật sẵn toggle lúc chưa biết lưu ai thì vô nghĩa.
                        if recipientReady, !alreadySaved {
                            saveToggle
                        }
                    }
                    .padding(16)
                }
                .onChangeNewCompat(of: isAmountFocused) { focused in
                    guard focused else { return }
                    // Hoãn một nhịp: `safeAreaInset` chèn bàn phím vào cùng lượt render này,
                    // cuộn ngay thì tính theo khung CŨ (chưa trừ 216pt) nên vẫn thiếu chỗ.
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.25)) {
                            // `.bottom`: kéo đáy phần số tiền (tức hàng chips) lên sát mép
                            // trên bàn phím. Canh `.top` thì chips vẫn nằm dưới vùng bị che.
                            proxy.scrollTo(Self.amountAnchor, anchor: .bottom)
                        }
                    }
                }
            }
            footer
        }
        .screenBackground(Color.white)
        // Bàn phím HỆ THỐNG (ô nội dung) đã tự ẩn nhờ cử chỉ gắn ở tầng UIWindow (xem
        // DismissKeyboardOnTap). Ở đây lo hai bàn phím số tự vẽ: ô số TK và ô số tiền.
        // Cất bàn phím ô số TK cũng là lúc tra tên (xem onChange của `isAccountFocused`).
        .contentShape(Rectangle())
        .onTapGesture {
            isAmountFocused = false
            isAccountFocused = false
        }
        .task { _ = await bankCache.get() }
        .task {
            // Người nhận đã khoá sẵn (QR / danh bạ / pay link) thì vào là đọc số tiền ngay.
            // Luồng nhập tay không bật ở đây — đợi tra ra tên (xem runLookupIfNeeded).
            guard recipientLocked else { return }
            await startVoiceIfReady()
        }
        .onAppear { speech.onResult = { candidates in handleSpeech(candidates) } }
        .onDisappear { speech.stop() }
        // Có số tiền rồi thì mọi lời nhắc của mic đều VÔ NGHĨA — xoá ngay.
        //
        // Đặt ở `onChange` của `amount` chứ không rải vào từng chỗ điền số: bàn phím số,
        // mệnh giá gợi ý, mic, prefill từ QR/pay link đều đi qua đây, nên không sót đường
        // nào. Không xoá thì hint "Chưa nghe được gì, thử lại nhé" vẫn treo dưới ô tiền
        // trong khi người dùng đã tự gõ xong số — như đang báo lỗi việc họ không làm sai.
        .onChangeNewCompat(of: amount) { newValue in
            if newValue > 0 { voiceHint = nil }
        }
        .onAppear {
            if initialDraft?.prefillContent == nil { content = defaultContent }
        }
        .onChangeCompat(of: selectedBin) { _, _ in
            if holderName.isEmpty { runLookupIfNeeded() }
        }
        .onChangeCompat(of: isAccountFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused { runLookupIfNeeded() }
            // Quay lại sửa số TK thì cất bàn phím số của ô TIỀN đi, không thì hai bàn phím
            // chồng nhau. Ô nội dung dùng bàn phím HỆ THỐNG nên cũng phải nhả focus, nếu
            // không nó nằm đè lên bàn phím tự vẽ. Mic tắt vì người nhận đang được nhập lại —
            // tra cứu xong `startVoiceIfReady` sẽ bật lại.
            if isFocused {
                isAmountFocused = false
                isContentFocused = false
                stopListening()
            }
        }
        .sheet(isPresented: $showBankSheet) {
            BankPickerSheet(banks: sortedBanks, selectedBin: bankSheetBinding, onDismiss: { showBankSheet = false })
        }
        .sheet(isPresented: pendingTransactionIdBinding) {
            if useBiometric {
                BiometricAuthSheet(
                    amountText: Int(amount).vndFormatted,
                    recipientName: holderName,
                    onAuthenticate: submitBiometric,
                    onUsePassword: {
                        // Chỉ đổi sheet, KHÔNG xoá pendingTransactionId — giao dịch pending vẫn
                        // còn hạn (BE cho 120s) nên nhập mật khẩu xong là hoàn tất được luôn.
                        biometricError = nil
                        useBiometric = false
                    },
                    onCancel: { pendingTransactionId = nil },
                    externalError: $biometricError
                )
            } else {
                PinEntrySheet(
                    amountText: Int(amount).vndFormatted,
                    recipientName: holderName,
                    onSubmit: submitPin,
                    onCancel: { pendingTransactionId = nil },
                    externalError: $pinError
                )
            }
        }
        .overlay { if isSubmitting { ProcessingOverlay() } }
        .overlay {
            if let transferError {
                TransferErrorOverlay(message: transferError) { self.transferError = nil }
            }
        }
    }

    // MARK: - Header

    /// Header nền TRẮNG, chữ mực đen — mirror TransferScreen.kt L878-903 (không phải dải
    /// gradient xanh: gradient chỉ dùng ở màn thành công).
    private var header: some View {
        HStack {
            headerCircleButton(systemImage: "arrow.left", action: onBack, accessibilityLabel: "Quay lại")
            Spacer()
            Text("Chuyển tiền")
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(AppColor.payInk)
            Spacer()
            headerCircleButton(systemImage: "house.fill", action: onHome, accessibilityLabel: "Trang chủ")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    /// Nút tròn 38pt nền xám nhạt `#F1F3F5`, icon mực đen — mirror `HeaderCircleButton`
    /// (TransferScreen.kt L425-450). Không shadow: trên nền trắng thì viền xám là đủ.
    private func headerCircleButton(systemImage: String, action: @escaping () -> Void, accessibilityLabel: String) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColor.payInk)
                .frame(width: 38, height: 38)
                .background(Color(hex: 0xF1F3F5))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Ví nguồn (số ví người gửi + số dư)

    private var sourceAccountCard: some View {
        SourceAccountCard(username: wallet.bkUsername, balance: wallet.balance)
    }

    // MARK: - Người nhận

    private var recipientCard: some View {
        VStack(spacing: 0) {
            bankHeaderRow
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 14)
                if recipientLocked {
                    lockedAccountBlock
                } else {
                    manualAccountBlock
                }
                Spacer().frame(height: 14)
            }
            .padding(.horizontal, 16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(cardBorderColor, lineWidth: 1)
        }
        .shadow(color: Color(hex: 0x111C17).opacity(0.08), radius: 3, x: 0, y: 1)
    }

    private var cardBorderColor: Color {
        selectedBank?.brandColor.flatMap(Color.init(hexString:)) ?? AppColor.line
    }

    private var bankHeaderRow: some View {
        let bank = selectedBank
        let brand = bank?.brandColor.flatMap(Color.init(hexString:)) ?? Color(hex: 0xF1F3F5)
        let onBrand: Color = bank == nil ? AppColor.payInk : (brand.isLight ? AppColor.payInk : .white)
        return HStack(spacing: 12) {
            Circle()
                .fill(Color.white)
                .frame(width: 42, height: 42)
                .overlay { BankLogoView(bank: bank) }
            if let bank {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bank.shortName)
                        .font(AppFont.beVietnamPro(16, .bold))
                        .foregroundStyle(onBrand)
                        .lineLimit(1)
                    Text(bank.name)
                        .font(AppFont.beVietnamPro(12))
                        .foregroundStyle(onBrand.opacity(0.85))
                        .lineLimit(2)
                }
            } else {
                Text("Chọn ngân hàng")
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.payInk)
            }
            Spacer()
            if recipientLocked {
                Circle()
                    .fill(Color(hex: 0x12A67E))
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(onBrand)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(brand)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !recipientLocked else { return }
            isContentFocused = false
            isAccountFocused = false
            isAmountFocused = false
            showBankSheet = true
        }
    }

    private var lockedAccountBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(accType == 1 ? "Số thẻ" : "Số tài khoản")
                .font(AppFont.beVietnamPro(12.5, .medium))
                .foregroundStyle(AppColor.payMuted)
            Spacer().frame(height: 8)
            Text(accountNumber.isEmpty ? "—" : accountNumber)
                .font(AppFont.beVietnamPro(17, .bold))
                .foregroundStyle(AppColor.payInk)
                .lineLimit(1)
            Spacer().frame(height: 14)
            Rectangle().fill(AppColor.line).frame(height: 1)
            Spacer().frame(height: 14)
            Text("Tên người nhận")
                .font(AppFont.beVietnamPro(12.5, .medium))
                .foregroundStyle(AppColor.payMuted)
            Spacer().frame(height: 6)
            Text(holderName.isEmpty ? "—" : holderName.uppercased())
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)
                .lineLimit(1)
        }
    }

    private var manualAccountBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 0) {
                    Text(accType == 1 ? "Số thẻ" : "Số tài khoản")
                        .font(AppFont.beVietnamPro(12.5, .medium))
                        .foregroundStyle(AppColor.payMuted)
                    Text(" *")
                        .font(AppFont.beVietnamPro(12.5))
                        .foregroundStyle(AppColor.error)
                }
                Spacer()
                accTypeToggle
            }
            Spacer().frame(height: 8)
            accountRow

            if isLookingUp || !holderName.isEmpty || lookupError != nil {
                Spacer().frame(height: 14)
                Rectangle().fill(AppColor.line).frame(height: 1)
                Spacer().frame(height: 14)
                Text("Tên người nhận")
                    .font(AppFont.beVietnamPro(12.5, .medium))
                    .foregroundStyle(AppColor.payMuted)
                Spacer().frame(height: 6)
                if isLookingUp {
                    Text("Đang tra cứu...")
                        .font(AppFont.beVietnamPro(14))
                        .foregroundStyle(AppColor.payMuted)
                } else if !holderName.isEmpty {
                    Text(holderName.uppercased())
                        .font(AppFont.beVietnamPro(16, .bold))
                        .foregroundStyle(AppColor.payInk)
                        .lineLimit(1)
                } else {
                    Text(lookupError ?? "")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.error)
                        .lineLimit(2)
                }
            }
        }
    }

    private var accTypeToggle: some View {
        HStack(spacing: 2) {
            accTypeButton(title: "Số TK", index: 0)
            accTypeButton(title: "Số thẻ", index: 1)
        }
        .padding(3)
        .background(Color(hex: 0xF1F3F5))
        .clipShape(Capsule())
    }

    private func accTypeButton(title: String, index: Int) -> some View {
        let selected = accType == index
        return Button {
            setAccType(index)
        } label: {
            Text(title)
                .font(AppFont.beVietnamPro(12, selected ? .bold : .medium))
                .foregroundStyle(selected ? Color(hex: 0x00542F) : AppColor.payMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(selected ? Color.white : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// Số tài khoản/thẻ dùng bàn phím SỐ HỆ THỐNG (không phải NumericKeypad tự vẽ) —
    /// tra cứu tên chủ TK chạy khi rời focus (`onChange(isAccountFocused)`) hoặc bấm Done.
    private var accountRow: some View {
        HStack(spacing: 8) {
            // Ô hiển thị + con trỏ nháy tự vẽ, KHÔNG phải `TextField`: ô này dùng bàn phím số
            // tự vẽ (có phím "Tiếp") nên không được để bàn phím hệ thống bật lên.
            HStack(spacing: 1) {
                if accountNumber.isEmpty {
                    Text(accType == 1 ? "Nhập số thẻ" : "Nhập số tài khoản")
                        .font(AppFont.beVietnamPro(17, .bold))
                        .foregroundStyle(AppColor.payMuted)
                } else {
                    Text(accountNumber)
                        .font(AppFont.beVietnamPro(17, .bold))
                        .foregroundStyle(AppColor.payInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if isAccountFocused {
                    BlinkingCaret(color: AppColor.payInk, height: 19)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { isAccountFocused = true }
            .onChangeCompat(of: accountNumber) { _, newValue in
                let filtered = String(newValue.filter(\.isNumber).prefix(19))
                if filtered != newValue {
                    // Gán lại sẽ kích hoạt `onChange` lần nữa với giá trị đã lọc — lượt đó mới
                    // hẹn tra cứu, nên ở đây không cần gọi.
                    accountNumber = filtered
                } else {
                    // Gọi CẢ KHI ô vừa bị xoá trắng: trước đây bỏ qua trường hợp rỗng nên xoá
                    // hết số mà tên chủ tài khoản cũ vẫn còn nằm đó.
                    clearHolderName()
                }
            }

            if !accountNumber.isEmpty {
                Button {
                    accountNumber = ""; holderName = ""; lookupError = nil; lastLookedUp = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: 0xBFC4CC))
                }
                .buttonStyle(PressableButtonStyle())
            } else {
                // Nút "Dán" như ô nhập số ví: `keyboardType(.numberPad)` KHÔNG có menu
                // Paste khi long-press (bàn phím số không kèm thanh chỉnh sửa), nên không
                // có nút này thì người dùng chỉ còn cách gõ tay cả 19 chữ số.
                //
                // Chỉ hiện khi ô đang TRỐNG, dùng chung chỗ với nút xoá: hàng này còn nút
                // danh bạ nữa, nhồi ba nút cạnh nhau sẽ hết chỗ cho số tài khoản dài.
                Button {
                    guard let clip = UIPasteboard.general.string else { return }
                    // Lọc lấy chữ số ngay tại đây: số tài khoản copy từ app ngân hàng hay
                    // kèm khoảng trắng/dấu gạch ("1234 5678 9012"), dán thô vào thì
                    // `onChange` cắt 19 KÝ TỰ trước khi lọc nên mất mấy số cuối.
                    accountNumber = String(clip.filter(\.isNumber).prefix(19))
                    // `onChange` của ô đã tự dọn `holderName`/`lookupError`. Chỉ cần xoá
                    // `lastLookedUp` để lần tra trước không chặn lần này (dán lại đúng số
                    // vừa tra xong mà tra lỗi thì vẫn phải cho tra lại).
                    lastLookedUp = nil
                    runLookupIfNeeded()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 15))
                        Text("Dán")
                            .font(AppFont.beVietnamPro(12.5, .bold))
                    }
                    .foregroundStyle(AppColor.brand)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppColor.brand.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
            }

            Button {
                isAccountFocused = false
                onOpenContacts()
            } label: {
                Image(systemName: "person.crop.rectangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: 0x00542F))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Chọn từ danh bạ")
        }
    }

    // MARK: - Số tiền

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Số tiền chuyển")
                    .font(AppFont.beVietnamPro(13, .semibold))
                    .foregroundStyle(AppColor.payMuted)
                Spacer()
                if let amountWarning {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text(amountWarning)
                            .font(AppFont.beVietnamPro(12, .medium))
                    }
                    .foregroundStyle(AppColor.error)
                }
            }

            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppColor.line, lineWidth: 1)
                    .frame(height: 130)
                    .overlay {
                        ZStack {
                            if speech.isListening || isParsingSpeech {
                                VStack(spacing: 8) {
                                    MicWaveBars(height: 40)
                                    Text(isParsingSpeech ? "Đang xử lý..." : "Đang nghe... (chạm mic để dừng)")
                                        .font(AppFont.beVietnamPro(12, .medium))
                                        .foregroundStyle(AppColor.payMuted)
                                }
                            }
                            HStack(spacing: 4) {
                                Text(amountText.isEmpty ? "0" : amountText)
                                    .font(AppFont.beVietnamPro(amountFontSize, .bold))
                                    .foregroundStyle(amountText.isEmpty ? AppColor.line : AppColor.payInk)
                                    .lineLimit(1)
                                if amountEditable && isAmountFocused {
                                    BlinkingCaret(color: AppColor.payInk, height: amountFontSize * 0.85)
                                }
                            }
                            .opacity(speech.isListening || isParsingSpeech ? 0 : 1)
                            HStack {
                                Spacer()
                                Text("VND")
                                    .font(AppFont.beVietnamPro(16, .medium))
                                    .foregroundStyle(AppColor.payMuted)
                                    .tracking(0.6)
                            }
                        }
                        .padding(.horizontal, 36)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isContentFocused = false
                            isAccountFocused = false
                            isAmountFocused = true
                        }
                    }

                micButton
            }

            if let voiceHint {
                Text(voiceHint)
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if amountEditable {
                if !amountSuggestions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(amountSuggestions, id: \.self) { value in
                            quickChip(Int(value).vndGrouped) { amount = value }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach(Self.quickAmounts, id: \.label) { q in
                            quickChip(q.label) { amount = min(Self.maxAmount, amount + q.value) }
                        }
                    }
                }
            }
        }
    }

    private func quickChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.beVietnamPro(13, .bold))
                .foregroundStyle(AppColor.payInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .overlay { Capsule().strokeBorder(AppColor.line, lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// Mirror `saveToggle` bên `WalletTransferAmountView` để hai luồng chuyển tiền nhìn
    /// như một.
    private var saveToggle: some View {
        Toggle(isOn: $saveRecipient) {
            Text("Lưu vào danh bạ")
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payInk)
        }
        .tint(AppColor.brand)
    }

    // MARK: - Nội dung

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .bottom) {
                Text("Nội dung chuyển tiền")
                    .font(AppFont.beVietnamPro(13, .medium))
                    .foregroundStyle(AppColor.payMuted)
                Spacer()
                Text("\(content.count)/250")
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
            }

            if contentEditable {
                TextField("", text: $content, prompt: .appPlaceholder("Nhập nội dung chuyển tiền", size: 16), axis: .vertical)
                    .font(AppFont.beVietnamPro(16, .medium))
                    .foregroundStyle(AppColor.payInk)
                    .tint(AppColor.brand)
                    .lineLimit(1...4)
                    .focused($isContentFocused)
                    .onChangeCompat(of: isContentFocused) { _, focused in
                        // Sang ô nội dung thì cất CẢ HAI bàn phím số tự vẽ và tắt mic. Thiếu
                        // `isAccountFocused` thì bàn phím ô số TK (nhánh xét trước ở footer)
                        // vẫn nằm đó, đè lên bàn phím hệ thống của ô này. Mic tắt vì đang nghe
                        // mà gõ nội dung thì số tiền tự nhảy, người dùng không hiểu vì sao.
                        if focused {
                            isAmountFocused = false
                            isAccountFocused = false
                            stopListening()
                        }
                    }
                    .onChangeCompat(of: content) { _, newValue in
                        if newValue.count > 250 { content = String(newValue.prefix(250)) }
                    }
            } else {
                Text(content)
                    .font(AppFont.beVietnamPro(16, .medium))
                    .foregroundStyle(AppColor.payInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle()
                .fill(isContentFocused ? AppColor.payInk : AppColor.line)
                .frame(height: 1)
                .padding(.top, 4)
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                ForEach(Self.contentSuggestions, id: \.self) { suggestion in
                    Button {
                        content = suggestion
                    } label: {
                        Text(suggestion)
                            .font(AppFont.beVietnamPro(12.5, .medium))
                            .foregroundStyle(AppColor.payMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .overlay { Capsule().strokeBorder(AppColor.line, lineWidth: 1) }
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(!contentEditable)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Group {
            if isAccountFocused {
                // Bàn phím của ô SỐ TÀI KHOẢN. Phím "Tiếp" tra tên chủ tài khoản rồi chuyển
                // sang ô số tiền — trước đây phải chạm ra ngoài mới tra được.
                //
                // KHÔNG chèn số 0 dẫn đầu như ô tiền: số tài khoản có thể bắt đầu bằng 0.
                //
                // Bản `Plain` (không có phím "000"): số tài khoản là số đếm từng chữ, gõ tắt
                // hàng nghìn là sai. Ô SỐ TIỀN bên dưới vẫn dùng `NumericKeypad` có "000".
                PlainNumericKeypad(
                    onDigit: pushAccountDigit,
                    onBackspace: backspaceAccountDigit,
                    onNext: {
                        isAccountFocused = false
                        runLookupIfNeeded()
                        isAmountFocused = amountEditable
                    },
                    nextTitle: "Tiếp",
                    nextEnabled: selectedBin != nil && accountNumber.count >= 4
                )
            } else if amountEditable && isAmountFocused {
                // Nút trên bàn phím gửi giao dịch LUÔN, không chỉ ẩn bàn phím — giống màn
                // chuyển ví. Chỉ ẩn bàn phím thì người dùng phải bấm thêm "TIẾP TỤC" ngay
                // bên dưới, thành hai bước cho cùng một ý định.
                NumericKeypad(
                    onDigit: pushDigit,
                    onBackspace: backspaceDigit,
                    onNext: { startTransfer() },
                    nextTitle: "Tiếp",
                    nextEnabled: canContinue && !isSubmitting
                )
            } else {
                continueButton
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white)
            }
        }
    }

    private var continueButton: some View {
        Button {
            startTransfer()
        } label: {
            HStack(spacing: 10) {
                Text("TIẾP TỤC")
                    .font(AppFont.beVietnamPro(14, .bold))
                    .tracking(1.2)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(canContinue ? .white : AppColor.payMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(canContinue ? AppColor.brand : AppColor.bgSoft)
            .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!canContinue || isSubmitting)
    }

    /// Không dùng được thì vẫn HIỆN nhưng mờ — ẩn hẳn khiến người dùng tưởng app lúc
    /// có lúc không tính năng.
    private var micButton: some View {
        Button(action: toggleListening) {
            Image(systemName: "mic.fill")
                .font(.system(size: 18))
                .foregroundStyle(micTint)
                .frame(width: 36, height: 36)
                .background(
                    speech.isListening ? AppColor.brand.opacity(0.12) : Color.clear,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .padding(10)
        .accessibilityLabel(speech.isListening ? "Dừng nghe" : "Nhập số tiền bằng giọng nói")
    }

    private var micTint: Color {
        if !speech.isAvailable { return AppColor.payMuted.opacity(0.4) }
        return speech.isListening ? AppColor.brand : AppColor.payMuted
    }

    // MARK: - Giọng nói

    /// Mic CHỈ điền số tiền. Số điền xong vẫn sửa/xoá được vì ghi thẳng vào `amount`.
    private func handleSpeech(_ candidates: [String]) {
        if let value = SpeechAmountParser.pickAmount(from: candidates) {
            applyVoiceAmount(value)
            return
        }
        // Đã có số tiền rồi thì kết quả đến sau KHÔNG được phép báo lỗi: bắt được tiền là
        // xong việc của mic. Chốt thêm ở đây vì lượt nghe có thể đã bị dừng giữa đường
        // (người dùng chạm mic, hoặc nhánh AI phía dưới về muộn sau khi số đã điền).
        guard amount == 0 else { return }

        guard !candidates.isEmpty else {
            voiceHint = "Chưa nghe được gì, thử lại nhé"
            return
        }
        // Regex trượt nhưng câu nói trông có số -> nhờ AI backend bóc lại. Lượt nói
        // linh tinh thì không gọi, đỡ một vòng mạng vô ích.
        guard candidates.contains(where: SpeechAmountParser.containsAmountHint) else {
            voiceHint = "Hãy đọc số tiền, ví dụ \"hai trăm nghìn\""
            return
        }
        Task {
            isParsingSpeech = true
            defer { isParsingSpeech = false }
            let parsed = try? await SpeechService.parseTransfer(transcripts: candidates)
            // Vòng mạng có thể về SAU khi user đã tự gõ số hoặc lượt nghe khác đã điền —
            // lúc đó tuyệt đối không ghi đè, cũng không báo lỗi.
            guard amount == 0 else { return }
            guard let parsed, parsed.amount > 0 else {
                voiceHint = "Chưa nghe rõ số tiền, thử nói \"hai trăm nghìn\""
                return
            }
            applyVoiceAmount(parsed.amount)
        }
    }

    private func applyVoiceAmount(_ value: Int64) {
        voiceHint = nil
        amount = min(value, Self.maxAmount)
        // Bắt được số là dừng — nghe tiếp dễ ăn tiếng ồn rồi ghi đè số vừa đúng.
        speech.stop()
    }

    private func toggleListening() {
        guard speech.isAvailable else {
            voiceHint = speech.unavailableReason
            return
        }
        if speech.isListening {
            speech.stop()
        } else {
            voiceHint = nil
            isAmountFocused = true
            Task { await speech.start() }
        }
    }

    private func stopListening() {
        if speech.isListening { speech.stop() }
    }

    /// Tự bật mic khi ĐÃ có người nhận và chưa nhập số tiền. Khác màn ví ở chỗ luồng
    /// nhập tay còn phải chọn ngân hàng + gõ số tài khoản trước — bật mic lúc đó là
    /// chiếm micro trong khi người dùng chưa có gì để đọc.
    private func startVoiceIfReady() async {
        guard amountEditable, amount == 0, recipientReady, speech.isAvailable else { return }
        guard !speech.isListening else { return }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled, amount == 0 else { return }
        isAmountFocused = true
        await speech.start()
    }

    // MARK: - Nhập số tiền (bàn phím tự vẽ)

    private func pushDigit(_ s: String) {
        stopListening()
        guard amountEditable else { return }
        let current = amount == 0 ? "" : String(amount)
        let next = String((current + s).filter(\.isNumber).drop(while: { $0 == "0" }).prefix(9))
        amount = min(Int64(next) ?? 0, Self.maxAmount)
    }

    private func backspaceDigit() {
        stopListening()
        guard amountEditable else { return }
        let current = amount == 0 ? "" : String(amount)
        amount = Int64(String(current.dropLast())) ?? 0
    }

    private func setAccType(_ type: Int) {
        guard accType != type else { return }
        accType = type
        holderName = ""; lookupError = nil; lastLookedUp = nil
        if accountNumber.count >= 4, selectedBin != nil { runLookupIfNeeded() }
    }

    // MARK: - Tra cứu tên chủ tài khoản

    // MARK: - Nhập số tài khoản (bàn phím tự vẽ)

    /// Giới hạn 19 chữ số như bản `TextField` cũ. KHÔNG chặn số 0 dẫn đầu — khác ô số tiền,
    /// số tài khoản/số thẻ bắt đầu bằng 0 là bình thường.
    private func pushAccountDigit(_ digits: String) {
        guard !recipientLocked else { return }
        accountNumber = String((accountNumber + digits).prefix(19))
    }

    private func backspaceAccountDigit() {
        guard !recipientLocked, !accountNumber.isEmpty else { return }
        accountNumber.removeLast()
    }

    /// Vừa sửa số tài khoản -> dọn tên cũ. KHÔNG tự tra ở đây: chỉ tra khi bấm "Tiếp" trong
    /// bàn phím hoặc khi rời ô.
    private func clearHolderName() {
        // Người nhận đã khoá (vào từ QR/OneTouch/link) thì tên đã có sẵn và đúng — không được
        // xoá. Chặn TRƯỚC khi dọn, không thì tên điền sẵn bị mất mà không có gì tra lại.
        guard !recipientLocked else { return }
        // Đúng số đang tra / vừa tra xong: nút "Dán" gán text RỒI gọi tra ngay, mà `onChange`
        // chỉ chạy ở vòng cập nhật sau — không chặn ở đây thì lượt đó xoá mốc vừa đặt, và lần
        // rời ô sau đó lại tra lại đúng số đó một lần nữa.
        if let bin = selectedBin, let lastLookedUp, lastLookedUp == (bin, accountNumber, accType) {
            return
        }
        // Số đổi thì tên cũ không còn thuộc số này — xoá cả tên lẫn mốc chống tra trùng, nếu
        // giữ mốc thì xoá lùi về đúng số vừa tra sẽ bị bỏ qua và ô tên trống vĩnh viễn.
        holderName = ""; lookupError = nil; lastLookedUp = nil
    }

    private func runLookupIfNeeded() {
        guard !recipientLocked, let bin = selectedBin, accountNumber.count >= 4 else { return }
        guard let bankNo = Int(bin) else {
            lookupError = "Mã ngân hàng không hợp lệ"
            return
        }
        let key = (bin, accountNumber, accType)
        if let lastLookedUp, lastLookedUp == key { return }
        lastLookedUp = key
        holderName = ""; lookupError = nil
        Task {
            isLookingUp = true
            defer { isLookingUp = false }
            do {
                holderName = try await TransferService.verifyBeneficiary(
                    VerifyBeneficiaryRequest(accNo: accountNumber, bankNo: bankNo, accType: accType)
                )
                // Tra ra tên là bước cuối của phần người nhận -> việc tiếp theo chắc chắn
                // là nhập số tiền, nên bật mic luôn cho đọc ngay.
                isAccountFocused = false
                await startVoiceIfReady()
            } catch let error as APIError {
                lookupError = error.message
            } catch {
                lookupError = "Không tra cứu được tài khoản"
            }
        }
    }

    // MARK: - Submit

    private func startTransfer() {
        guard amount <= TransferLimits.faceFixed else {
            transferError = "Số tiền chuyển tối đa 1 lần là 10.000.000đ"
            return
        }
        Task { await submitTransfer() }
    }

    private func submitTransfer() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let request = TransferToBankRequest(
            idempotencyKey: idempotencyKey,
            accNo: accountNumber, accType: accType, bankNo: selectedBin ?? "",
            accName: holderName, transAmount: Int(amount), memo: effectiveContent
        )

        do {
            // Mốc đo thời gian xử lý THẬT để biên lai không phải bịa "2,0 giây".
            submitStartedAt = Date()
            let result = try await TransferService.transferToBank(request)
            await handleResult(result)
        } catch let error as APIError {
            transferError = error.message
        } catch {
            transferError = "Đã có lỗi xảy ra, vui lòng thử lại"
        }
    }

    /// Xác thực giao dịch pending bằng Face ID — ký số tiền + SỐ TÀI KHOẢN người nhận.
    /// `accountNumber` chính là `acc_no` đã gửi khi tạo giao dịch, khớp `signaturePayload()` BE.
    private func submitBiometric() async {
        guard let transactionId = pendingTransactionId else { return }
        do {
            submitStartedAt = Date()
            let result = try await BiometricService.verifyTransfer(
                transactionId: transactionId,
                amount: amount,
                recipient: accountNumber
            )
            await handleResult(result)
        } catch BiometricKeyError.userCancelled {
            // Huỷ hộp thoại Face ID: giữ sheet, không báo lỗi đỏ — bấm "Thử lại" hoặc
            // "Dùng mật khẩu" là được.
            biometricError = nil
        } catch BiometricKeyError.keyInvalidated {
            // Đổi/thêm khuôn mặt trong Cài đặt iOS -> khoá tự vô hiệu (.biometryCurrentSet).
            BiometricKeyStore.deleteKey()
            useBiometric = false
            pinError = "Face ID đã thay đổi, vui lòng nhập mật khẩu và bật lại trong Cá nhân"
        } catch let error as BiometricKeyError {
            biometricError = error.localizedDescription
        } catch let error as APIError {
            // 403 = BE nói "đừng quét lại nữa" (còn cooling-off, chưa đăng ký khoá, bị khoá).
            // 400 và lỗi khác: quét lại có thể được. Xem quy ước ở `verifyTransfer` bên BE.
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
        do {
            // Đo lại từ lúc gửi PIN — thời gian người dùng gõ PIN không phải thời gian
            // xử lý giao dịch.
            submitStartedAt = Date()
            let result = try await TransferService.verifyTransfer(
                VerifyTransferRequest(password: pin, transactionId: transactionId)
            )
            await handleResult(result)
        } catch let error as APIError {
            pinError = error.message
        } catch {
            pinError = "Đã có lỗi xảy ra, vui lòng thử lại"
        }
    }

    private func handleResult(_ result: TransferResult) async {
        if result.isPending, let transactionId = result.transactionId {
            pendingTransactionId = transactionId
            return
        }
        pendingTransactionId = nil
        let elapsed = submitStartedAt.map { Date().timeIntervalSince($0) }
        // `alreadySaved` phải kiểm lại ở đây: khi người nhận đã có trong danh bạ thì toggle
        // bị ẩn nhưng `saveRecipient` vẫn còn true -> tạo trùng bản ghi. Mirror đúng cách
        // `WalletTransferAmountView.handleResult` đang làm.
        if saveRecipient, !alreadySaved, let bankNo = selectedBin, !accountNumber.isEmpty {
            _ = try? await BeneficiaryStore.shared.create(
                CreateBeneficiaryRequest(
                    type: .bankAccount, bankNo: bankNo, accNo: accountNumber, accName: holderName
                )
            )
        }
        if let payLinkToken {
            await PayLinkService.consume(reqToken: payLinkToken, txId: result.transId)
        }
        await WalletStore.shared.refresh(force: true)
        onSuccess(
            TransferSuccessInfo(
                kind: .bank, amount: amount, recipientName: holderName,
                bankName: bankNameForSubmit, accountNumber: accountNumber,
                noteLabel: "Nội dung", note: effectiveContent,
                transactionCode: result.bkTransId ?? result.transId,
                elapsedSeconds: elapsed,
                // Bảo Kim code 99: tiền đã trừ nhưng ngân hàng chưa chốt.
                isProcessing: result.status == "PENDING",
                feeAmount: result.feeAmount
            )
        )
    }

}

// `BlinkingCaret` chuyển sang UI/Components để màn chuyển ví dùng chung — ô số ví bên đó cũng
// dùng bàn phím số tự vẽ nên cũng cần con trỏ.

/// Logo ngân hàng thật (ảnh mạng) kèm fallback khối màu brand + tên viết tắt.
/// Không `private` — dùng lại ở lưới chọn ngân hàng của màn bổ sung thông tin eKYC.
struct BankLogoView: View {
    let bank: Bank?
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let bank {
                if let urlString = bank.logoUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit()
                        } else {
                            fallback(bank)
                        }
                    }
                } else {
                    fallback(bank)
                }
            } else {
                Image(systemName: "building.columns")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(AppColor.payMuted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func fallback(_ bank: Bank) -> some View {
        Circle()
            .fill(bank.brandColor.flatMap(Color.init(hexString:)) ?? AppColor.brand)
            .overlay {
                Text(bank.shortName.prefix(4))
                    .font(AppFont.beVietnamPro(size * 0.28, .bold))
                    .foregroundStyle(.white)
            }
    }
}

private extension Color {
    /// Mirror `Color.luminance() > 0.6f` bên Kotlin — quyết định chữ trắng/đen trên
    /// nền brand-color của từng ngân hàng.
    var isLight: Bool {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return false }
        let luminance = 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2]
        return luminance > 0.6
    }
}

/// Sheet "Chọn ngân hàng" — danh sách đầy đủ, tìm kiếm không dấu (mirror
/// ModalBottomSheet trong TransferScreen.kt). Không `private` — tái dùng ở WithdrawView.
struct BankPickerSheet: View {
    let banks: [Bank]
    @Binding var selectedBin: String?
    let onDismiss: () -> Void

    @State private var query = ""

    private var filtered: [Bank] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return banks }
        let needle = trimmed.noAccentLowercased
        return banks.filter {
            $0.shortName.noAccentLowercased.contains(needle) || $0.name.noAccentLowercased.contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColor.line)
                .frame(width: 40, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Text("Chọn ngân hàng")
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppColor.payMuted)
                TextField("", text: $query, prompt: .appPlaceholder("Tìm ngân hàng..."))
                    .font(AppFont.beVietnamPro(14))
                    .foregroundStyle(AppColor.payInk)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(hex: 0xF1F3F5))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { bank in
                        Button {
                            selectedBin = bank.bin
                            onDismiss()
                        } label: {
                            HStack(spacing: 12) {
                                BankLogoView(bank: bank, size: 32)
                                Text(bank.shortName)
                                    .font(AppFont.beVietnamPro(14, .semibold))
                                    .foregroundStyle(AppColor.payInk)
                                Spacer()
                                Text(bank.name)
                                    .font(AppFont.beVietnamPro(12))
                                    .foregroundStyle(AppColor.payMuted)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 12)
                            // Không có `contentShape` thì `Spacer()` giữa hai nhãn không
                            // nhận chạm — bấm vào giữa hàng là không chọn được ngân hàng.
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        Rectangle().fill(AppColor.line).frame(height: 1)
                    }
                }
                .padding(.horizontal, 20)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
        }
        // Chừa một dải trên đầu để còn chỗ chạm ra ngoài mà đóng — `.large` phủ gần kín
        // nên hầu như không còn "ngoài" nào để chạm.
        .presentationDetents([.fraction(0.92)])
        // iOS 26 để nền sheet là kính mờ, nhìn xuyên thấy màn phía dưới. Phần sheet che
        // tới đâu thì phải đục tới đó.
        //
        // `.presentationBackground` là iOS 16.4, cao hơn deployment target. Ở đây chỉ cần
        // nền TRẮNG ĐỤC nên `.background` thường là đủ — khác các sheet dialog cần nền
        // TRONG SUỐT, chỗ đó phải dùng `transparentSheetBackground()`.
        .background(Color.white)
    }
}

private extension String {
    /// Bỏ dấu tiếng Việt + hạ chữ thường để tìm kiếm không phân biệt dấu/hoa-thường.
    var noAccentLowercased: String {
        folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .lowercased()
    }
}

#Preview {
    BankTransferView(onBack: {}, onHome: {}, onSuccess: { _ in })
}
