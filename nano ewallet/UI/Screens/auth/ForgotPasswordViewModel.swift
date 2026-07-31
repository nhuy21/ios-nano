//
//  ForgotPasswordViewModel.swift
//  nano ewallet
//
//  Mirror phần state của ForgotPasswordScreen.kt.
//

import Foundation

@MainActor
final class ForgotPasswordViewModel: ObservableObject {

    @Published var phone = ""
    @Published var otp = ""
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published var errors: [String: String] = [:]
    @Published var isSending = false
    @Published var isSubmitting = false
    @Published var codeSent = false
    @Published var resetDone = false

    var canSubmitReset: Bool {
        otp.count == 6 && newPassword.count == 6 && confirmPassword.count == 6
    }

    func sendCode() async {
        guard validatePhone(), !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await AuthService.sendPasswordReset(phone: phone)
            codeSent = true
            errors = [:]
        } catch {
            // Hiện dưới ô SĐT — mirror `errors["phone"]` bên Android.
            errors["phone"] = (error as? APIError)?.message ?? "Gửi mã xác nhận thất bại, vui lòng thử lại"
        }
    }

    func resetPassword() async -> Bool {
        guard validateReset(), !isSubmitting else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await AuthService.resetPassword(
                phone: phone, otp: otp, newPassword: newPassword, confirmPassword: confirmPassword
            )
            resetDone = true
            errors = [:]
            return true
        } catch {
            errors["submit"] = (error as? APIError)?.message ?? "Đặt lại mật khẩu thất bại, vui lòng thử lại"
            return false
        }
    }

    // MARK: - Private

    private func validatePhone() -> Bool {
        errors = [:]
        if !(phone.count >= 10 && phone.count <= 11 && phone.allSatisfy(\.isNumber)) {
            errors["phone"] = "Số điện thoại không hợp lệ"
        }
        return errors.isEmpty
    }

    private func validateReset() -> Bool {
        errors = [:]
        if !AuthValidator.isValidOtp(otp) {
            errors["otp"] = "Mã OTP phải gồm đúng 6 chữ số"
        }
        if !AuthValidator.isValidPassword(newPassword) {
            errors["newPassword"] = "Mật khẩu mới phải gồm đúng 6 chữ số"
        }
        if !AuthValidator.isValidPassword(confirmPassword) {
            errors["confirmPassword"] = "Xác nhận mật khẩu không hợp lệ"
        } else if confirmPassword != newPassword {
            errors["confirmPassword"] = "Mật khẩu xác nhận không khớp"
        }
        return errors.isEmpty
    }
}
