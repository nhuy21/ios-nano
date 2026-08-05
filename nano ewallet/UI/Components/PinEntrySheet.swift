//
//  PinEntrySheet.swift
//  nano ewallet
//
//  Sheet nhập mật khẩu 6 số để xác thực giao dịch pending — mirror PinEntrySheet
//  (PaymentAuthComponents.kt). Dùng chung cho cả 2 luồng transfer (bank/wallet).
//

import SwiftUI

struct PinEntrySheet: View {
    let amountText: String
    let recipientName: String
    /// Cha xử lý gọi API verify-transfer; set `externalError` (qua Binding) nếu sai PIN
    /// để sheet tự xoá pin + hiện lỗi mà không cần đóng/mở lại sheet.
    var onSubmit: (String) async -> Void
    let onCancel: () -> Void
    @Binding var externalError: String?

    @State private var pin = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColor.line)
                .frame(width: 40, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 16)

            Text("Xác nhận chuyển tiền")
                .font(AppFont.beVietnamPro(17, .bold))
                .foregroundStyle(AppColor.payInk)

            VStack(spacing: 4) {
                Text(amountText)
                    .font(AppFont.beVietnamPro(28, .bold))
                    .foregroundStyle(AppColor.brand)
                Text("Đến \(recipientName)")
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.payMuted)
            }
            .padding(.top, 8)
            .padding(.bottom, 20)

            Text("Nhập mật khẩu 6 chữ số để xác nhận")
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)
                .padding(.bottom, 12)

            PinDotsField(
                value: $pin,
                placeholder: "Mật khẩu",
                hasError: externalError != nil,
                dotsAlignment: .center,
                submitLabel: .done,
                onSubmit: submit
            )
            .padding(.horizontal, 24)
            .onChangeNewCompat(of: pin) { newValue in
                if newValue.count == 6 { submit() }
            }

            if let externalError {
                FieldError(message: externalError)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 20)

            Button("Huỷ") { onCancel() }
                .buttonStyle(.plain)
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.payMuted)
                .padding(.bottom, 16)
        }
        .padding(.top, 4)
        .disabled(isSubmitting)
        .overlay {
            if isSubmitting {
                ProgressView().tint(AppColor.brand)
            }
        }
        .presentationDetents([.height(420)])
        // Sheet không set nền sẽ lấy nền hệ thống — ở dark mode là ĐEN, mà chữ trong đây
        // đều là màu tối cố định (`payInk`/`payMuted`) nên bị dìm gần như không đọc được.
        // Ghim nền sáng cho khớp Android (bên đó nền sheet là `Color.White` cứng).
        //
        // Phải giãn hết khung TRƯỚC khi tô nền: `VStack` chỉ cao bằng nội dung, mà detent
        // cố định thường cao hơn — tô nền theo `VStack` sẽ để hở dải dưới lộ lại nền đen.
        // `alignment: .top` giữ nội dung ở trên, không bị dồn ra giữa khi giãn.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .presentationDragIndicator(.hidden)
    }

    private func submit() {
        guard pin.count == 6, !isSubmitting else { return }
        externalError = nil
        Task {
            isSubmitting = true
            defer { isSubmitting = false }
            await onSubmit(pin)
            // Nếu cha set externalError sau khi onSubmit xong (sai PIN) -> xoá để nhập lại.
            if externalError != nil { pin = "" }
        }
    }
}
