//
//  RegisterViewModel.swift
//  nano ewallet
//
//  Mirror phần state + handleNext() của RegisterScreen.kt.
//

import Foundation
import Combine

@MainActor
final class RegisterViewModel: ObservableObject {

    @Published var phone = ""
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var errors: [String: String] = [:]
    @Published var isSubmitting = false

    /// Trả về true nếu đăng ký thành công, để View điều hướng sang OTP.
    func submit() async -> Bool {
        guard validate(), !isSubmitting else { return false }
        isSubmitting = true
        defer { isSubmitting = false }

        let cleanPhone = phone.filter { !$0.isWhitespace }
        do {
            try await AuthService.register(
                phone: cleanPhone,
                password: password,
                confirmPassword: confirmPassword,
                email: email
            )
            return true
        } catch {
            errors["submit"] = (error as? APIError)?.message ?? "Đăng ký thất bại, vui lòng thử lại"
            return false
        }
    }

    var cleanPhone: String { phone.filter { !$0.isWhitespace } }

    // MARK: - Private

    private func validate() -> Bool {
        errors = [:]
        let cleanPhone = phone.filter { !$0.isWhitespace }
        if !(cleanPhone.count >= 10 && cleanPhone.count <= 11 && cleanPhone.allSatisfy(\.isNumber)) {
            errors["phone"] = "Số điện thoại không hợp lệ (VD: 0912345678)"
        }
        if email.isEmpty || !AuthValidator.isValidEmail(email) {
            errors["email"] = "Địa chỉ email không hợp lệ"
        }
        if !AuthValidator.isValidPassword(password) {
            errors["password"] = "Mật khẩu phải gồm đúng 6 chữ số"
        }
        if password != confirmPassword {
            errors["confirmPassword"] = "Mật khẩu nhập lại không khớp"
        }
        return errors.isEmpty
    }
}
