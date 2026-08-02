//
//  NotificationService.swift
//  nano ewallet
//
//  Mirror NotificationApi.kt. Cần đăng nhập (Bearer accessToken).
//

import Foundation

enum NotificationService {
    /// `GET notifications` — mới nhất trước.
    static func list(limit: Int = 30, before: String? = nil) async throws -> NotificationPage {
        var query = ["limit": String(limit)]
        if let before { query["before"] = before }
        return try await APIClient.shared.request(
            .get, "notifications", query: query, auth: true, as: NotificationPage.self
        )
    }

    /// `PATCH notifications/{id}/read` — best-effort, nuốt lỗi như bản Android:
    /// đánh dấu đã đọc hỏng thì cũng không nên chặn thao tác của người dùng.
    static func markRead(id: String) async {
        try? await APIClient.shared.requestVoid(.patch, "notifications/\(id)/read", auth: true)
    }

    /// `POST notifications/read-all` — best-effort.
    static func markAllRead() async {
        try? await APIClient.shared.requestVoid(.post, "notifications/read-all", auth: true)
    }
}
