//
//  UnlinkWalletSheet.swift
//  nano ewallet
//
//  Sheet nhập mật khẩu 6 số để xác nhận HUỶ LIÊN KẾT ví Bảo Kim.
//
//  Tách riêng khỏi `PinEntrySheet`: sheet đó gắn với một giao dịch cụ thể (bắt buộc có
//  `amountText`/`recipientName` để người dùng đối chiếu trước khi ký), còn ở đây không có giao
//  dịch nào — chỉ xác nhận chủ tài khoản trước một thao tác không tự hoàn tác được.
//

import SwiftUI

struct UnlinkWalletSheet: View {
    @Binding var pin: String
    @Binding var errorText: String?
    var isSubmitting: Bool
    var onSubmit: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColor.line)
                .frame(width: 40, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 16)

            Text("Xác nhận huỷ liên kết")
                .font(AppFont.beVietnamPro(17, .bold))
                .foregroundStyle(AppColor.payInk)

            Text("Nhập mật khẩu 6 chữ số để xác nhận")
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)
                .padding(.top, 8)
                .padding(.bottom, 16)

            PinDotsField(
                value: $pin,
                placeholder: "Mật khẩu",
                hasError: errorText != nil,
                dotsAlignment: .center,
                submitLabel: .done,
                onSubmit: submit
            )
            .padding(.horizontal, 24)
            // Đủ 6 số là gửi luôn, không bắt bấm thêm nút — giống PinEntrySheet, và bàn phím số
            // trên một số máy không vẽ nút hành động nên người dùng gõ xong không biết bấm gì.
            .onChangeNewCompat(of: pin) { newValue in
                if newValue.count == 6 { submit() }
            }

            if let errorText {
                FieldError(message: errorText)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 20)

            Button("Huỷ") { onCancel() }
                .buttonStyle(PressableButtonStyle())
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.payMuted)
                .padding(.bottom, 16)
                .disabled(isSubmitting)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private func submit() {
        guard pin.count == 6, !isSubmitting else { return }
        onSubmit(pin)
    }
}
