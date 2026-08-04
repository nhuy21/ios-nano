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
        try await performTransfer("wallet/transfer-to-wallet", body: request)
    }

    /// `POST wallet/transfer-to-bank`
    static func transferToBank(_ request: TransferToBankRequest) async throws -> TransferResult {
        try await performTransfer("wallet/transfer-to-bank", body: request)
    }

    /// `POST wallet/verify-transfer` — xác thực PIN + thực thi giao dịch pending.
    static func verifyTransfer(_ request: VerifyTransferRequest) async throws -> TransferResult {
        try await performTransfer("wallet/verify-transfer", body: request)
    }

    /// `POST wallet/withdraw` — rút về TK ngân hàng.
    static func withdraw(_ request: WithdrawRequest) async throws -> TransferResult {
        try await performTransfer("wallet/withdraw", body: request)
    }

    /// Gọi 1 endpoint giao dịch, coi "2xx nhưng thiếu `data`" là THÀNH CÔNG RỖNG.
    ///
    /// Vì sao phải xử lý riêng: interceptor của BE (`format-response/success/
    /// transform.interceptor.ts`) LOẠI BỎ hẳn field `data` khi giá trị là null —
    /// mà `data` chính là `result.data` Bảo Kim trả, có lúc null. Để `APIClient` ném
    /// `thiếu data` như các endpoint khác thì app báo lỗi dù TIỀN ĐÃ TRỪ, và người dùng
    /// không thấy màn "chuyển tiền thành công".
    ///
    /// An toàn vì HTTP 2xx ở đây nghĩa là BE đã ghi giao dịch + trừ tiền xong; thiếu chi
    /// tiết chỉ làm biên lai ẩn vài dòng (mã GD, phí), không sai về tiền.
    private static func performTransfer(_ path: String, body: Encodable) async throws -> TransferResult {
        do {
            return try await APIClient.shared.request(
                .post, path, body: body, auth: true, slow: true, as: TransferResult.self
            )
        } catch APIError.missingData(_) {
            return .empty
        }
    }

    /// Sinh idempotencyKey 1 lần/session màn chuyển tiền — mirror cách Android sinh
    /// theo timestamp + suffix ngẫu nhiên (chỉ cần duy nhất, không cần bảo mật).
    static func newIdempotencyKey() -> String {
        "\(Int(Date().timeIntervalSince1970 * 1000))\(Int.random(in: 1000...9999))"
    }
}
