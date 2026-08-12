//
//  ForgotPasswordView.swift
//  nano ewallet
//
//  Mirror ForgotPasswordScreen.kt. Sửa bug đã xác nhận: Android ghi comment ô SĐT
//  "locked" sau khi gửi mã nhưng không thực sự disable — bản này disable thật
//  bằng `.disabled(vm.codeSent)`.
//
//  Dùng `ForgotField`-style riêng (placeholder = label, canh giữa) khác AppTextField
//  dùng ở Login/Register — đúng spec khảo sát được.
//

import SwiftUI
import Combine

struct ForgotPasswordView: View {
    let onBack: () -> Void
    let onBackToLogin: () -> Void

    @StateObject private var vm = ForgotPasswordViewModel()
    /// `@State` chứ không `@FocusState`: các ô dùng bàn phím TỰ VẼ nên không có `TextField`
    /// thật nào để focus — biến này thuần là "ô nào đang nhận phím", `nil` = ẩn bàn phím.
    @State private var focusedField: Field?

    private enum Field: Hashable { case phone, otp, newPassword, confirm }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 64)

                    Image("logo_main")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 52)
                        .accessibilityLabel("Ví nano")

                    Spacer().frame(height: 24)

                    Text(title)
                        .font(AppFont.beVietnamPro(22, .bold))
                        .foregroundStyle(AppColor.payInk)
                        .multilineTextAlignment(.center)

                    Spacer().frame(height: 6)

                    Text(subtitle)
                        .font(AppFont.beVietnamPro(14))
                        .foregroundStyle(AppColor.payMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Spacer().frame(height: 28)

                    if !vm.resetDone {
                        formContent
                    } else {
                        successContent
                    }

                    if !vm.codeSent || vm.resetDone {
                        Spacer().frame(height: 20)
                        backToLoginLink
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 24)
            }
            // Bàn phím tự vẽ thay chỗ dải chừa 24pt khi có ô đang nhập. Bản KHÔNG có phím
            // "000": cả 4 ô đều là số đếm từng chữ (sĐT, mã OTP, mật khẩu), gõ tắt hàng
            // nghìn là vô nghĩa.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let field = focusedField {
                    PlainNumericKeypad(
                        onDigit: { appendDigit($0, to: field) },
                        onBackspace: { backspace(from: field) },
                        onNext: { advance(from: field) },
                        nextTitle: nextTitle(for: field),
                        nextEnabled: canAdvance(from: field)
                    )
                } else {
                    Color.clear.frame(height: 24)
                }
            }
            .screenBackground(Color.white)
            .dismissesCustomKeypadOnTap { focusedField = nil }
            .scrollDismissesKeyboard(.interactively)

            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppColor.brand)
                    .frame(width: 42, height: 42)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .circleButtonShadow()
            .padding(.leading, 16)
            .padding(.top, 8)
            .accessibilityLabel("Quay lại")
        }
    }

    // MARK: - Nội dung theo trạng thái

    @ViewBuilder
    private var formContent: some View {
        VStack(spacing: 0) {
            forgotField(
                placeholder: "Số điện thoại",
                text: vm.phone,
                field: .phone,
                error: vm.errors["phone"]
            )
            .disabled(vm.codeSent)
            .opacity(vm.codeSent ? 0.6 : 1)

            Spacer().frame(height: 12)

            if !vm.codeSent {
                PrimaryButton(
                    title: "Gửi mã xác nhận",
                    loadingTitle: "Đang gửi...",
                    isLoading: vm.isSending,
                    action: sendCode
                )
            } else {
                Spacer().frame(height: 12)

                forgotField(
                    placeholder: "Mã xác nhận (6 số)",
                    text: vm.otp,
                    field: .otp,
                    error: vm.errors["otp"]
                )

                Spacer().frame(height: 12)

                forgotField(
                    placeholder: "Mật khẩu mới (6 số)",
                    text: vm.newPassword,
                    field: .newPassword,
                    error: vm.errors["newPassword"]
                )

                Spacer().frame(height: 12)

                forgotField(
                    placeholder: "Xác nhận mật khẩu mới",
                    text: vm.confirmPassword,
                    field: .confirm,
                    error: vm.errors["confirmPassword"]
                )

                if let submitError = vm.errors["submit"] {
                    FieldError(message: submitError)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                }

                Spacer().frame(height: 12)

                PrimaryButton(
                    title: "Đặt lại mật khẩu",
                    loadingTitle: "Đang xử lý...",
                    isLoading: vm.isSubmitting,
                    isEnabled: vm.canSubmitReset,
                    action: submitReset
                )

                Spacer().frame(height: 12)

                Button {
                    sendCode()
                } label: {
                    Text("Không nhận được mã? Gửi lại")
                        .font(AppFont.beVietnamPro(13, .semibold))
                        .foregroundStyle(AppColor.brand)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(vm.isSending)
            }
        }
    }

    private var successContent: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(AppColor.okSoft)
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(AppColor.ok)
                }

            Spacer().frame(height: 28)

            PrimaryButton(title: "Quay lại đăng nhập", action: onBackToLogin)
        }
    }

    private var backToLoginLink: some View {
        HStack(spacing: 0) {
            Text("Nhớ mật khẩu rồi? ")
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payMuted)
            Text("Đăng nhập")
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.brand)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onBackToLogin() }
    }

    // MARK: - Field riêng của màn này (placeholder canh giữa, không có label riêng)

    /// Cả 4 ô của màn này đều là số nên dùng chung ô bàn phím tự vẽ. `field` thay cho
    /// `.focused(...)` trước đây — tiêu điểm giờ do `focusedField` giữ.
    @ViewBuilder
    private func forgotField(
        placeholder: String,
        text: String,
        field: Field,
        error: String?
    ) -> some View {
        VStack(spacing: 0) {
            KeypadTextField(
                text: text,
                placeholder: placeholder,
                hasError: error != nil,
                textAlignment: .center,
                isFocused: focusedField == field,
                onTap: { focusedField = field }
            )
            if let error {
                FieldError(message: error)
            }
        }
    }

    // MARK: - Nhập bằng bàn phím tự vẽ

    /// Độ dài tối đa từng ô, đúng bằng `maxLength` của bản `AppTextField` trước đây.
    private func maxLength(of field: Field) -> Int {
        switch field {
        case .phone: return 11
        case .otp, .newPassword, .confirm: return 6
        }
    }

    private func binding(for field: Field) -> String {
        switch field {
        case .phone: return vm.phone
        case .otp: return vm.otp
        case .newPassword: return vm.newPassword
        case .confirm: return vm.confirmPassword
        }
    }

    private func setValue(_ value: String, for field: Field) {
        switch field {
        case .phone: vm.phone = value
        case .otp: vm.otp = value
        case .newPassword: vm.newPassword = value
        case .confirm: vm.confirmPassword = value
        }
    }

    private func appendDigit(_ digit: String, to field: Field) {
        let next = binding(for: field) + digit
        setValue(String(next.prefix(maxLength(of: field))), for: field)
    }

    private func backspace(from field: Field) {
        var current = binding(for: field)
        guard !current.isEmpty else { return }
        current.removeLast()
        setValue(current, for: field)
    }

    /// Phím hành động: nhảy sang ô kế, ô cuối thì chạy luôn hành động của bước đó.
    private func advance(from field: Field) {
        switch field {
        case .phone:
            focusedField = nil
            if !vm.codeSent { sendCode() }
        case .otp: focusedField = .newPassword
        case .newPassword: focusedField = .confirm
        case .confirm:
            focusedField = nil
            submitReset()
        }
    }

    private func canAdvance(from field: Field) -> Bool {
        !binding(for: field).isEmpty
    }

    private func nextTitle(for field: Field) -> String {
        switch field {
        case .phone: return "Gửi mã"
        case .otp, .newPassword: return "Tiếp"
        case .confirm: return "Xong"
        }
    }

    private var title: String {
        vm.resetDone ? "Đặt lại mật khẩu thành công" : "Quên mật khẩu?"
    }

    private var subtitle: String {
        if vm.resetDone {
            return "Mật khẩu của bạn đã được đặt lại. Hãy đăng nhập bằng mật khẩu mới."
        }
        if vm.codeSent {
            return "Nhập mã xác nhận đã gửi tới Zalo và mật khẩu mới của bạn."
        }
        return "Nhập số điện thoại đã đăng ký, chúng tôi sẽ gửi mã xác nhận để đặt lại mật khẩu."
    }

    private func sendCode() {
        Task { await vm.sendCode() }
    }

    private func submitReset() {
        Task { _ = await vm.resetPassword() }
    }
}

#Preview {
    ForgotPasswordView(onBack: {}, onBackToLogin: {})
}
