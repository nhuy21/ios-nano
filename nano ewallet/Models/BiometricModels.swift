//
//  BiometricModels.swift
//  nano ewallet
//
//  Mirror wallet.dto.ts (RegisterBiometricDto, VerifyTransferBiometricDto, RemoveBiometricDto)
//  và auth.dto.ts (RegisterBiometricLoginDto, BiometricLoginDto).
//

import Foundation

// MARK: - Xác thực giao dịch

/// `POST wallet/biometric/register`
struct RegisterBiometricRequest: Encodable {
    let deviceId: String
    /// Khoá công khai P-256, SPKI DER dạng base64.
    let publicKey: String
    let password: String
}

struct RegisterBiometricResult: Decodable {
    let registeredAt: String
    /// Trong 24h đầu sau khi đăng ký, giao dịch vẫn phải nhập mật khẩu (cooling-off).
    let coolingOffUntil: String
}

/// `GET wallet/biometric/status`
struct BiometricStatus: Decodable {
    let enabled: Bool
    let registeredAt: String?
    let coolingOffUntil: String?
    let inCoolingOff: Bool
}

/// `POST wallet/verify-transfer-biometric`
struct VerifyTransferBiometricRequest: Encodable {
    let transactionId: String
    let deviceId: String
    /// Chữ ký ECDSA P-256 (DER) dạng base64.
    let signature: String
}

/// `DELETE wallet/biometric` — và cũng dùng cho `POST auth/biometric/remove`.
struct DeviceIdBody: Encodable {
    let deviceId: String
}

// MARK: - Đăng nhập

/// `POST auth/biometric/register`
struct RegisterBiometricLoginRequest: Encodable {
    let deviceId: String
    let password: String
}

struct RegisterBiometricLoginResult: Decodable {
    /// Chỉ nhận được ĐÚNG một lần — BE chỉ lưu SHA-256. Phải ghi ngay vào Keychain có ACL
    /// sinh trắc, mất là phải bật lại bằng mật khẩu.
    let biometricToken: String
    let expiredAt: String
}

/// `POST auth/biometric/login`
struct BiometricLoginRequest: Encodable {
    let deviceId: String
    let biometricToken: String
    let deviceName: String?
}
