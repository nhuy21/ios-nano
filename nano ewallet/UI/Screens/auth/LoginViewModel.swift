//
//  LoginViewModel.swift
//  nano ewallet
//
//  Mirror phần state + handleLogin() của LoginScreen.kt.
//

import Foundation

@MainActor
final class LoginViewModel: ObservableObject {

    @Published var phone = ""
    @Published var password = ""
    @Published var errors: [String: String] = [:]
    @Published var isSubmitting = false

    // Luồng máy khác đang đăng nhập.
    @Published var deviceTicket: String?
    @Published var showDeviceConflict = false
    @Published var sendingDeviceOtp = false
    @Published var deviceOtpPhone: String?
    @Published var showDeviceOtp = false

    /// Trả `(phone, status)` khi đăng nhập thành công để `onLogin` điều hướng.
    func submit() async -> (phone: String, status: String?)? {
        guard validate(), !isSubmitting else { return nil }
        isSubmitting = true
        defer { isSubmitting = false }

        let cleanPhone = phone.filter { !$0.isWhitespace }
        do {
            let outcome = try await AuthService.login(phone: cleanPhone, password: password)
            switch outcome {
            case .requireDeviceOtp(let ticket, _):
                deviceTicket = ticket
                showDeviceConflict = true
                return nil
            case .authenticated(let user):
                return (cleanPhone, user?.status)
            case .requireOtp(let user):
                // Không nên xảy ra ở login (chỉ verify-otp mới lặp lại vào PENDING),
                // nhưng vẫn xử lý để không im lặng bỏ qua.
                return (cleanPhone, user?.status)
            }
        } catch {
            errors["submit"] = (error as? APIError)?.message ?? "Đăng nhập thất bại, vui lòng thử lại"
            return nil
        }
    }

    func confirmDeviceOtp() async {
        guard let ticket = deviceTicket else { return }
        sendingDeviceOtp = true
        defer { sendingDeviceOtp = false }
        do {
            let phoneForOtp = try await AuthService.sendDeviceOtp(loginTicket: ticket)
            deviceOtpPhone = phoneForOtp
            showDeviceConflict = false
            showDeviceOtp = true
        } catch {
            showDeviceConflict = false
            deviceTicket = nil
            errors["submit"] = (error as? APIError)?.message ?? "Không gửi được mã OTP, vui lòng thử lại"
        }
    }

    func dismissDeviceConflict() {
        showDeviceConflict = false
        deviceTicket = nil
    }

    // MARK: - Private

    /// Mirror `validate()`: chỉ chạy lúc submit, không validate live.
    private func validate() -> Bool {
        errors = [:]
        let cleanPhone = phone.filter { !$0.isWhitespace }
        if !isValidPhoneFormat(cleanPhone) {
            errors["phone"] = "Số điện thoại không hợp lệ"
        }
        if !AuthValidator.isValidPassword(password) {
            errors["password"] = "Mật khẩu phải gồm đúng 6 chữ số"
        }
        return errors.isEmpty
    }

    private func isValidPhoneFormat(_ phone: String) -> Bool {
        phone.count >= 10 && phone.count <= 11 && phone.allSatisfy(\.isNumber)
    }
}
