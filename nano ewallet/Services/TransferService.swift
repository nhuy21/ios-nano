//
//  TransferService.swift
//  nano ewallet
//
//  Mirror TransferApi.kt + wallet.controller.ts (POST wallet/verify-beneficiary,
//  transfer-to-wallet, transfer-to-bank, verify-transfer). Dùng `slow: true` như
//  transfer bên Android (chờ Bảo Kim có thể tới 10s ở BE).
//

import Foundation

enum TransferService {
    /// `POST wallet/verify-beneficiary` — trả thẳng tên chủ tài khoản/ví (String, không object).
    static func verifyBeneficiary(_ request: VerifyBeneficiaryRequest) async throws -> String {
        try await APIClient.shared.request(
            .post, "wallet/verify-beneficiary", body: request, auth: true, as: String.self
        )
    }

    /// `POST wallet/transfer-to-wallet`
    static func transferToWallet(_ request: TransferToWalletRequest) async throws -> TransferResult {
        try await APIClient.shared.request(
            .post, "wallet/transfer-to-wallet", body: request, auth: true, slow: true, as: TransferResult.self
        )
    }

    /// `POST wallet/transfer-to-bank`
    static func transferToBank(_ request: TransferToBankRequest) async throws -> TransferResult {
        try await APIClient.shared.request(
            .post, "wallet/transfer-to-bank", body: request, auth: true, slow: true, as: TransferResult.self
        )
    }

    /// `POST wallet/verify-transfer` — xác thực PIN + thực thi giao dịch pending.
    static func verifyTransfer(_ request: VerifyTransferRequest) async throws -> TransferResult {
        try await APIClient.shared.request(
            .post, "wallet/verify-transfer", body: request, auth: true, slow: true, as: TransferResult.self
        )
    }

    /// `POST wallet/withdraw` — rút về TK ngân hàng.
    static func withdraw(_ request: WithdrawRequest) async throws -> TransferResult {
        try await APIClient.shared.request(
            .post, "wallet/withdraw", body: request, auth: true, slow: true, as: TransferResult.self
        )
    }

    /// Sinh idempotencyKey 1 lần/session màn chuyển tiền — mirror cách Android sinh
    /// theo timestamp + suffix ngẫu nhiên (chỉ cần duy nhất, không cần bảo mật).
    static func newIdempotencyKey() -> String {
        "\(Int(Date().timeIntervalSince1970 * 1000))\(Int.random(in: 1000...9999))"
    }
}
