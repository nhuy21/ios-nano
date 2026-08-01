//
//  TransactionModels.swift
//  nano ewallet
//
//  DTO mirror be/src/modules/transaction. amount/fee/cachedBalanceAfter là String
//  ở BE (BIGINT) — parse sang Int64 qua computed property, không decode thẳng Int.
//
//  BE dùng SELECT * nên response thật có nhiều field hơn (userId, walletId,
//  requireFaceVerify...) — struct chỉ khai field cần dùng, Codable tự bỏ qua
//  phần còn lại (giống Gson bên Android).
//

import Foundation

struct TransactionPage: Decodable {
    let items: [TransactionEntity]
    let hasMore: Bool
}

struct TransactionEntity: Decodable, Identifiable {
    let id: String
    let type: String
    let amount: String
    let fee: String
    let description: String?
    let cachedBalanceAfter: String?
    let bkTransId: String?
    let benBankNo: String?
    let benAccNo: String?
    let benAccName: String?
    let benBankName: String?
    let status: String
    /// ISO-8601 dạng String — parse sang Date qua `createdAtDate` khi cần hiển thị,
    /// đồng thời dùng CHÍNH chuỗi này làm cursor phân trang (before/after).
    let createdAt: String

    var amountValue: Int64 { Int64(amount) ?? 0 }
    var feeValue: Int64 { Int64(fee) ?? 0 }
    var cachedBalanceAfterValue: Int64? { cachedBalanceAfter.flatMap { Int64($0) } }

    var kind: TransactionType? { TransactionType(rawValue: type) }
    var statusKind: TransactionStatus? { TransactionStatus(rawValue: status) }

    /// Tiền vào ví (nhận tiền/nạp tiền/hoàn tiền) hay tiền ra.
    var isIncome: Bool {
        switch kind {
        case .transferIn, .topUp, .refund: return true
        case .transferOut, .withdraw, .none: return false
        }
    }
}

enum TransactionType: String {
    case transferOut = "TRANSFER_OUT"
    case transferIn = "TRANSFER_IN"
    case topUp = "TOP_UP"
    case withdraw = "WITHDRAW"
    case refund = "REFUND"
}

enum TransactionStatus: String {
    case pending = "PENDING"
    case processing = "PROCESSING"
    case success = "SUCCESS"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
}

/// Query GET transactions — mirror be/src/modules/transaction/dto/transaction.dto.ts.
nonisolated struct TransactionQuery {
    var limit: Int = 20
    var type: String = "ALL" // "ALL" | "IN" | "OUT"
    var after: String?
    var before: String?
    var q: String?
    var dateFrom: String?
    var dateTo: String?

    func asQueryDict() -> [String: String] {
        var dict: [String: String] = ["limit": "\(limit)", "type": type]
        if let after { dict["after"] = after }
        if let before { dict["before"] = before }
        if let q { dict["q"] = q }
        if let dateFrom { dict["dateFrom"] = dateFrom }
        if let dateTo { dict["dateTo"] = dateTo }
        return dict
    }
}
