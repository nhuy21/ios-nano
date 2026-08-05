//
//  WalletTransferAmountView.swift
//  nano ewallet
//
//  Màn GỘP của luồng chuyển ví→ví: số ví người nhận + số tiền + lời nhắn trên CÙNG
//  một màn. Mirror `WalletTransferScreen` (bản Kotlin mới đã bỏ màn nhập số tiền
//  riêng — `WalletTransferAmountScreen.kt` còn trong repo nhưng không còn được đăng
//  ký vào navigation).
//
//  Hai chế độ, quyết định bởi `draft`:
//   - `draft == nil`  -> NHẬP TAY: hiện ô số ví, tra cứu tên chủ ví khi rời ô.
//   - `draft != nil`  -> người nhận KHOÁ (từ danh bạ/QR/OneTouch/giọng nói/pay-link),
//     vào thẳng phần nhập tiền.
//
//  Lời nhắn giới hạn 140 ký tự (luồng ngân hàng dùng 250). PIN sheet dùng chung.
//

import SwiftUI
import Combine
import UIKit

@MainActor
struct WalletTransferAmountView: View {
    /// `nil` = chế độ nhập tay. Có giá trị = người nhận đã xác thực, khoá lại.
    let initialDraft: WalletTransferDraft?
    let onBack: () -> Void
    let onSuccess: (TransferSuccessInfo) -> Void
    /// Mở danh bạ ví — chỉ dùng ở chế độ nhập tay.
    var onOpenContacts: () -> Void = {}
    /// Về Home — nút nhà ở header, luôn hiện như bản Kotlin. Mặc định lùi 1 bước để nơi
    /// gọi không bắt buộc truyền.
    var onHome: () -> Void = {}

    /// 140 ký tự cho luồng ví (bank transfer dùng 250).
    private static let maxMessageLength = 140
    private static let suggestions = ["Mình chuyển nhé", "Cảm ơn nha", "Chúc mừng"]

    @StateObject private var wallet = WalletStore.shared
    @StateObject private var authStore = AuthStore.shared
    @StateObject private var beneficiaryStore = BeneficiaryStore.shared
    @StateObject private var speech = SpeechRecognizerService()

    /// Báo ngắn dưới ô số tiền khi nghe không ra số (hoặc không dùng được mic).
    @State private var voiceHint: String?
    /// Đang nhờ backend bóc lại số tiền sau khi regex trượt.
    @State private var isParsingSpeech = false

    /// OneTouch bóc được số tiền từ nội dung dán -> điền sẵn, vẫn sửa được.
    @State private var amountText: String
    @State private var message = ""
    @State private var saveRecipient = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    @State private var pendingTransactionId: String?
    /// Mốc bắt đầu gọi API chuyển tiền — để biên lai hiện thời gian xử lý thật.
    @State private var submitStartedAt: Date?
    @State private var pinError: String?

    /// Xác thực giao dịch pending bằng Face ID thay vì nhập mật khẩu. Bật khi thiết bị đã đăng
    /// ký khoá sinh trắc; người dùng bấm "Dùng mật khẩu" thì tắt để rơi về `PinEntrySheet`.
    /// Chỉ đọc `hasKey()` (không gọi API, không bật Face ID) nên gán được ngay lúc dựng view.
    @State private var useBiometric = BiometricKeyStore.hasKey()
    @State private var biometricError: String?

    /// Bàn phím số tự vẽ đang hiện hay không. Mở sẵn khi vào màn, chạm ra ngoài thì ẩn,
    /// chạm vào ô số tiền thì mở lại. Không phải @FocusState vì bàn phím này là SwiftUI
    /// thuần — `endEditing` ở tầng UIWindow không đụng tới được.
    @State private var isAmountFocused: Bool
    @FocusState private var isMessageFocused: Bool

    // Chế độ nhập tay — tra cứu số ví người nhận ngay trên màn này.
    @State private var username: String
    @State private var verifiedName: String?
    @State private var isVerifying = false
    @State private var lookupError: String?
    @State private var lastVerified: String?
    @FocusState private var isUsernameFocused: Bool

    /// Popup hotline — Kotlin để nút Hỗ trợ ở header màn này.
    @State private var showSupport = false

