//
//  ConversationView.swift
//  nano ewallet
//
//  Mirror ConversationScreen.kt — 1 màn dạng chat 2 chiều dùng chung cho cả người
//  xin tiền lẫn người bị xin: composer nhập số tiền + lời nhắn để GỬI yêu cầu,
//  mỗi bubble lịch sử có nút Đồng ý/Từ chối (yêu cầu đến, PENDING) hoặc Huỷ (yêu
//  cầu đi, PENDING). "Đồng ý" KHÔNG tự chuyển tiền ở BE — App phải tự gọi tiếp
//  transfer-to-wallet tới requester rồi verify-transfer nếu vượt ngưỡng PIN.
//

import SwiftUI

@MainActor
struct ConversationView: View {
    let otherBkUsername: String
    let onBack: () -> Void

    private static let maxRequestAmount: Int64 = 2_000_000

    @State private var displayName: String
    @State private var items: [MoneyRequestItem] = []
    @State private var isLoading = true

    @State private var amountText = ""
    @State private var note = ""
    @State private var isSending = false

    @State private var busyId: String?
    @State private var pendingTransactionId: String?
    @State private var pinError: String?
    @State private var pinRecipientName = ""
    @State private var pinAmount: Int64 = 0
    @State private var errorMessage: String?

    @FocusState private var isAmountFocused: Bool
    @FocusState private var isNoteFocused: Bool

    init(otherName: String, otherBkUsername: String, onBack: @escaping () -> Void) {
        self.otherBkUsername = otherBkUsername
        self.onBack = onBack
        _displayName = State(initialValue: otherName)
    }

    private var amount: Int64 { Int64(amountText) ?? 0 }

