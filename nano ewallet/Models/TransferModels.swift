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

    /// BẮT BUỘC map snake_case: BE bật `forbidNonWhitelisted` nên field sai tên không
    /// bị bỏ qua mà trả lỗi "property <tên> should not exist". Thiếu phần này thì tra
    /// cứu tên chủ ví luôn thất bại dù username đúng.
    enum CodingKeys: String, CodingKey {
        case benUsername = "ben_username"
        case accNo = "acc_no"
        case bankNo = "bank_no"
        case accType = "acc_type"
    }
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

/// `POST wallet/withdraw` — rút về TK ngân hàng. BE không bắt buộc khớp với
/// wallets.accNo/bankNo đã liên kết (chỉ là quy ước phía app) — không có `memo`.
struct WithdrawRequest: Encodable {
    let idempotencyKey: String
    let accNo: String
    let accType: Int
    let bankNo: String
    let transAmount: Int

    enum CodingKeys: String, CodingKey {
        case idempotencyKey
        case accNo = "acc_no"
        case accType = "acc_type"
        case bankNo = "bank_no"
        case transAmount = "trans_amount"
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

    /// BE trả nguyên `result.data` của Bảo Kim (xem `wallet.service.ts`: `{...result.data,
    /// status}`), mà Bảo Kim KHÔNG nhất quán kiểu: `bk_trans_id`/`trans_id`/số tiền có
    /// lúc là chuỗi, có lúc là số. Decode chặt theo 1 kiểu sẽ ném lỗi và mất luôn màn
    /// "chuyển tiền thành công" dù tiền đã chuyển xong — nên phải nhận cả hai dạng.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pending = try container.decodeIfPresent(Bool.self, forKey: .pending)
        transactionId = Self.flexibleString(container, forKey: .transactionId)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        transAmount = Self.flexibleInt(container, forKey: .transAmount)
        feeAmount = Self.flexibleInt(container, forKey: .feeAmount)
        transId = Self.flexibleString(container, forKey: .transId)
        bkTransId = Self.flexibleString(container, forKey: .bkTransId)
    }

    /// Nhận String hoặc số -> String. Kiểu lạ/thiếu thì `nil`.
    ///
    /// Phải bóc HAI tầng: `decodeIfPresent` trả `T?`, `try?` bọc thêm thành `T??` — bóc
    /// một tầng thì biến vẫn là optional và không truyền được vào `String(_:)`/`Int64(_:)`.
    private static func flexibleString(
        _ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
    ) -> String? {
        if let raw = try? container.decodeIfPresent(String.self, forKey: key), let text = raw {
            return text
        }
        if let raw = try? container.decodeIfPresent(Int64.self, forKey: key), let number = raw {
            return String(number)
        }
        if let raw = try? container.decodeIfPresent(Double.self, forKey: key), let number = raw,
           let clamped = Self.safeInt64(number) {
            return String(clamped)
        }
        return nil
    }

    /// Nhận số hoặc chuỗi số -> Int64. Kiểu lạ/thiếu thì `nil`.
    private static func flexibleInt(
        _ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
    ) -> Int64? {
        if let raw = try? container.decodeIfPresent(Int64.self, forKey: key), let number = raw {
            return number
        }
        if let raw = try? container.decodeIfPresent(String.self, forKey: key), let text = raw {
            return Int64(text)
        }
        if let raw = try? container.decodeIfPresent(Double.self, forKey: key), let number = raw {
            return Self.safeInt64(number)
        }
        return nil
    }

    /// `Int64(Double)` TRAP với NaN/vô cực/ngoài biên — trả `nil` thay vì làm sập app.
    private static func safeInt64(_ value: Double) -> Int64? {
        guard value.isFinite, value >= -9.2e18, value <= 9.2e18 else { return nil }
        return Int64(value)
    }

    var isPending: Bool { pending == true }
    var isSuccess: Bool { status == "SUCCESS" }
}
