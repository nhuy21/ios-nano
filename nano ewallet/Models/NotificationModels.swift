//
//  NotificationModels.swift
//  nano ewallet
//
//  Mirror NotificationApi.kt — hộp thư thông báo của user
//  (be/src/modules/notification).
//

import Foundation

/// Một thông báo trong hộp thư. Đặt tên `AppNotification` để không đụng
/// `Foundation.Notification` (NotificationCenter).
struct AppNotification: Decodable, Identifiable, Hashable {
    let id: String
    /// "TRANSACTION" | "KYC" | "SYSTEM"
    let type: String
    let title: String
    let body: String
    var isRead: Bool
    /// ISO-8601
    let createdAt: String
    /// Tham chiếu nguồn phát sinh để bấm-mở đúng chi tiết. `nil` = thông báo
    /// cũ/không có hành động.
    let data: NotificationRef?
}

/// Payload tham chiếu (cột `notifications.data`). Field nào có tuỳ theo `type`:
///  - TRANSACTION:       type + txId
///  - MONEY_REQUEST_NEW: type + requestId + otherBkUsername (bấm → sheet Đồng ý/Từ chối)
///  - MONEY_REQUEST_*:   type + requestId + otherBkUsername (mở cuộc thoại)
struct NotificationRef: Decodable, Hashable {
    let type: String?
    let txId: String?
    let requestId: String?
    let otherBkUsername: String?
}

/// `GET notifications` — danh sách mới nhất trước + số chưa đọc.
struct NotificationPage: Decodable {
    let items: [AppNotification]
    let hasMore: Bool
    let unreadCount: Int
}
