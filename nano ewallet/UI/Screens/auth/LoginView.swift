//
//  LoginView.swift
//  nano ewallet
//
//  Mirror LoginScreen.kt.
//

import SwiftUI
import Combine

struct LoginView: View {
    let onLogin: (_ phone: String, _ status: String?) -> Void
    let onRegister: () -> Void
    let onForgotPassword: () -> Void

    @StateObject private var vm = LoginViewModel()
    /// `@State` chứ không `@FocusState`: cả hai ô dùng bàn phím TỰ VẼ nên không có
    /// `TextField` thật nào để mà focus — tiêu điểm ở đây thuần là "ô nào đang nhận phím".
    /// `nil` = không ô nào, bàn phím ẩn.
    @State private var focusedField: Field?

    private enum Field: Hashable { case phone, password }

    /// Số điện thoại VN dài nhất 10 số.
    private static let phoneMaxLength = 10

    /// Caret nháy của ô sĐT. Cùng nhịp 0.5s với `PinDotsField` để hai ô không lệch pha.
    @State private var caretVisible = true
    private let caretTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 28)

                // Cap chiều cao như các màn auth khác (Register 260, WelcomeBack 200):
                // không cap thì ảnh phình theo bề ngang, đẩy nội dung vượt 1 màn hình
                // khiến phần dưới bị cắt lúc mới vào (ScrollView còn ở offset 0).
                Image("login_signin")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)

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
                phoneField
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
                    onSubmit: submit,
                    usesCustomKeypad: true,
                    externalFocus: focusedField == .password,
                    onTapWhenCustom: { focusedField = .password }
                )
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
                .buttonStyle(PressableButtonStyle())
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
        // Bàn phím tự vẽ thay chỗ dải chừa 24pt khi có ô đang nhập. Dùng bản KHÔNG có phím
        // "000": số điện thoại và mật khẩu gõ tắt hàng nghìn là vô nghĩa.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let field = focusedField {
                PlainNumericKeypad(
                    onDigit: { appendDigit($0, to: field) },
                    onBackspace: { backspace(from: field) },
                    onNext: { advance(from: field) },
                    nextTitle: field == .phone ? "Tiếp" : "Xong",
                    nextEnabled: canAdvance(from: field)
                )
            } else {
                Color.clear.frame(height: 24)
            }
        }
        .screenBackground(Color.white)
        .scrollDismissesKeyboard(.interactively)
        .onReceive(caretTimer) { _ in
            guard focusedField == .phone else {
                caretVisible = false
                return
            }
            caretVisible.toggle()
        }
        .onChangeNewCompat(of: vm.phone) { _ in
            // Vừa gõ/xoá thì caret sáng lại ngay, không phải chờ nhịp timer kế tiếp.
            if focusedField == .phone { caretVisible = true }
        }
        .sheet(isPresented: $vm.showDeviceConflict) {
            DeviceConflictDialog(
                sending: vm.sendingDeviceOtp,
                onDismiss: vm.dismissDeviceConflict,
                onConfirm: { Task { await vm.confirmDeviceOtp() } }
            )
            .transparentSheetBackground()
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
                .transparentSheetBackground()
            }
        }
    }

    private var registerLink: some View {
        HStack(spacing: 0) {
            Text("Chưa có tài khoản? ")
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payMuted)
            Text("Đăng ký")
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.brand)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onRegister() }
    }

    // MARK: - Ô số điện thoại

    /// Hiển thị thuần, KHÔNG phải `TextField`: có `TextField` thật là iOS bật bàn phím hệ
    /// thống lên chồng với bàn phím tự vẽ. Trông vẫn như ô nhập bình thường (nền, viền,
    /// caret nháy) nhưng mọi ký tự đến từ `PlainNumericKeypad`.
    private var phoneField: some View {
        let focused = focusedField == .phone
        let hasError = vm.errors["phone"] != nil
        return HStack(spacing: 0) {
            if vm.phone.isEmpty && !focused {
                Text("Nhập số điện thoại")
                    .font(AppFont.beVietnamPro(18))
                    .foregroundStyle(AppColor.payPlaceholder)
            } else {
                Text(vm.phone)
                    .font(AppFont.beVietnamPro(18, .medium))
                    .foregroundStyle(AppColor.payInk)
                // Caret nháy ngay sau số cuối, dùng chung nhịp với `PinDotsField`.
                if focused {
                    Rectangle()
                        .fill(AppColor.brand)
                        .frame(width: 2, height: 24)
                        .opacity(caretVisible ? 1 : 0)
                        .padding(.leading, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(hasError ? AppColor.errorSoft : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(hasError ? AppColor.error : AppColor.payInputBorder, lineWidth: 1)
        }
        .inputShadow()
        .contentShape(Rectangle())
        .onTapGesture { focusedField = .phone }
    }

    // MARK: - Nhập bằng bàn phím tự vẽ

    private func appendDigit(_ digit: String, to field: Field) {
        switch field {
        case .phone:
            vm.phone = String((vm.phone + digit).prefix(Self.phoneMaxLength))
        case .password:
            // 6 số như `PinDotsField.maxLength`; đủ 6 thì dừng nhận thêm.
            guard vm.password.count < 6 else { return }
            vm.password += digit
        }
    }

    private func backspace(from field: Field) {
        switch field {
        case .phone: if !vm.phone.isEmpty { vm.phone.removeLast() }
        case .password: if !vm.password.isEmpty { vm.password.removeLast() }
        }
    }

    /// Phím hành động: ô sĐT thì sang ô mật khẩu, ô mật khẩu thì đăng nhập luôn.
    private func advance(from field: Field) {
        switch field {
        case .phone: focusedField = .password
        case .password:
            focusedField = nil
            submit()
        }
    }

    private func canAdvance(from field: Field) -> Bool {
        switch field {
        case .phone: return !vm.phone.isEmpty
        case .password: return vm.password.count == 6
        }
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
