//
//  RegisterView.swift
//  nano ewallet
//
//  Mirror RegisterScreen.kt — dùng AppTextField/PinDotsField chung, canh lỗi TRÁI
//  (khác Login/ForgotPassword canh giữa) và container luôn trắng kể cả khi lỗi,
//  đúng như `RegisterTextField`/`RegisterPasswordField` bên Android.
//

import SwiftUI

struct RegisterView: View {
    let onBack: () -> Void
    let onNext: (_ phone: String) -> Void
    let onLogin: () -> Void

    @StateObject private var vm = RegisterViewModel()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email, password, confirm }

    var body: some View {
        VStack(spacing: 0) {
            BackHeader(action: onBack)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image("register_signup")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)

                    Spacer().frame(height: 10)

                    Text("Điền đầy đủ thông tin để tạo tài khoản")
                        .font(AppFont.beVietnamPro(14))
                        .foregroundStyle(AppColor.payMuted)

                    Spacer().frame(height: 24)

                    fieldBlock(label: "Số điện thoại") {
                        AppTextField(
                            text: $vm.phone,
                            placeholder: "Nhập số điện thoại của bạn",
                            keyboardType: .phonePad,
                            submitLabel: .next
                        ) {
                            focusedField = .email
                        }
                        .numericKeyboardToolbar { focusedField = .email }
                    }
                    if let error = vm.errors["phone"] {
                        FieldError(message: error, alignment: .leading)
                    }

                    Spacer().frame(height: 16)

                    fieldBlock(label: "Email") {
                        AppTextField(
                            text: $vm.email,
                            placeholder: "Nhập địa chỉ email của bạn",
                            keyboardType: .emailAddress,
                            submitLabel: .next
                        ) {
                            focusedField = .password
                        }
                        .focused($focusedField, equals: .email)
                    }
                    if let error = vm.errors["email"] {
                        FieldError(message: error, alignment: .leading)
                    }

                    Spacer().frame(height: 16)

                    fieldBlock(label: "Mật khẩu") {
                        PinDotsField(
                            value: $vm.password,
                            placeholder: "Nhập mật khẩu",
                            hasError: false,
                            dotsAlignment: .leading,
                            submitLabel: .next
                        ) {
                            focusedField = .confirm
                        }
                        .focused($focusedField, equals: .password)
                        .numericKeyboardToolbar { focusedField = .confirm }
                    }
                    if let error = vm.errors["password"] {
                        FieldError(message: error, alignment: .leading)
                    }

                    Spacer().frame(height: 16)

                    fieldBlock(label: "Nhập lại mật khẩu") {
                        PinDotsField(
                            value: $vm.confirmPassword,
                            placeholder: "Nhập lại mật khẩu",
                            hasError: false,
                            dotsAlignment: .leading,
                            submitLabel: .done,
                            onSubmit: submit
                        )
                        .focused($focusedField, equals: .confirm)
                        .numericKeyboardToolbar(label: "Xong", action: submit)
                    }
                    if let error = vm.errors["confirmPassword"] {
                        FieldError(message: error, alignment: .leading)
                    }

                    Spacer().frame(height: 8)

                    if let submitError = vm.errors["submit"] {
                        FieldError(message: submitError, alignment: .center)
                            .padding(.bottom, 12)
                    }

                    PrimaryButton(
                        title: "Tạo tài khoản",
                        loadingTitle: "Đang tạo tài khoản...",
                        isLoading: vm.isSubmitting,
                        action: submit
                    )

                    Spacer().frame(height: 20)

                    loginLink

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
        }
        .background(Color.white)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func fieldBlock<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel(text: label, size: 13)
            content()
        }
    }

    private var loginLink: some View {
        HStack(spacing: 0) {
            Text("Đã có tài khoản? ")
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payMuted)
            Text("Đăng nhập")
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.brand)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onLogin() }
    }

    private func submit() {
        Task {
            if await vm.submit() {
                onNext(vm.cleanPhone)
            }
        }
    }
}

#Preview {
    RegisterView(onBack: {}, onNext: { _ in }, onLogin: {})
}
