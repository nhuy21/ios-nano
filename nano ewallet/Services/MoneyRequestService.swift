//
//  MoneyRequestService.swift
//  nano ewallet
//
//  Mirror MoneyRequestApi.kt + money-request.controller.ts (path `money-requests`).
//

import Foundation

enum MoneyRequestService {
    /// `GET money-requests/conversations/:otherBkUsername`
    static func conversation(otherBkUsername: String) async throws -> MoneyRequestConversation {
        try await APIClient.shared.request(
            .get, "money-requests/conversations/\(otherBkUsername)", auth: true, as: MoneyRequestConversation.self
        )
    }

    /// `POST money-requests`
    static func create(payerBkUsername: String, amount: Int, note: String?) async throws -> MoneyRequestSimpleResult {
        try await APIClient.shared.request(
            .post, "money-requests",
            body: CreateMoneyRequestRequest(payerBkUsername: payerBkUsername, amount: amount, note: note),
            auth: true, as: MoneyRequestSimpleResult.self
        )
    }

    /// `POST money-requests/:id/approve` — chỉ đánh dấu APPROVED, KHÔNG chuyển tiền.
    /// App phải tự gọi tiếp `TransferService.transferToWallet` tới `requesterBkUsername`.
    static func approve(id: String) async throws -> MoneyRequestApproveResult {
        try await APIClient.shared.request(
            .post, "money-requests/\(id)/approve", auth: true, as: MoneyRequestApproveResult.self
        )
    }

    /// `POST money-requests/:id/decline`
    static func decline(id: String) async throws {
        try await APIClient.shared.requestVoid(.post, "money-requests/\(id)/decline", auth: true)
    }

    /// `POST money-requests/:id/cancel`
    static func cancel(id: String) async throws {
        try await APIClient.shared.requestVoid(.post, "money-requests/\(id)/cancel", auth: true)
    }
}
