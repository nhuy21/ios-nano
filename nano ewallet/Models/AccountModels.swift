//
//  AccountModels.swift
//  nano ewallet
//
//  Mirror be/src/modules/user/dto/user.dto.ts (đổi mật khẩu) và
//  be/src/modules/wallet/dto/wallet.dto.ts (đổi ngưỡng PIN).
//

import Foundation

struct ChangePasswordRequest: Encodable {
    let currentPassword: String
    let newPassword: String
    let confirmNewPassword: String
    let otp: String
}

struct UpdateLimitPinRequest: Encodable {
    let newLimit: Int
    let otp: String
}

enum WalletLimits {
    /// Mirror `PIN_LIMIT_MAX` ở be/src/modules/wallet/dto/wallet.dto.ts — ngưỡng PIN
    /// chỉ nhận giá trị 0..500.000đ.
    static let pinLimitMax: Int = 500_000
}
