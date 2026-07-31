//
//  AccountService.swift
//  nano ewallet
//
//  Mirror phần change-password/limit-pin trong EkycApi.kt — endpoint thật ở
//  be/src/modules/user (users/change-password) và be/src/modules/wallet (limit-pin).
//

import Foundation

enum AccountService {

    /// `POST users/change-password/request-otp`
    static func requestChangePasswordOtp() async throws {
        try await APIClient.shared.requestVoid(.post, "users/change-password/request-otp", auth: true)
    }

    /// `PATCH users/change-password`
    static func changePassword(
        currentPassword: String,
        newPassword: String,
        confirmNewPassword: String,
        otp: String
    ) async throws {
        let body = ChangePasswordRequest(
            currentPassword: currentPassword,
            newPassword: newPassword,
            confirmNewPassword: confirmNewPassword,
            otp: otp
        )
        try await APIClient.shared.requestVoid(.patch, "users/change-password", body: body, auth: true)
    }

    /// `POST wallet/limit-pin/request-otp`
    static func requestLimitPinOtp() async throws {
        try await APIClient.shared.requestVoid(.post, "wallet/limit-pin/request-otp", auth: true)
    }

    /// `POST wallet/limit-pin` — chỉ nhận 0..500.000đ (PIN_LIMIT_MAX).
    static func updateLimitPin(newLimit: Int, otp: String) async throws {
        let body = UpdateLimitPinRequest(newLimit: newLimit, otp: otp)
        try await APIClient.shared.requestVoid(.post, "wallet/limit-pin", body: body, auth: true)
    }
}
