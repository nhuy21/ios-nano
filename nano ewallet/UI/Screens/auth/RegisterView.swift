//
//  RegisterView.swift
//  nano ewallet
//
//  Mirror RegisterScreen.kt — dùng AppTextField/PinDotsField chung, canh lỗi TRÁI
//  (khác Login/ForgotPassword canh giữa) và container luôn trắng kể cả khi lỗi,
//  đúng như `RegisterTextField`/`RegisterPasswordField` bên Android.
//

import SwiftUI
import Combine

struct RegisterView: View {
    let onBack: () -> Void
    let onNext: (_ phone: String) -> Void
    let onLogin: () -> Void

    @StateObject private var vm = RegisterViewModel()
    /// Ô EMAIL vẫn dùng bàn phím hệ thống (cần chữ + @), nên nó là `TextField` thật và phải
    /// có `@FocusState` riêng. Ba ô còn lại dùng bàn phím TỰ VẼ, không có `TextField` nào để
    /// focus nên tiêu điểm của chúng chỉ là `@State` thường.
    ///
    /// Hai biến chứ không một: trộn vào một `@FocusState` thì lúc chọn ô số, SwiftUI vẫn coi
    /// là "có field đang focus" và bật bàn phím hệ thống lên chồng với bàn phím tự vẽ.
    @FocusState private var emailFocused: Bool
    @State private var focusedField: Field?

    private enum Field: Hashable { case phone, email, password, confirm }

    /// Số điện thoại VN dài nhất 10 số; mật khẩu 6 số như `PinDotsField.maxLength`.
    private static let phoneMaxLength = 10
    private static let passwordLength = 6

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
                        // 260 làm form 4 ô vượt 1 màn hình ~110pt -> đáy bị cắt lúc mới vào.
                        .frame(height: 150)

                    Spacer().frame(height: 10)

                    Text("Điền đầy đủ thông tin để tạo tài khoản")
                        .font(AppFont.beVietnamPro(14))
                        .foregroundStyle(AppColor.payMuted)

                    Spacer().frame(height: 24)

                    fieldBlock(label: "Số điện thoại", required: true) {
                        KeypadTextField(
                            text: vm.phone,
                            placeholder: "Nhập số điện thoại của bạn",
                            hasError: vm.errors["phone"] != nil,
                            isFocused: focusedField == .phone,
                            onTap: { focusedField = .phone }
                        )
                    }
                    if let error = vm.errors["phone"] {
                        FieldError(message: error, alignment: .leading)
                    }

                    Spacer().frame(height: 16)

                    fieldBlock(label: "Email", required: true) {
                        AppTextField(
                            text: $vm.email,
                            placeholder: "Nhập địa chỉ email của bạn",
                            keyboardType: .emailAddress,
                            submitLabel: .next
                        ) {
                            emailFocused = false
                            focusedField = .password
                        }
                        .focused($emailFocused)
                    }
                    if let error = vm.errors["email"] {
                        FieldError(message: error, alignment: .leading)
                    }

                    Spacer().frame(height: 16)

                    fieldBlock(label: "Mật khẩu", required: true) {
                        PinDotsField(
                            value: $vm.password,
                            placeholder: "Nhập mật khẩu",
                            hasError: false,
                            dotsAlignment: .leading,
                            submitLabel: .next,
                            onSubmit: { focusedField = .confirm },
                            // Đủ 6 số là tự nhảy sang ô nhập lại, không chờ bấm nút bàn phím.
                            onFilled: { focusedField = .confirm },
                            usesCustomKeypad: true,
                            externalFocus: focusedField == .password,
                            onTapWhenCustom: { focusedField = .password }
                        )
                    }
                    if let error = vm.errors["password"] {
                        FieldError(message: error, alignment: .leading)
                    }

                    Spacer().frame(height: 16)

