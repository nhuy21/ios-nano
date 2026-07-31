//
//  TransactionService.swift
//  nano ewallet
//
//  Mirror TransactionApi.kt — GET transactions (phân trang cursor theo createdAt)
//  và GET transactions/:id.
//

import Foundation

enum TransactionService {
    /// `GET transactions?limit=&type=&after=&before=&q=&dateFrom=&dateTo=`
    static func list(_ query: TransactionQuery = TransactionQuery()) async throws -> TransactionPage {
        try await APIClient.shared.request(
            .get, "transactions", query: query.asQueryDict(), auth: true, as: TransactionPage.self
        )
    }

    /// `GET transactions/:id`
    static func getById(_ id: String) async throws -> TransactionEntity {
        try await APIClient.shared.request(.get, "transactions/\(id)", auth: true, as: TransactionEntity.self)
    }
}
