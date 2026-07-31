//
//  TransferModels.swift
//  nano ewallet
//
//  Mirror be/src/modules/wallet/dto/wallet.dto.ts — request gửi lên trans_amount
//  là Number (không phải String) dù response BE trả BIGINT dạng String.
//

import Foundation

/// `POST wallet/verify-beneficiary` — xác thực người thụ hưởng theo 1 trong 2 nhánh
/// loại trừ nhau: ví (benUsername) HOẶC ngân hàng (accNo + bankNo + accType).
struct VerifyBeneficiaryRequest: Encodable {
    var benUsername: String?
    var accNo: String?
    var bankNo: Int?
    var accType: Int?
}

struct TransferToWalletRequest: Encodable {
    let idempotencyKey: String
    let benUsername: String
    var accName: String?
    let transAmount: Int
    let memo: String

    enum CodingKeys: String, CodingKey {
        case idempotencyKey
        case benUsername = "ben_username"
        case accName = "acc_name"
        case transAmount = "trans_amount"
        case memo
    }
}

struct TransferToBankRequest: Encodable {
    let idempotencyKey: String
    let accNo: String
    let accType: Int
    let bankNo: String
    var accName: String?
    let transAmount: Int
    let memo: String

    enum CodingKeys: String, CodingKey {
        case idempotencyKey
        case accNo = "acc_no"
        case accType = "acc_type"
        case bankNo = "bank_no"
        case accName = "acc_name"
        case transAmount = "trans_amount"
        case memo
    }
}

struct VerifyTransferRequest: Encodable {
    let password: String
    let transactionId: String
}

/// Response chung cho `transfer-to-wallet`/`transfer-to-bank`/`verify-transfer` —
/// BE trả `{...result.data, status}` khi thực thi ngay, hoặc `{pending: true,
/// transactionId}` khi số tiền >= ngưỡng PIN. 2 shape loại trừ nhau nên decode
/// optional cả 2 phía thay vì tách 2 struct.
struct TransferResult: Decodable {
    let pending: Bool?
    let transactionId: String?
    let status: String?
    let transAmount: Int64?
    let feeAmount: Int64?
    /// `trans_id` tự sinh của app, dùng làm txId khi gọi `PayLinkService.consume`.
    let transId: String?
    let bkTransId: String?

    enum CodingKeys: String, CodingKey {
        case pending
        case transactionId
        case status
        case transAmount = "trans_amount"
        case feeAmount = "fee_amount"
        case transId = "trans_id"
        case bkTransId = "bk_trans_id"
    }

    var isPending: Bool { pending == true }
    var isSuccess: Bool { status == "SUCCESS" }
}
