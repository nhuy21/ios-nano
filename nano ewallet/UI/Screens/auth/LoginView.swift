//
//  LoginView.swift
//  nano ewallet
//
//  Mirror LoginScreen.kt.
//

import SwiftUI

struct LoginView: View {
    let onLogin: (_ phone: String, _ status: String?) -> Void
    let onRegister: () -> Void
    let onForgotPassword: () -> Void

    @StateObject private var vm = LoginViewModel()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case phone, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 28)

                Image("login_signin")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)

                Spacer().frame(height: 16)

                Text("Đăng nhập")
                    .font(AppFont.beVietnamPro(24, .bold))
                    .foregroundStyle(AppColor.payInk)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Nhập thông tin để tiếp tục")
                    .font(AppFont.beVietnamPro(14))
                    .foregroundStyle(AppColor.payMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                Spacer().frame(height: 24)

                FieldLabel(text: "Số điện thoại")
                AppTextField(
                    text: $vm.phone,
                    placeholder: "Nhập số điện thoại",
                    keyboardType: .phonePad,
                    submitLabel: .next,
                    hasError: vm.errors["phone"] != nil
                ) {
                    focusedField = .password
                }
                .focused($focusedField, equals: .phone)
                .numericKeyboardToolbar { focusedField = .password }
                if let phoneError = vm.errors["phone"] {
                    FieldError(message: phoneError)
                }

                Spacer().frame(height: 16)

                FieldLabel(text: "Mật khẩu")
                PinDotsField(
                    value: $vm.password,
                    placeholder: "Nhập mật khẩu",
                    hasError: vm.errors["password"] != nil,
                    dotsAlignment: .leading,
                    submitLabel: .done,
                    onSubmit: submit
                )
                .numericKeyboardToolbar(label: "Xong", action: submit)
                if let passwordError = vm.errors["password"] {
                    FieldError(message: passwordError)
                }
                if let submitError = vm.errors["submit"] {
                    FieldError(message: submitError)
                }

                Spacer().frame(height: 12)

                Button("Quên mật khẩu?") {
                    onForgotPassword()
                }
                .buttonStyle(.plain)
                .font(AppFont.beVietnamPro(13, .semibold))
                .foregroundStyle(AppColor.brand)
                .frame(maxWidth: .infinity, alignment: .trailing)

                Spacer().frame(height: 20)

                PrimaryButton(
                    title: "Đăng nhập",
                    loadingTitle: "Đang đăng nhập...",
                    isLoading: vm.isSubmitting,
                    action: submit
                )

                Spacer().frame(height: 20)

                OrDivider()

                Spacer().frame(height: 20)

                registerLink

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.white)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $vm.showDeviceConflict) {
            DeviceConflictDialog(
                sending: vm.sendingDeviceOtp,
                onDismiss: vm.dismissDeviceConflict,
                onConfirm: { Task { await vm.confirmDeviceOtp() } }
            )
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $vm.showDeviceOtp) {
            if let ticket = vm.deviceTicket {
                DeviceOtpDialog(
                    loginTicket: ticket,
                    phone: vm.deviceOtpPhone,
                    onDismiss: { vm.showDeviceOtp = false },
                    onSuccess: { outcome in
                        vm.showDeviceOtp = false
                        if case .authenticated(let user) = outcome {
                            onLogin(vm.phone, user?.status)
                        }
                    }
                )
                .presentationBackground(.clear)
            }
        }
    }

    private var registerLink: some View {
        HStack(spacing: 0) {
            Text("Chưa có tài khoản? ")
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payMuted)
            Text("Đăng kí")
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.brand)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onRegister() }
    }

    private func submit() {
        Task {
            if let result = await vm.submit() {
                onLogin(result.phone, result.status)
            }
        }
    }
}

#Preview {
    LoginView(onLogin: { _, _ in }, onRegister: {}, onForgotPassword: {})
}
