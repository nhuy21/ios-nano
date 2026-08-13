//
//  ChangePasswordView.swift
//  nano ewallet
//
//  Mirror ChangeSecretScreen.kt — 3 field mật khẩu (PinDotsField) rồi tới OTP 2 bước.
//

import SwiftUI
import Combine

struct ChangePasswordView: View {
    let onBack: () -> Void

    @StateObject private var vm = ChangePasswordViewModel()
    /// `@State` chứ không `@FocusState`: bốn ô đều dùng bàn phím TỰ VẼ nên không có
    /// `TextField` thật nào để focus — biến này thuần là "ô nào đang nhận phím".
    @State private var focusedField: Field?

    private enum Field: Hashable { case current, new, confirm, otp }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "Đổi mật khẩu", onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Mật khẩu đăng nhập gồm 6 chữ số. Không dùng dãy số dễ đoán (123456, ngày sinh...).")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)

                    Spacer().frame(height: 16)

                    passwordCard

                    if vm.otpSent {
                        Spacer().frame(height: 16)
                        otpCard
                    }

                    if let submitError = vm.submitError {
                        FieldError(message: submitError)
                            .padding(.top, 8)
                    }

                    Spacer().frame(height: 20)

                    PrimaryButton(
                        title: vm.otpSent ? "Xác nhận" : "Gửi mã OTP",
                        loadingTitle: vm.otpSent ? "Đang xử lý..." : "Đang gửi...",
                        isLoading: vm.isSendingOtp || vm.isSubmitting,
                        isEnabled: vm.canSubmit,
                        action: submit
                    )
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
        }
        // Bàn phím số tự vẽ, bản KHÔNG có phím "000": mật khẩu và mã OTP là 6 chữ số rời,
        // gõ tắt hàng nghìn là vô nghĩa.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let field = focusedField {
                PlainNumericKeypad(
                    onDigit: { appendDigit($0, to: field) },
                    onBackspace: { backspace(from: field) },
                    onNext: { advance(from: field) },
                    nextTitle: field == .otp ? "Xác nhận" : "Tiếp",
                    nextEnabled: value(of: field).count == Self.codeLength
                )
            }
        }
        .screenBackground(Color(hex: 0xF7F8FA))
        .dismissesCustomKeypadOnTap { focusedField = nil }
        .alert("Đổi mật khẩu thành công", isPresented: $vm.showSuccess) {
            Button("Xong") { onBack() }
        } message: {
            Text("Thay đổi đã được áp dụng cho lần đăng nhập/giao dịch tiếp theo.")
        }
    }

    private var passwordCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldBlock(label: "Mật khẩu hiện tại", error: vm.currentError) {
                PinDotsField(
                    value: $vm.currentPassword,
                    placeholder: "Nhập mật khẩu hiện tại",
                    hasError: vm.currentError != nil,
                    submitLabel: .next,
                    // `onSubmit` truyền TƯỜNG MINH: trailing closure gắn vào tham số CUỐI của
                    // hàm, mà giờ tham số cuối là `onTapWhenCustom`.
                    onSubmit: { focusedField = .new },
                    usesCustomKeypad: true,
                    externalFocus: focusedField == .current,
                    onTapWhenCustom: { focusedField = .current }
                )

            }

            fieldBlock(label: "Mật khẩu mới", error: vm.newError) {
                PinDotsField(
                    value: $vm.newPassword,
                    placeholder: "Nhập mật khẩu mới",
                    hasError: vm.newError != nil,
                    submitLabel: .next,
                    onSubmit: { focusedField = .confirm },
                    usesCustomKeypad: true,
                    externalFocus: focusedField == .new,
                    onTapWhenCustom: { focusedField = .new }
                )

            }

            fieldBlock(label: "Xác nhận mật khẩu mới", error: vm.confirmError) {
                PinDotsField(
                    value: $vm.confirmPassword,
                    placeholder: "Nhập lại mật khẩu mới",
                    hasError: vm.confirmError != nil,
                    submitLabel: .done,
                    onSubmit: { Task { await vm.sendOtp() } },
                    usesCustomKeypad: true,
                    externalFocus: focusedField == .confirm,
                    onTapWhenCustom: { focusedField = .confirm }
                )

            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(hex: 0x784628).opacity(0x14 / 255.0), radius: 6, x: 0, y: 2)
    }

    private var otpCard: some View {
        fieldBlock(label: "Mã OTP (SMS)", error: vm.otpError) {
            PinDotsField(
                value: $vm.otp,
                placeholder: "Nhập mã 6 số",
                hasError: vm.otpError != nil,
                dotsAlignment: .center,
                submitLabel: .done,
                onSubmit: { Task { await vm.confirmChange() } },
                usesCustomKeypad: true,
                externalFocus: focusedField == .otp,
                onTapWhenCustom: { focusedField = .otp }
            )
            .focused($focusedField, equals: .otp)

            Button {
                Task { await vm.resendOtp() }
            } label: {
                Text(vm.isSendingOtp ? "Đang gửi..." : "Không nhận được mã? Gửi lại")
                    .font(AppFont.beVietnamPro(13, .semibold))
                    .foregroundStyle(AppColor.brand)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(vm.isSendingOtp)
            .padding(.top, 8)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(hex: 0x784628).opacity(0x14 / 255.0), radius: 6, x: 0, y: 2)
    }

    @ViewBuilder
    private func fieldBlock<Content: View>(
        label: String, error: String?, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel(text: label, size: 13)
            content()
            if let error {
                FieldError(message: error, alignment: .leading)
            }
        }
    }

    // MARK: - Nhập bằng bàn phím tự vẽ

    /// Mật khẩu và OTP đều 6 chữ số, khớp `PinDotsField.maxLength`.
    private static let codeLength = 6

    private func value(of field: Field) -> String {
        switch field {
        case .current: return vm.currentPassword
        case .new: return vm.newPassword
        case .confirm: return vm.confirmPassword
        case .otp: return vm.otp
        }
    }

    private func setValue(_ newValue: String, for field: Field) {
        switch field {
        case .current: vm.currentPassword = newValue
        case .new: vm.newPassword = newValue
        case .confirm: vm.confirmPassword = newValue
        case .otp: vm.otp = newValue
        }
    }

    private func appendDigit(_ digit: String, to field: Field) {
        let current = value(of: field)
        guard current.count < Self.codeLength else { return }
        setValue(current + digit, for: field)
    }

    private func backspace(from field: Field) {
        var current = value(of: field)
        guard !current.isEmpty else { return }
        current.removeLast()
        setValue(current, for: field)
    }

    /// Phím hành động: nhảy sang ô kế; ô cuối của mỗi bước thì chạy luôn việc của bước đó.
    private func advance(from field: Field) {
        switch field {
        case .current: focusedField = .new
        case .new: focusedField = .confirm
        case .confirm:
            focusedField = nil
            Task { await vm.sendOtp() }
        case .otp:
            focusedField = nil
            Task { await vm.confirmChange() }
        }
    }

    private func submit() {
        Task {
            if vm.otpSent {
                await vm.confirmChange()
            } else {
                await vm.sendOtp()
            }
        }
    }
}

#Preview {
    ChangePasswordView(onBack: {})
}