    private let idempotencyKey = TransferService.newIdempotencyKey()

    init(
        draft: WalletTransferDraft? = nil,
        onBack: @escaping () -> Void,
        onSuccess: @escaping (TransferSuccessInfo) -> Void,
        onOpenContacts: @escaping () -> Void = {},
        onHome: @escaping () -> Void = {}
    ) {
        self.initialDraft = draft
        self.onBack = onBack
        self.onSuccess = onSuccess
        self.onOpenContacts = onOpenContacts
        self.onHome = onHome
        _amountText = State(initialValue: draft?.prefillAmount.map(String.init) ?? "")
        _username = State(initialValue: draft?.username ?? "")
        _verifiedName = State(initialValue: draft?.holderName)
        _lastVerified = State(initialValue: draft?.username)
        // Nhập tay: chưa biết người nhận nên KHÔNG mở bàn phím số (nó che ô số ví) —
        // chỉ mở sau khi tra cứu ra tên chủ ví. Vào từ danh bạ/QR thì mở ngay.
        _isAmountFocused = State(initialValue: draft != nil)
    }

    /// Người nhận đã xác thực xong — dùng cho cả 2 chế độ. `nil` = chưa đủ để chuyển tiền.
    private var recipient: WalletTransferDraft? {
        guard let verifiedName, !username.isEmpty else { return nil }
        return WalletTransferDraft(
            username: username,
            holderName: verifiedName,
            payLinkToken: initialDraft?.payLinkToken,
            prefillAmount: initialDraft?.prefillAmount
        )
    }

    /// Người nhận truyền sẵn từ ngoài -> khoá, không cho sửa số ví.
    private var recipientLocked: Bool { initialDraft != nil }

    private var amount: Int64 { Int64(amountText) ?? 0 }
    private var overLimit: Bool {
        if let balance = wallet.balance { return amount > balance }
        return false
    }
    private var overMaxPerTransfer: Bool { amount > TransferLimits.faceFixed }
    /// Chế độ nhập tay phải tra cứu ra tên chủ ví trước — `recipient` mới có giá trị.
    private var canContinue: Bool { amount > 0 && !overMaxPerTransfer && recipient != nil }

    /// Nội dung mặc định điền sẵn vào ô lời nhắn để user SỬA được, không phải chỉ thay
    /// thế ngầm lúc gửi. Dùng tên người GỬI vì đây là dòng người nhận sẽ thấy.
    private var defaultMessage: String {
        let sender = authStore.userFullName?.trimmingCharacters(in: .whitespaces)
        guard let sender, !sender.isEmpty else { return "Chuyển tiền qua ví Nano" }
        return "\(sender) chuyển tiền qua ví Nano"
    }

    private var effectiveMessage: String {
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? defaultMessage : trimmed
    }

    /// Người nhận đã nằm trong danh bạ -> ẩn luôn toggle "Lưu vào danh bạ".
    private var alreadySaved: Bool {
        beneficiaryStore.beneficiaries.contains {
            $0.type == .wallet && $0.benUsername == username
        }
    }

    /// Gợi ý theo số ĐANG GÕ, đỡ phải gõ hết số 0: gõ "1" -> 1.000 / 10.000 / 100.000,
    /// gõ "15" -> 15.000 / 150.000 / 1.500.000. Gõ quá 3 chữ số coi như đang nhập số
    /// tiền đầy đủ nên không gợi ý nữa.
    private var amountSuggestions: [Int64] {
        // Chưa gõ gì -> mệnh giá mặc định để chạm 1 phát là xong.
        guard amount > 0 else { return [10_000, 100_000, 1_000_000] }
        // Gõ quá 3 chữ số coi như đang nhập số tiền đầy đủ, không gợi ý nữa.
        guard amount <= 999 else { return [] }
        return [amount * 1_000, amount * 10_000, amount * 100_000]
            .filter { $0 <= TransferLimits.faceFixed }
    }

    // MARK: - Nhập số

    private func appendDigits(_ digits: String) {
        // Gõ tay -> tắt mic. Để mic chạy tiếp thì nó sẽ ghi đè số vừa gõ.
        stopListening()
        // Chặn số 0 dẫn đầu và giới hạn 9 chữ số như bên Android.
        let combined = amountText.isEmpty && digits.allSatisfy { $0 == "0" }
            ? ""
            : amountText + digits
        amountText = String(combined.prefix(9))
    }

