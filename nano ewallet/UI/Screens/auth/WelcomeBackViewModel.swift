//
//  WelcomeBackViewModel.swift
//  nano ewallet
//
//  Mirror phần state của WelcomeBackScreen.kt.
//

import Foundation

@MainActor
final class WelcomeBackViewModel: ObservableObject {

    @Published var password = ""
    @Published var errorMsg: String?
    @Published var isSubmitting = false

    @Published var deviceTicket: String?
    @Published var showDeviceConflict = false
    @Published var sendingDeviceOtp = false
    @Published var deviceOtpPhone: String?
    @Published var showDeviceOtp = false

    enum LoginResult {
        case success(status: String?)
        case handledByDialog
        case failed
    }

    func submit(phone: String) async -> LoginResult {
        guard AuthValidator.isValidPassword(password) else {
            errorMsg = "Mật khẩu phải gồm đúng 6 chữ số"
            return .failed
        }
        guard !isSubmitting else { return .failed }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            // rememberPhone: false — SĐT đã có sẵn (từ lastPhone), không ghi lại.
            let outcome = try await AuthService.login(phone: phone, password: password, rememberPhone: false)
            switch outcome {
            case .requireDeviceOtp(let ticket, _):
                deviceTicket = ticket
                showDeviceConflict = true
                return .handledByDialog
            case .authenticated(let user):
                return .success(status: user?.status)
            case .requireOtp(let user):
                return .success(status: user?.status)
            }
        } catch {
            errorMsg = (error as? APIError)?.message ?? "Đăng nhập thất bại, vui lòng thử lại"
            return .failed
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
            errorMsg = (error as? APIError)?.message ?? "Không gửi được mã OTP, vui lòng thử lại"
        }
    }

    func dismissDeviceConflict() {
        showDeviceConflict = false
        deviceTicket = nil
    }
}
