//
//  TransactionRepository.swift
//  nano ewallet
//

import Foundation

/// Truy xuất/lưu lịch sử giao dịch — tương ứng TransactionRepository.kt phía Android.
final class TransactionRepository {
    static let shared = TransactionRepository()
    private init() {}

    func fetchTransactions() async throws -> [TransactionModel] {
        // TODO: gọi API be/src/modules/transaction, giữ đúng contract response
        []
    }
}