    private func backspaceDigit() {
        stopListening()
        guard !amountText.isEmpty else { return }
        amountText.removeLast()
    }


    // MARK: - Giọng nói

    /// Mic CHỈ điền số tiền, không thu lời nhắn. Số điền xong vẫn sửa được bằng bàn
    /// phím vì nó ghi thẳng vào `amountText` — không khoá ô.
    private func handleSpeech(_ candidates: [String]) {
        // Bóc bằng regex trước — tức thì, không tốn mạng.
        if let amount = SpeechAmountParser.pickAmount(from: candidates) {
            applyVoiceAmount(amount)
            return
        }

        // Đã có số tiền rồi thì kết quả đến sau KHÔNG được phép báo lỗi: bắt được tiền là
        // xong việc của mic. Chốt thêm ở đây vì lượt nghe có thể đã bị dừng giữa đường
        // (người dùng chạm mic, hoặc nhánh AI phía dưới về muộn sau khi số đã điền).
        guard amountText.isEmpty else { return }

        guard !candidates.isEmpty else {
            voiceHint = "Chưa nghe được gì, thử lại nhé"
            return
        }

        // Regex trượt nhưng câu nói TRÔNG NHƯ có đọc số -> nhờ AI backend bóc lại.
        // Lượt nói linh tinh thì không gọi, đỡ một vòng mạng vô ích.
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
            guard amountText.isEmpty else { return }
            guard let parsed, parsed.amount > 0 else {
                voiceHint = "Chưa nghe rõ số tiền, thử nói \"hai trăm nghìn\""
                return
            }
            applyVoiceAmount(parsed.amount)
        }
    }

    private func applyVoiceAmount(_ amount: Int64) {
        voiceHint = nil
        amountText = String(min(amount, TransferLimits.faceFixed))
        // Bắt được số là dừng — nghe tiếp dễ ăn phải tiếng ồn rồi ghi đè số vừa đúng.
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
            Task { await speech.start() }
        }
    }

    private func stopListening() {
        if speech.isListening { speech.stop() }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sourceAccountCard
                    recipientCard
                    amountSection
                    messageSection
                    if !alreadySaved {
                        saveToggle
                    }
                }
                .padding(16)
            }

            // Bàn phím số tự vẽ thay cho nút "Tiếp tục" rời — nút hành động nằm luôn
            // trong bàn phím. Ẩn khi đang gõ số ví/lời nhắn để nhường bàn phím hệ thống.
            if isAmountFocused && !isMessageFocused && !isUsernameFocused {
                NumericKeypad(
                    onDigit: appendDigits,
                    onBackspace: backspaceDigit,
                    onNext: { Task { await submitTransfer() } },
                    nextTitle: "Tiếp",
                    nextEnabled: canContinue && !isSubmitting
                )
            } else {
                // Ẩn bàn phím số (chạm ra ngoài) hoặc đang gõ lời nhắn bằng bàn phím
                // hệ thống -> nhường chỗ cho nút bấm rời.
                continueBar
            }
        }
        // Nền xám nhạt `WtPageBg` — khác màn chuyển khoản ngân hàng (nền trắng).
        .background(Color(hex: 0xF1F3F5))
        // Bàn phím HỆ THỐNG đã tự ẩn nhờ cử chỉ gắn ở tầng UIWindow (xem
        // DismissKeyboardOnTap). Ở đây chỉ cần lo bàn phím số tự vẽ.
        .contentShape(Rectangle())
        .onTapGesture { isAmountFocused = false }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            // Cần danh bạ để biết người nhận đã được lưu chưa (quyết định ẩn toggle).
            _ = await beneficiaryStore.get()
        }
        .onAppear {
            // Điền sẵn nội dung mặc định (user sửa/xoá được), chỉ làm 1 lần lúc vào màn.
            if message.isEmpty { message = defaultMessage }
            speech.onResult = { candidates in handleSpeech(candidates) }
        }
        .task {
            // Tự bật mic khi vào màn, CHỈ khi chưa có số tiền — vào từ OneTouch/trợ lý
            // giọng nói/link nhận tiền thì số đã điền sẵn, không còn gì để đọc.
            //
            // Chế độ nhập tay thì chờ tra cứu ra tên chủ ví xong mới bật (xem
            // `runVerifyIfNeeded`) — bật ngay lúc user đang gõ số ví là vô nghĩa.
            guard recipientLocked, amountText.isEmpty, speech.isAvailable else { return }
            // Đệm nhỏ để hiệu ứng chuyển màn xong rồi mới chiếm micro.
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, amountText.isEmpty else { return }
            await speech.start()
        }
        .onDisappear { speech.stop() }
        // Có số tiền rồi thì mọi lời nhắc của mic đều VÔ NGHĨA — xoá ngay.
        //
        // Đặt ở `onChange` của `amountText` chứ không rải vào từng chỗ điền số: bàn phím số,
        // mệnh giá gợi ý, mic, prefill từ QR/OneTouch đều đi qua đây, nên không sót đường
        // nào. Không xoá thì hint "Chưa nghe được gì, thử lại nhé" vẫn treo dưới ô tiền
        // trong khi người dùng đã tự gõ xong số — như đang báo lỗi việc họ không làm sai.
        .onChangeNewCompat(of: amountText) { newValue in
            if !newValue.isEmpty { voiceHint = nil }
        }
        .sheet(isPresented: pendingTransactionIdBinding) {
            if useBiometric {
                BiometricAuthSheet(
                    amountText: Int(amount).vndFormatted,
                    recipientName: verifiedName ?? username,
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
                    recipientName: verifiedName ?? username,
                    onSubmit: submitPin,
                    onCancel: { pendingTransactionId = nil },
                    externalError: $pinError
                )
            }
        }
        .overlay { if isSubmitting { ProcessingOverlay() } }
        .overlay {
            if let errorMessage {
                // Bản Kotlin của luồng ví không có icon cảnh báo.
                TransferErrorOverlay(message: errorMessage, showIcon: false) {
                    self.errorMessage = nil
                }
            }
        }
        .overlay {
            if showSupport {
                SupportDialog(onDismiss: { showSupport = false })
            }
        }
    }

    private var pendingTransactionIdBinding: Binding<Bool> {
        Binding(get: { pendingTransactionId != nil }, set: { if !$0 { pendingTransactionId = nil } })
    }

    // MARK: - Header

    /// Header nền TRẮNG, chữ mực đen — mirror WalletTransferScreen.kt L482-538 (không phải
    /// dải gradient xanh: gradient chỉ dùng ở màn thành công). Nút back tròn xám bên trái,
    /// Hỗ trợ + Trang chủ bên phải, luôn hiện ở cả 2 chế độ.
    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppColor.payInk)
                    .frame(width: 38, height: 38)
                    .background(Color(hex: 0xF1F3F5))
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quay lại")

            Spacer()

            Text("Chuyển tiền ví")
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(AppColor.payInk)

            Spacer()

            HStack(spacing: 0) {
                // Khung 38pt quanh glyph 22pt: chạm vào đúng icon nhỏ như vậy rất khó,
                // Apple khuyến nghị vùng chạm tối thiểu ~44pt.
                Button { showSupport = true } label: {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 22))
                        .foregroundStyle(AppColor.payInk)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hỗ trợ")

                Rectangle()
                    .fill(AppColor.payInk.opacity(0.15))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 10)

                Button(action: onHome) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColor.payInk)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Trang chủ")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    // MARK: - Ví nguồn (số ví người gửi + số dư)

    private var sourceAccountCard: some View {
        SourceAccountCard(username: wallet.bkUsername, balance: wallet.balance)
    }

    // MARK: - Người nhận

    /// Khoá (vào từ danh bạ/QR/OneTouch) -> card chỉ đọc. Nhập tay -> ô nhập số ví +
    /// ô tên chủ ví chỉ đọc hiện trạng thái tra cứu.
    @ViewBuilder
    private var recipientCard: some View {
        if recipientLocked {
            lockedRecipientCard
        } else {
            usernameSection
        }
    }

    private var lockedRecipientCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppColor.brandSoft)
                .frame(width: 44, height: 44)
                .overlay {
                    Text((verifiedName ?? username).nameInitials)
                        .font(AppFont.beVietnamPro(16, .bold))
                        .foregroundStyle(AppColor.brand)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(verifiedName ?? username)
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.payInk)
                Text("Ví nano · \(username)")
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Ô nhập số ví + nút "Dán" nằm TRONG ô. Tên chủ ví chỉ hiện SAU khi tra cứu
    /// (đang tra / ra tên / lỗi), không chiếm chỗ sẵn.
    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Số ví người nhận")
                    .font(AppFont.beVietnamPro(14, .bold))
                    .foregroundStyle(AppColor.payInk)
                Spacer()
                Button(action: onOpenContacts) {
                    HStack(spacing: 2) {
                        Text("Danh bạ")
                            .font(AppFont.beVietnamPro(13, .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(AppColor.brand)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                TextField("", text: $username, prompt: Text("Nhập số ví")
                    .font(AppFont.beVietnamPro(15))
                    .foregroundColor(AppColor.payMuted))
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.payInk)
                    .keyboardType(.numberPad)
                    .tint(AppColor.brand)
                    .focused($isUsernameFocused)
                    .onChangeCompat(of: isUsernameFocused) { wasFocused, focusedNow in
                        if wasFocused && !focusedNow { runVerifyIfNeeded() }
                    }

                Button {
                    if let clip = UIPasteboard.general.string { username = clip }
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
                .buttonStyle(.plain)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(height: 52)
            .background(AppColor.bgSoft)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Chỉ hiện khi CÓ GÌ để hiện (đang tra / ra tên / lỗi) — mirror cách màn
            // chuyển khoản ngân hàng làm. Ô rỗng kèm chữ "Nhập số ví để tra cứu" chiếm
            // chỗ vô ích và trông như một ô nhập thứ hai.
            if isVerifying || verifiedName != nil || lookupError != nil {
                Rectangle()
                    .fill(AppColor.line)
                    .frame(height: 1)
                    .padding(.vertical, 8)

                Text("Tên chủ ví")
                    .font(AppFont.beVietnamPro(12.5, .medium))
                    .foregroundStyle(AppColor.payMuted)

                if isVerifying {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColor.brand)
                        Text("Đang tra cứu...")
                            .font(AppFont.beVietnamPro(14))
                            .foregroundStyle(AppColor.payMuted)
                    }
                } else if let verifiedName {
                    Text(verifiedName.uppercased())
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
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Tra cứu tên chủ ví. Xong thì mở bàn phím số + bật mic để đi tiếp ngay.
    private func runVerifyIfNeeded() {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != lastVerified else { return }
        lastVerified = trimmed
        lookupError = nil
        verifiedName = nil
        Task {
            isVerifying = true
            defer { isVerifying = false }
            do {
                verifiedName = try await TransferService.verifyBeneficiary(
                    VerifyBeneficiaryRequest(benUsername: trimmed)
                )
                // Có người nhận rồi mới mở bàn phím số (trước đó nó che ô số ví).
                isAmountFocused = true
                if amountText.isEmpty, speech.isAvailable { await speech.start() }
            } catch let error as APIError {
                lookupError = error.message
            } catch {
                lookupError = "Không xác thực được số ví người nhận"
            }
        }
    }

    // MARK: - Số tiền

    /// Số tiền hiển thị lớn, LUÔN có dấu chấm phân nghìn. Việc nhập/xoá do bàn phím tự
    /// vẽ ở dưới đảm nhiệm nên không dùng ô nhập của hệ thống nữa.
    private var amountSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Text(amountText.isEmpty ? "0đ" : "\(Int(amount).vndGrouped)đ")
                    .font(AppFont.beVietnamPro(34, .bold))
                    .foregroundStyle(amountText.isEmpty ? AppColor.payMuted : AppColor.payInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .opacity(speech.isListening || isParsingSpeech ? 0 : 1)

                if speech.isListening || isParsingSpeech {
                    VStack(spacing: 8) {
                        MicWaveBars(height: 36)
                        Text(isParsingSpeech ? "Đang xử lý..." : "Đang nghe... (chạm mic để dừng)")
                            .font(AppFont.beVietnamPro(12, .medium))
                            .foregroundStyle(AppColor.payMuted)
                    }
                }
            }
            .frame(height: 62)
            .contentShape(Rectangle())
            .onTapGesture { isAmountFocused = true }
            // Ngang hàng với con số, mép phải. Gắn vào cả thẻ thì mic đè lên chip gợi ý
            // mệnh giá ở dưới nên phải bó trong vùng số tiền.
            .overlay(alignment: .trailing) { micButton }

            Rectangle()
                .fill(canContinue ? AppColor.brand : AppColor.line)
                .frame(height: 2)

            if let voiceHint {
                Text(voiceHint)
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if overMaxPerTransfer {
                FieldError(message: "Số tiền chuyển tối đa 1 lần là 10.000.000đ", alignment: .center)
            } else if overLimit {
                FieldError(message: "Số tiền vượt quá số dư khả dụng", alignment: .center)
            }

            if !amountSuggestions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(amountSuggestions, id: \.self) { value in
                        Button {
                            amountText = String(value)
                        } label: {
                            Text("\(Int(value).vndGrouped)đ")
                                .font(AppFont.beVietnamPro(13, .bold))
                                .foregroundStyle(AppColor.payInk)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .overlay {
                                    Capsule().strokeBorder(AppColor.line, lineWidth: 1.5)
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Không dùng được (mất mạng / máy không hỗ trợ) thì vẫn HIỆN nhưng mờ đi — ẩn hẳn
    /// sẽ khiến người dùng tưởng app lúc có lúc không tính năng.
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
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isListening ? "Dừng nghe" : "Nhập số tiền bằng giọng nói")
    }

    private var micTint: Color {
        if !speech.isAvailable { return AppColor.payMuted.opacity(0.4) }
        return speech.isListening ? AppColor.brand : AppColor.payMuted
    }


    // MARK: - Lời nhắn

    /// Không bọc trong ô có viền: chỉ nhãn + bộ đếm ký tự ở trên, chữ trải rộng và
    /// XUỐNG DÒNG được, gạch chân mảnh ở dưới.
    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Nội dung chuyển tiền")
                    .font(AppFont.beVietnamPro(14))
                    .foregroundStyle(AppColor.payMuted)
                Spacer()
                Text("\(message.count)/\(Self.maxMessageLength)")
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.payMuted)
            }

            TextField("", text: $message, prompt: .appPlaceholder("Nhập nội dung chuyển tiền", size: 17), axis: .vertical)
                .font(AppFont.beVietnamPro(17, .semibold))
                .foregroundStyle(AppColor.payInk)
                .tint(AppColor.brand)
                .lineLimit(1...4)
                .focused($isMessageFocused)
                .onChangeCompat(of: message) { _, newValue in
                    if newValue.count > Self.maxMessageLength {
                        message = String(newValue.prefix(Self.maxMessageLength))
                    }
                }

            Rectangle()
                .fill(AppColor.line)
                .frame(height: 1)

            HStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button {
                        message = suggestion
                    } label: {
                        Text(suggestion)
                            .font(AppFont.beVietnamPro(12, .medium))
                            .foregroundStyle(AppColor.brand)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppColor.brandSoft)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var saveToggle: some View {
        Toggle(isOn: $saveRecipient) {
            Text("Lưu vào danh bạ")
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payInk)
        }
        .tint(AppColor.brand)
    }

    // MARK: - Continue bar

    private var continueBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(AppColor.line).frame(height: 1)
            PrimaryButton(
                title: "Chuyển tiền", loadingTitle: "Đang xử lý...",
                isLoading: isSubmitting, isEnabled: canContinue
            ) {
                Task { await submitTransfer() }
            }
            .padding(16)
        }
        .background(Color.white)
    }

    // MARK: - Submit

    private func submitTransfer() async {
        // Chưa tra cứu ra người nhận thì không gửi — `canContinue` đã chặn nút, đây là
        // lớp cuối để không bao giờ gọi API với số ví chưa xác thực.
        guard let recipient else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let request = TransferToWalletRequest(
            idempotencyKey: idempotencyKey, benUsername: recipient.username,
            accName: recipient.holderName, transAmount: Int(amount), memo: effectiveMessage
        )

        do {
            // Mốc đo thời gian xử lý THẬT để biên lai không phải bịa "2,0 giây".
            submitStartedAt = Date()
            let result = try await TransferService.transferToWallet(request)
            await handleResult(result)
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Đã có lỗi xảy ra, vui lòng thử lại"
        }
    }

    /// Xác thực giao dịch pending bằng Face ID — ký số tiền + số ví người nhận rồi gửi chữ ký.
    ///
    /// `username` (không phải `recipient?.username`): ở chế độ nhập tay `recipient` là computed
    /// từ `verifiedName`, mà sheet này mở sau khi đã tra cứu xong nên `username` luôn là giá trị
    /// đã dùng để tạo giao dịch pending. Payload PHẢI khớp `signaturePayload()` bên BE.
    private func submitBiometric() async {
        guard let transactionId = pendingTransactionId else { return }
        do {
            // Đo từ lúc quét mặt xong — thời gian chờ người dùng không phải thời gian xử lý.
            submitStartedAt = Date()
            let result = try await BiometricService.verifyTransfer(
                transactionId: transactionId,
                amount: Int64(amount),
                recipient: username
            )
            await handleResult(result)
        } catch BiometricKeyError.userCancelled {
            // Người dùng huỷ hộp thoại Face ID: giữ sheet, KHÔNG báo lỗi đỏ — họ chỉ cần bấm
            // "Thử lại" hoặc "Dùng mật khẩu".
            biometricError = nil
        } catch BiometricKeyError.keyInvalidated {
            // Đổi/thêm khuôn mặt trong Cài đặt iOS -> khoá tự vô hiệu (.biometryCurrentSet).
            // Rơi thẳng về mật khẩu, không bắt người dùng thử lại vô ích.
            BiometricKeyStore.deleteKey()
            useBiometric = false
            pinError = "Face ID đã thay đổi, vui lòng nhập mật khẩu và bật lại trong Cá nhân"
        } catch let error as BiometricKeyError {
            biometricError = error.localizedDescription
        } catch let error as APIError {
            // 403 = BE nói "đừng quét lại nữa" (cooling-off 24h, thiết bị chưa đăng ký khoá,
            // sinh trắc bị khoá do thất bại nhiều lần). Chuyển thẳng sang mật khẩu thay vì để
            // người dùng bấm "Thử lại" mãi không được. Xem quy ước ở đầu `verifyTransfer` bên BE.
            // 400 và các lỗi khác: quét lại có thể được.
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
            // Đo lại từ lúc gửi PIN — thời gian gõ PIN không phải thời gian xử lý.
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
        // Đọc từ state chứ không nhận qua tham số: `handleResult` còn được gọi lại từ
        // `submitPin`, lúc đó không còn `recipient` của lời gọi đầu.
        let holderName = verifiedName ?? username
        let elapsed = submitStartedAt.map { Date().timeIntervalSince($0) }
        // `alreadySaved` phải kiểm lại ở đây: khi người nhận đã có trong danh bạ thì
        // toggle bị ẩn nhưng saveRecipient vẫn còn true -> tạo trùng bản ghi.
        if saveRecipient && !alreadySaved {
            _ = try? await BeneficiaryStore.shared.create(
                CreateBeneficiaryRequest(type: .wallet, accName: holderName, benUsername: username)
            )
        }
        if let token = initialDraft?.payLinkToken {
            await PayLinkService.consume(reqToken: token, txId: result.transId)
        }
        await WalletStore.shared.refresh(force: true)
        onSuccess(
            TransferSuccessInfo(
                kind: .wallet, amount: amount, recipientName: holderName,
                accountNumber: username,
                noteLabel: "Lời nhắn", note: effectiveMessage,
                transactionCode: result.bkTransId ?? result.transId,
                elapsedSeconds: elapsed,
                isProcessing: result.status == "PENDING",
                feeAmount: result.feeAmount
            )
        )
    }
}

#Preview("Nhập tay") {
    WalletTransferAmountView(onBack: {}, onSuccess: { _ in })
}

#Preview("Người nhận đã khoá") {
    WalletTransferAmountView(
        draft: WalletTransferDraft(username: "19957873068", holderName: "NGUYEN VAN A"),
        onBack: {}, onSuccess: { _ in }
    )
}