    /// Gợi ý số tiền nhặt từ lời nhắn (regex đơn giản: "100k", "1tr", "100.000"...).
    private var suggestedAmount: Int64? {
        Self.suggestAmount(from: note)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            composer
        }
        .background(Color.white)
        .task { await reload() }
        .sheet(isPresented: pendingTransactionIdBinding) {
            PinEntrySheet(
                amountText: Int(pinAmount).vndFormatted,
                recipientName: pinRecipientName,
                onSubmit: submitPin,
                onCancel: {
                    pendingTransactionId = nil
                    busyId = nil
                },
                externalError: $pinError
            )
        }
    }

    private var pendingTransactionIdBinding: Binding<Bool> {
        Binding(get: { pendingTransactionId != nil }, set: { if !$0 { pendingTransactionId = nil } })
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColor.payInk)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            Circle()
                .fill(AppColor.brandSoft)
                .frame(width: 38, height: 38)
                .overlay {
                    Text(Self.initials(for: displayName))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppColor.brand)
                }

            VStack(alignment: .leading, spacing: 0) {
                Text(displayName.isEmpty ? "Cuộc thoại" : displayName)
                    .font(AppFont.beVietnamPro(16, .bold))
                    .foregroundStyle(AppColor.payInk)
                Text("Xin chuyển tiền")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.payMuted)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.white)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - Nội dung

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            ProgressView().tint(AppColor.brand).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            Text("Chưa có yêu cầu nào.\nNhập số tiền + lời nhắn để xin chuyển tiền.")
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payMuted)
                .multilineTextAlignment(.center)
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        bubble(for: item)
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
        }
    }

    private func bubble(for item: MoneyRequestItem) -> some View {
        let pending = item.status == .pending
        return HStack {
            if item.outgoing { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.outgoing ? "Bạn xin \(Int(item.amountValue).vndFormatted)" : "\(displayName) xin bạn \(Int(item.amountValue).vndFormatted)")
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(AppColor.payInk)

                if let note = item.note, !note.isEmpty {
                    Text("\"\(note)\"")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColor.payInk.opacity(0.8))
                }

                Text(item.status.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusColor(item.status))

                if pending && !item.outgoing {
                    HStack(spacing: 8) {
                        Button { decline(item) } label: {
                            Text("Từ chối")
                                .font(AppFont.beVietnamPro(14, .semibold))
                                .foregroundStyle(AppColor.payMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button { approve(item) } label: {
                            Text("Đồng ý")
                                .font(AppFont.beVietnamPro(14, .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(AppColor.brand)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .disabled(busyId == item.id)
                    .opacity(busyId == item.id ? 0.6 : 1)
                    .padding(.top, 4)
                } else if pending && item.outgoing {
                    Button("Huỷ yêu cầu") { cancel(item) }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.error)
                        .disabled(busyId == item.id)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: 300, alignment: .leading)
            .background(item.outgoing ? AppColor.brandSoft : AppColor.bgSoft)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !item.outgoing { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: item.outgoing ? .trailing : .leading)
    }

    private func statusColor(_ status: MoneyRequestStatus) -> Color {
        switch status {
        case .approved: return AppColor.ok
        case .declined, .expired, .cancelled: return AppColor.muted
        case .pending: return AppColor.brand
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let suggestedAmount, suggestedAmount > 0, suggestedAmount <= Self.maxRequestAmount, amountText.isEmpty {
                Button {
                    amountText = String(suggestedAmount)
                } label: {
                    Text("Dùng \(Int(suggestedAmount).vndFormatted)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.brand)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppColor.brandSoft)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            AppTextField(text: $note, placeholder: "Lời nhắn (vd: mẹ ơi chuyển cho con 100k)", submitLabel: .next, maxLength: 200)
                .focused($isNoteFocused)
                .onSubmit { isAmountFocused = true }

            if let errorMessage {
                FieldError(message: errorMessage, alignment: .leading)
            }

            HStack(spacing: 10) {
                AppTextField(
                    text: amountFieldBinding, placeholder: "Số tiền",
                    keyboardType: .numberPad, submitLabel: .done, digitsOnly: true
                )
                .focused($isAmountFocused)

                Button {
                    send()
                } label: {
                    ZStack {
                        Circle().fill(AppColor.brand).frame(width: 52, height: 52)
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSending)
            }
        }
        .padding(12)
        .background(Color.white)
        .shadow(color: .black.opacity(0.06), radius: 8, y: -2)
    }

    private var amountFieldBinding: Binding<String> {
        Binding(
            get: { amountText },
            set: { newValue in amountText = String(newValue.filter(\.isNumber).prefix(9)) }
        )
    }

    // MARK: - Actions

    private func reload() async {
        do {
            let detail = try await MoneyRequestService.conversation(otherBkUsername: otherBkUsername)
            if let fullName = detail.other.fullName, !fullName.isEmpty { displayName = fullName }
            items = detail.items
        } catch {
            // giữ dữ liệu cũ, mirror Android (bỏ qua lỗi reload)
        }
        isLoading = false
    }

    private func send() {
        guard !isSending else { return }
        if amount <= 0 {
            errorMessage = "Nhập số tiền"
            return
        }
        if amount > Self.maxRequestAmount {
            errorMessage = "Tối đa \(Int(Self.maxRequestAmount).vndFormatted)"
            return
        }
        errorMessage = nil
        isSending = true
        Task {
            defer { isSending = false }
            do {
                _ = try await MoneyRequestService.create(
                    payerBkUsername: otherBkUsername, amount: Int(amount),
                    note: note.trimmingCharacters(in: .whitespaces)
                )
                amountText = ""
                note = ""
                await reload()
            } catch let error as APIError {
                errorMessage = error.message
            } catch {
                errorMessage = "Gửi yêu cầu thất bại"
            }
        }
    }

    /// Đồng ý = chuyển tiền cho requester như luồng chuyển ví→ví bình thường:
    /// 1) approve (đánh dấu APPROVED; hết hạn/không còn PENDING -> BE ném lỗi, dừng).
    /// 2) transfer-to-wallet đúng số tiền yêu cầu tới `otherBkUsername`.
    private func approve(_ item: MoneyRequestItem) {
        guard busyId == nil, item.amountValue > 0 else { return }
        busyId = item.id
        Task {
            do {
                let approved = try await MoneyRequestService.approve(id: item.id)
                let recipientBk = approved.requesterBkUsername ?? otherBkUsername
                let memo = (item.note?.isEmpty == false) ? item.note! : "Chuyển theo yêu cầu"
                let result = try await TransferService.transferToWallet(
                    TransferToWalletRequest(
                        idempotencyKey: TransferService.newIdempotencyKey(),
                        benUsername: recipientBk, transAmount: Int(item.amountValue), memo: memo
                    )
                )
                if result.isPending, let transactionId = result.transactionId {
                    pinAmount = item.amountValue
                    pinRecipientName = displayName
                    pendingTransactionId = transactionId
                } else {
                    await reload()
                    busyId = nil
                }
            } catch let error as APIError {
                errorMessage = error.message
                busyId = nil
            } catch {
                errorMessage = "Chuyển tiền thất bại"
                busyId = nil
            }
        }
    }

    private func submitPin(_ pin: String) async {
        guard let transactionId = pendingTransactionId else { return }
        do {
            _ = try await TransferService.verifyTransfer(
                VerifyTransferRequest(password: pin, transactionId: transactionId)
            )
            pendingTransactionId = nil
            await reload()
            busyId = nil
        } catch let error as APIError {
            pinError = error.message
        } catch {
            pinError = "Đã có lỗi xảy ra, vui lòng thử lại"
        }
    }

    private func decline(_ item: MoneyRequestItem) {
        guard busyId == nil else { return }
        busyId = item.id
        Task {
            do {
                try await MoneyRequestService.decline(id: item.id)
                await reload()
            } catch let error as APIError {
                errorMessage = error.message
            } catch {
                errorMessage = "Từ chối thất bại"
            }
            busyId = nil
        }
    }

    private func cancel(_ item: MoneyRequestItem) {
        guard busyId == nil else { return }
        busyId = item.id
        Task {
            do {
                try await MoneyRequestService.cancel(id: item.id)
                await reload()
            } catch let error as APIError {
                errorMessage = error.message
            } catch {
                errorMessage = "Huỷ thất bại"
            }
            busyId = nil
        }
    }

    // MARK: - Helpers

    private static func initials(for name: String) -> String {
        name.nameInitials
    }

    /// Gợi ý số tiền từ lời nhắn — mirror suggestAmount() bên Android (regex đơn giản hoá):
    /// "100k"/"1tr"/"2 triệu" hoặc số có phân tách nghìn "100.000".
    private static func suggestAmount(from text: String) -> Int64? {
        let lowered = text.lowercased()
        if let match = try? NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?)\s*(triệu|tr|nghìn|ngàn|k)"#)
            .firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
           let numRange = Range(match.range(at: 1), in: lowered),
           let unitRange = Range(match.range(at: 2), in: lowered) {
            let numString = lowered[numRange].replacingOccurrences(of: ",", with: ".")
            guard let num = Double(numString) else { return nil }
            let unit = String(lowered[unitRange])
            let multiplier: Double
            switch unit {
            case "triệu", "tr": multiplier = 1_000_000
            case "nghìn", "ngàn", "k": multiplier = 1_000
            default: multiplier = 1
            }
            return Int64(num * multiplier)
        }
        if let match = try? NSRegularExpression(pattern: #"\b(\d{1,3}(?:[.,]\d{3})+)\b"#)
            .firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
           let range = Range(match.range(at: 1), in: lowered) {
            let digits = lowered[range].replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
            return Int64(digits)
        }
        return nil
    }
}

#Preview {
    ConversationView(otherName: "Nguyễn Văn A", otherBkUsername: "19957873068", onBack: {})
}
