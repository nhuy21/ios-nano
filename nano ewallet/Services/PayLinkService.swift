//
//  PayLinkService.swift
//  nano ewallet
//
//  Mirror PayLinkApi.kt + pay-link.controller.ts (path `pay-links`).
//

import Foundation

enum PayLinkService {
    /// `POST pay-links`
    static func create(_ request: CreatePayLinkRequest) async throws -> CreatePayLinkResult {
        try await APIClient.shared.request(
            .post, "pay-links", body: request, auth: true, as: CreatePayLinkResult.self
        )
    }

    /// `GET pay-links/:reqToken` — resolve khi mở deep link, ném lỗi nếu hết hạn/thu hồi.
    static func resolve(reqToken: String) async throws -> PayLinkInfo {
        try await APIClient.shared.request(
            .get, "pay-links/\(reqToken)", auth: true, as: PayLinkInfo.self
        )
    }

    /// `POST pay-links/:reqToken/consume` — best-effort, gọi sau khi giao dịch chốt SUCCESS.
    /// Không rollback nếu lỗi vì tiền đã chuyển xong (mirror `runCatching` bên Android).
    static func consume(reqToken: String, txId: String?) async {
        struct Body: Encodable { let txId: String? }
        try? await APIClient.shared.requestVoid(
            .post, "pay-links/\(reqToken)/consume", body: Body(txId: txId), auth: true
        )
    }
}