                    fieldBlock(label: "Nhập lại mật khẩu", required: true) {
                        PinDotsField(
                            value: $vm.confirmPassword,
                            placeholder: "Nhập lại mật khẩu",
                            hasError: false,
                            dotsAlignment: .leading,
                            submitLabel: .done,
                            onSubmit: submit,
                            // Chỉ ẩn bàn phím để lộ nút "Tạo tài khoản", CỐ Ý không tự bấm:
                            // gõ sai số cuối là hiện "mật khẩu nhập lại không khớp" ngay giữa
                            // lúc người ta còn đang sửa.
                            onFilled: { focusedField = nil },
                            usesCustomKeypad: true,
                            externalFocus: focusedField == .confirm,
                            onTapWhenCustom: { focusedField = .confirm }
                        )
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
        // Bàn phím tự vẽ cho 3 ô SỐ (sĐT, mật khẩu, nhập lại). Ô email không qua đây — nó
        // cần chữ và "@" nên vẫn dùng bàn phím hệ thống.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let field = focusedField, field != .email {
                PlainNumericKeypad(
                    onDigit: { appendDigit($0, to: field) },
                    onBackspace: { backspace(from: field) },
                    onNext: { advance(from: field) },
                    nextTitle: field == .confirm ? "Xong" : "Tiếp",
                    nextEnabled: canAdvance(from: field)
                )
            } else {
                Color.clear.frame(height: 24)
            }
        }
        // Chạm vào ô email khi bàn phím tự vẽ đang mở: tắt nó đi, nếu không hai bàn phím
        // cùng nằm ở đáy màn.
        .onChangeNewCompat(of: emailFocused) { focused in
            if focused { focusedField = nil }
        }
        // Và chiều ngược lại: chọn một ô số khi bàn phím hệ thống của email đang mở.
        .onChangeNewCompat(of: focusedField) { field in
            if field != nil { emailFocused = false }
        }
        .screenBackground(Color.white)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func fieldBlock<Content: View>(
        label: String,
        required: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel(text: label, size: 13, required: required)
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

    // MARK: - Nhập bằng bàn phím tự vẽ

    private func appendDigit(_ digit: String, to field: Field) {
        switch field {
        case .phone:
            vm.phone = String((vm.phone + digit).prefix(Self.phoneMaxLength))
        case .password:
            guard vm.password.count < Self.passwordLength else { return }
            vm.password += digit
            // `onFilled` của `PinDotsField` chỉ bắn ở chế độ có `TextField`, nên tự nhảy ô
            // tại đây: đủ 6 số là sang ô nhập lại, không chờ bấm phím.
            if vm.password.count == Self.passwordLength { focusedField = .confirm }
        case .confirm:
            guard vm.confirmPassword.count < Self.passwordLength else { return }
            vm.confirmPassword += digit
            // Gõ đủ 6 số thì chỉ ẩn bàn phím để lộ nút "Tạo tài khoản", CỐ Ý không tự gọi
            // API — gõ sai số cuối là hiện "mật khẩu nhập lại không khớp" ngay giữa lúc
            // người ta còn đang sửa. Muốn gửi thì bấm "Xong" hoặc nút dưới màn, tức phải là
            // một hành động CHỦ ĐỘNG.
            if vm.confirmPassword.count == Self.passwordLength { focusedField = nil }
        case .email:
            break
        }
    }

    private func backspace(from field: Field) {
        switch field {
        case .phone: if !vm.phone.isEmpty { vm.phone.removeLast() }
        case .password: if !vm.password.isEmpty { vm.password.removeLast() }
        case .confirm: if !vm.confirmPassword.isEmpty { vm.confirmPassword.removeLast() }
        case .email: break
        }
    }

    /// Phím hành động: nhảy sang ô kế; ô cuối ("Xong") thì tạo tài khoản luôn.
    private func advance(from field: Field) {
        switch field {
        case .phone:
            focusedField = nil
            emailFocused = true
        case .password: focusedField = .confirm
        case .confirm:
            focusedField = nil
            submit()
        case .email: focusedField = nil
        }
    }

    private func canAdvance(from field: Field) -> Bool {
        switch field {
        case .phone: return !vm.phone.isEmpty
        case .password: return vm.password.count == Self.passwordLength
        case .confirm: return vm.confirmPassword.count == Self.passwordLength
        case .email: return false
        }
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
