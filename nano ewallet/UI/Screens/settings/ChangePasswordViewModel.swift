//
//  ChangePasswordViewModel.swift
//  nano ewallet
//
//  Mirror phần state của ChangeSecretScreen.kt — luồng 2 bước: gửi OTP rồi confirm.
//

import Foundation
import Combine

@MainActor
final class ChangePasswordViewModel: ObservableObject {

    @Published var currentPassword = ""
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published var otp = ""

    @Published var currentError: String?
    @Published var newError: String?
    @Published var confirmError: String?
    @Published var otpError: String?
    @Published var submitError: String?

    @Published var otpSent = false
    @Published var isSendingOtp = false
    @Published var isSubmitting = false
    @Published var showSuccess = false

    var allFilled: Bool {
        currentPassword.count == 6 && newPassword.count == 6 && confirmPassword.count == 6
    }

    var canSubmit: Bool {
        guard allFilled, !isSendingOtp, !isSubmitting else { return false }
        return otpSent ? otp.count == 6 : true
    }

    /// Bước 1: validate 3 field mật khẩu rồi gửi OTP.
    func sendOtp() async {
        guard validatePasswords(), !isSendingOtp else { return }
        isSendingOtp = true
        submitError = nil
        defer { isSendingOtp = false }
        do {
            try await AccountService.requestChangePasswordOtp()
            otpSent = true
        } catch {
            submitError = (error as? APIError)?.message ?? "Gửi mã OTP thất bại, vui lòng thử lại"
        }
    }

    /// Bước 2: validate lại + OTP rồi xác nhận đổi mật khẩu.
    func confirmChange() async {
        guard validatePasswords() else { return }
        guard AuthValidator.isValidOtp(otp) else {
            otpError = "Vui lòng nhập đủ 6 số"
            return
        }
        guard !isSubmitting else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        do {
            try await AccountService.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword,
                confirmNewPassword: confirmPassword,
                otp: otp
            )
            showSuccess = true
        } catch {
            submitError = (error as? APIError)?.message ?? "Đổi mật khẩu thất bại, vui lòng thử lại"
        }
    }

    func resendOtp() async {
        otp = ""
        otpError = nil
        await sendOtp()
    }

    // MARK: - Private

    private func validatePasswords() -> Bool {
        currentError = nil
        newError = nil
        confirmError = nil

        if currentPassword.count != 6 { currentError = "Vui lòng nhập đủ 6 số" }
        if newPassword.count != 6 {
            newError = "Vui lòng nhập đủ 6 số"
        } else if newPassword == currentPassword {
            newError = "Mật khẩu mới phải khác mật khẩu hiện tại"
        }
        if confirmPassword.count != 6 {
            confirmError = "Vui lòng nhập đủ 6 số"
        } else if confirmPassword != newPassword {
            confirmError = "Mật khẩu xác nhận không khớp"
        }

        return currentError == nil && newError == nil && confirmError == nil
    }
}
