//
//  AccountService.swift
//  nano ewallet
//
//  Mirror phần change-password/limit-pin trong EkycApi.kt — endpoint thật ở
//  be/src/modules/user (users/change-password) và be/src/modules/wallet (limit-pin).
//

import Foundation

/// Hồ sơ người dùng cho màn Thông tin cá nhân — `GET users/me`.
///
/// `phone`/`email`/`kycStatus` KHÔNG optional vì BE luôn trả (tài khoản nào cũng có), còn
/// nhóm thông tin giấy tờ chỉ có sau khi eKYC xong nên để optional.
struct UserProfile: Decodable {
    let fullName: String?
    let phone: String
    let email: String
    let idNumber: String?
    let birthDay: String?
    /// 1 = Nam, 2 = Nữ, 3 = Khác — xem `PersonalInfoView.genderLabel`.
    let gender: Int?
    let kycStatus: String
}

enum AccountService {

    /// `GET users/me` — hồ sơ đầy đủ cho màn Thông tin cá nhân.
    static func getMyProfile() async throws -> UserProfile {
        try await APIClient.shared.request(.get, "users/me", auth: true, as: UserProfile.self)
    }

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
