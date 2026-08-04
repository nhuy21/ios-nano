//
//  WelcomeBackViewModel.swift
//  nano ewallet
//
//  Mirror phần state của WelcomeBackScreen.kt.
//

import Foundation
import Combine

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

    /// Máy này đã bật đăng nhập sinh trắc chưa — chỉ kiểm tra có token, KHÔNG bật Face ID.
    var canUseBiometric: Bool { BiometricService.hasLoginToken }

    /// Đăng nhập bằng Face ID: quét mặt để đọc token trong Keychain rồi đổi lấy session.
    /// KHÔNG gửi mật khẩu — máy không lưu mật khẩu nào cả.
    ///
    /// Xử lý outcome giống hệt `submit`: BE vẫn có thể đòi OTP thiết bị nếu máy khác đang đăng
    /// nhập (sinh trắc không né được ràng buộc 1 thiết bị).
    func submitBiometric() async -> LoginResult {
        guard !isSubmitting else { return .failed }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let outcome = try await BiometricService.loginWithBiometric()
            switch outcome {
            case .requireDeviceOtp(let ticket, _):
                deviceTicket = ticket
                showDeviceConflict = true
                return .handledByDialog
            case .authenticated(let user), .requireOtp(let user):
                return .success(status: user?.status)
            }
        } catch BiometricKeyError.userCancelled {
            // Huỷ quét mặt: im lặng, người dùng nhập mật khẩu như thường.
            return .failed
        } catch BiometricKeyError.keyMissing {
            // Token đã mất (đổi khuôn mặt, xoá app cài lại) -> tắt hẳn để lần sau không hiện nút.
            BiometricTokenStore.remove()
            errorMsg = "Đăng nhập sinh trắc không còn hiệu lực, vui lòng nhập mật khẩu"
            return .failed
        } catch let error as APIError {
            // BE thu hồi token (đổi mật khẩu, bị force-logout ở máy khác) -> xoá token cục bộ,
            // không thì lần nào mở app cũng quét mặt rồi lỗi.
            if case .server(let code, _) = error, code == 401 {
                BiometricTokenStore.remove()
            }
            errorMsg = error.message
            return .failed
        } catch {
            errorMsg = "Đăng nhập sinh trắc thất bại, vui lòng nhập mật khẩu"
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
