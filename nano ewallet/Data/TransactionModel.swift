//
//  TransactionModel.swift
//  nano ewallet
//

import Foundation

/// Model giao dịch — tương ứng TransactionEntity.kt phía Android.
struct TransactionModel: Identifiable, Codable {
    let id: String
    let amount: Decimal
    let createdAt: Date
    let note: String?
}
