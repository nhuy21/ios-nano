//
//  WalletTransferAmountView.swift
//  nano ewallet
//
//  Mirror WalletTransferAmountScreen.kt — số tiền + lời nhắn (140 ký tự, khác 250
//  của bank transfer), PIN sheet dùng chung với luồng ngân hàng.
//

import SwiftUI
import Combine

@MainActor
struct WalletTransferAmountView: View {
    let draft: WalletTransferDraft
    let onBack: () -> Void
    let onSuccess: (TransferSuccessInfo) -> Void

    private static let maxAmountPerTransfer: Int64 = 10_000_000
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
    @State private var pinError: String?

    /// Bàn phím số tự vẽ đang hiện hay không. Mở sẵn khi vào màn, chạm ra ngoài thì ẩn,
    /// chạm vào ô số tiền thì mở lại. Không phải @FocusState vì bàn phím này là SwiftUI
    /// thuần — `endEditing` ở tầng UIWindow không đụng tới được.
    @State private var isAmountFocused = true
    @FocusState private var isMessageFocused: Bool

    private let idempotencyKey = TransferService.newIdempotencyKey()

    init(
        draft: WalletTransferDraft,
        onBack: @escaping () -> Void,
        onSuccess: @escaping (TransferSuccessInfo) -> Void
    ) {
        self.draft = draft
        self.onBack = onBack
        self.onSuccess = onSuccess
        _amountText = State(initialValue: draft.prefillAmount.map(String.init) ?? "")
    }

    private var amount: Int64 { Int64(amountText) ?? 0 }
    private var overLimit: Bool {
        if let balance = wallet.balance { return amount > balance }
        return false
    }
    private var overMaxPerTransfer: Bool { amount > Self.maxAmountPerTransfer }
    private var canContinue: Bool { amount > 0 && !overMaxPerTransfer }

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
            $0.type == .wallet && $0.benUsername == draft.username
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
            .filter { $0 <= Self.maxAmountPerTransfer }
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
            guard let parsed = try? await SpeechService.parseTransfer(transcripts: candidates),
                  parsed.amount > 0 else {
                voiceHint = "Chưa nghe rõ số tiền, thử nói \"hai trăm nghìn\""
                return
            }
            applyVoiceAmount(parsed.amount)
        }
    }

    private func applyVoiceAmount(_ amount: Int64) {
        voiceHint = nil
        amountText = String(min(amount, Self.maxAmountPerTransfer))
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
            // trong bàn phím, giống màn nhập tiền bên Android.
            if isAmountFocused && !isMessageFocused {
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
        .background(Color(hex: 0xF7F8FA))
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
            guard amountText.isEmpty, speech.isAvailable else { return }
            // Đệm nhỏ để hiệu ứng chuyển màn xong rồi mới chiếm micro.
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, amountText.isEmpty else { return }
            await speech.start()
        }
        .onDisappear { speech.stop() }
        .sheet(isPresented: pendingTransactionIdBinding) {
            PinEntrySheet(
                amountText: Int(amount).vndFormatted,
                recipientName: draft.holderName,
                onSubmit: submitPin,
                onCancel: { pendingTransactionId = nil },
                externalError: $pinError
            )
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
            Text("SỐ TIỀN")
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

    // MARK: - TK nguồn (ví của người gửi + số dư)

    private var sourceAccountCard: some View {
        SourceAccountCard(username: wallet.bkUsername, balance: wallet.balance)
    }

    // MARK: - Người nhận (read-only)

    private var recipientCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppColor.brandSoft)
                .frame(width: 44, height: 44)
                .overlay {
                    Text(draft.holderName.nameInitials)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppColor.brand)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.holderName)
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.payInk)
                Text("Ví nano · \(draft.username)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.payMuted)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Số tiền

    /// Số tiền hiển thị lớn, LUÔN có dấu chấm phân nghìn. Việc nhập/xoá do bàn phím tự
    /// vẽ ở dưới đảm nhiệm nên không dùng ô nhập của hệ thống nữa.
    private var amountSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Text(amountText.isEmpty ? "0đ" : "\(Int(amount).vndGrouped)đ")
                    .font(AppFont.baloo2(34, .bold))
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
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.payMuted)
            }

            TextField("Nhập nội dung chuyển tiền", text: $message, axis: .vertical)
                .font(AppFont.beVietnamPro(17, .semibold))
                .foregroundStyle(AppColor.payInk)
                .tint(AppColor.brand)
                .lineLimit(1...4)
                .focused($isMessageFocused)
                .onChange(of: message) { _, newValue in
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
                            .font(.system(size: 12, weight: .medium))
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
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let request = TransferToWalletRequest(
            idempotencyKey: idempotencyKey, benUsername: draft.username,
            accName: draft.holderName, transAmount: Int(amount), memo: effectiveMessage
        )

        do {
            let result = try await TransferService.transferToWallet(request)
            await handleResult(result)
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Đã có lỗi xảy ra, vui lòng thử lại"
        }
    }

    private func submitPin(_ pin: String) async {
        guard let transactionId = pendingTransactionId else { return }
        do {
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
        // `alreadySaved` phải kiểm lại ở đây: khi người nhận đã có trong danh bạ thì
        // toggle bị ẩn nhưng saveRecipient vẫn còn true -> tạo trùng bản ghi.
        if saveRecipient && !alreadySaved {
            _ = try? await BeneficiaryStore.shared.create(
                CreateBeneficiaryRequest(type: .wallet, accName: draft.holderName, benUsername: draft.username)
            )
        }
        if let token = draft.payLinkToken {
            await PayLinkService.consume(reqToken: token, txId: result.transId)
        }
        await WalletStore.shared.refresh(force: true)
        onSuccess(
            TransferSuccessInfo(
                amount: amount, recipientName: draft.holderName,
                recipientDetail: "Ví nano • \(draft.username)",
                noteLabel: "Lời nhắn", note: effectiveMessage
            )
        )
    }
}

#Preview {
    WalletTransferAmountView(
        draft: WalletTransferDraft(username: "19957873068", holderName: "NGUYEN VAN A"),
        onBack: {}, onSuccess: { _ in }
    )
}
