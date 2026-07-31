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

struct ForgotPasswordView: View {
    let onBack: () -> Void
    let onBackToLogin: () -> Void

    @StateObject private var vm = ForgotPasswordViewModel()
    @FocusState private var focusedField: Field?

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
                        .font(AppFont.baloo2(22, .bold))
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
            .background(Color.white)
            .scrollDismissesKeyboard(.interactively)

            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppColor.brand)
                    .frame(width: 42, height: 42)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
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
                text: $vm.phone,
                keyboardType: .phonePad,
                submitLabel: vm.codeSent ? .done : .done,
                maxLength: 11,
                error: vm.errors["phone"]
            ) {
                if !vm.codeSent { sendCode() }
            }
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
                    text: $vm.otp,
                    keyboardType: .numberPad,
                    submitLabel: .next,
                    maxLength: 6,
                    error: vm.errors["otp"]
                ) {
                    focusedField = .newPassword
                }
                .focused($focusedField, equals: .otp)

                Spacer().frame(height: 12)

                forgotField(
                    placeholder: "Mật khẩu mới (6 số)",
                    text: $vm.newPassword,
                    keyboardType: .numberPad,
                    submitLabel: .next,
                    maxLength: 6,
                    error: vm.errors["newPassword"]
                ) {
                    focusedField = .confirm
                }
                .focused($focusedField, equals: .newPassword)

                Spacer().frame(height: 12)

                forgotField(
                    placeholder: "Xác nhận mật khẩu mới",
                    text: $vm.confirmPassword,
                    keyboardType: .numberPad,
                    submitLabel: .done,
                    maxLength: 6,
                    error: vm.errors["confirmPassword"]
                ) {
                    submitReset()
                }
                .focused($focusedField, equals: .confirm)

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
                .buttonStyle(.plain)
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

    @ViewBuilder
    private func forgotField(
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType,
        submitLabel: SubmitLabel,
        maxLength: Int,
        error: String?,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            AppTextField(
                text: text,
                placeholder: placeholder,
                keyboardType: keyboardType,
                submitLabel: submitLabel,
                hasError: error != nil,
                textAlignment: .center,
                maxLength: maxLength,
                digitsOnly: keyboardType == .numberPad || keyboardType == .phonePad,
                onSubmit: onSubmit
            )
            if let error {
                FieldError(message: error)
            }
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
            return "Nhập mã xác nhận đã gửi và mật khẩu mới của bạn."
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
