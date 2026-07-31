//
//  BankTransferAmountView.swift
//  nano ewallet
//
//  Mirror phần "gộp" của TransferScreen.kt cho luồng ngân hàng — người nhận đã
//  xác thực xong ở BankTransferView, màn này chỉ còn số tiền + nội dung + PIN.
//

import SwiftUI

@MainActor
struct BankTransferAmountView: View {
    let draft: BankTransferDraft
    let onBack: () -> Void
    let onSuccess: (TransferSuccessInfo) -> Void

    /// Hạn mức 1 lần chuyển — mirror TransferScreen.kt. Nhập tối đa 9 chữ số
    /// (chặn ở `amountFieldBinding.set`), số này chặn thêm ở mức hạn mức thật.
    private static let maxAmountPerTransfer: Int64 = 10_000_000
    private static let suggestions = ["Chuyển tiền", "Trả tiền ăn", "Gửi tặng"]

    @StateObject private var wallet = WalletStore.shared

    @State private var amountText = ""
    @State private var memo = ""
    @State private var saveRecipient = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    @State private var pendingTransactionId: String?
    @State private var pinError: String?

    @FocusState private var isAmountFocused: Bool
    @FocusState private var isMemoFocused: Bool

    private let idempotencyKey = TransferService.newIdempotencyKey()

    private var amount: Int64 { Int64(amountText) ?? 0 }

    private var overLimit: Bool {
        if let balance = wallet.balance { return amount > balance }
        return false
    }

    private var overMaxPerTransfer: Bool { amount > Self.maxAmountPerTransfer }

    private var canContinue: Bool { amount > 0 && !overMaxPerTransfer }

    private var effectiveMemo: String {
        let trimmed = memo.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Chuyen tien" : trimmed
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    recipientCard
                    amountSection
                    memoSection
                    saveToggle
                    if let errorMessage {
                        FieldError(message: errorMessage, alignment: .leading)
                    }
                }
                .padding(16)
            }
            continueBar
        }
        .background(Color(hex: 0xF7F8FA))
        .sheet(isPresented: pendingTransactionIdBinding) {
            PinEntrySheet(
                amountText: Int(amount).vndFormatted,
                recipientName: draft.holderName,
                onSubmit: submitPin,
                onCancel: { pendingTransactionId = nil },
                externalError: $pinError
            )
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

    // MARK: - Người nhận (read-only)

    private var recipientCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppColor.brandSoft)
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(draft.holderName.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppColor.brand)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.holderName)
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.payInk)
                Text("\(draft.bankName) • \(draft.accNo)")
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

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Số tiền")
            AppTextField(
                text: amountFieldBinding,
                placeholder: "0",
                keyboardType: .numberPad,
                submitLabel: .next,
                textAlignment: .leading,
                digitsOnly: true
            )
            .focused($isAmountFocused)
            .numericKeyboardToolbar(label: "Tiếp theo") { isMemoFocused = true }

            if overMaxPerTransfer {
                FieldError(message: "Số tiền chuyển tối đa 1 lần là 10.000.000đ", alignment: .leading)
            } else if overLimit {
                FieldError(message: "Số tiền vượt quá số dư khả dụng", alignment: .leading)
            }
        }
    }

    /// Format hiển thị "1.234.567" trong lúc gõ — lưu raw digits ở `amountText`.
    private var amountFieldBinding: Binding<String> {
        Binding(
            get: { amount > 0 ? Int(amount).vndFormatted.replacingOccurrences(of: " đ", with: "") : "" },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                amountText = String(digits.prefix(9))
            }
        )
    }

    // MARK: - Nội dung

    private var memoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Nội dung chuyển khoản")
            AppTextField(
                text: $memo, placeholder: "Nhập nội dung chuyển khoản",
                submitLabel: .done, maxLength: 250
            )
            .focused($isMemoFocused)

            HStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button {
                        memo = suggestion
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

        let request = TransferToBankRequest(
            idempotencyKey: idempotencyKey,
            accNo: draft.accNo, accType: draft.accType, bankNo: draft.bin,
            accName: draft.holderName, transAmount: Int(amount), memo: effectiveMemo
        )

        do {
            let result = try await TransferService.transferToBank(request)
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
        if saveRecipient {
            try? await BeneficiaryStore.shared.create(
                CreateBeneficiaryRequest(
                    type: .bankAccount, bankNo: draft.bin, accNo: draft.accNo, accName: draft.holderName
                )
            )
        }
        await WalletStore.shared.refresh(force: true)
        onSuccess(
            TransferSuccessInfo(
                amount: amount, recipientName: draft.holderName,
                recipientDetail: "\(draft.bankName) • \(draft.accNo)",
                noteLabel: "Nội dung", note: effectiveMemo
            )
        )
    }
}

#Preview {
    BankTransferAmountView(
        draft: BankTransferDraft(bin: "970436", bankName: "Vietcombank", accNo: "0123456789", accType: 0, holderName: "NGUYEN VAN A"),
        onBack: {}, onSuccess: { _ in }
    )
}
