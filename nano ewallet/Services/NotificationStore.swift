//
//  NotificationStore.swift
//  nano ewallet
//
//  Mirror NotificationStore.kt — nguồn thông báo dùng chung toàn app. Giữ số chưa
//  đọc + danh sách để badge chuông và màn Thông báo luôn khớp nhau, đồng thời bắn
//  `newNotification` khi có thông báo MỚI để hiện banner trong app.
//

import Foundation
import Combine
import UserNotifications

@MainActor
final class NotificationStore: ObservableObject {

    static let shared = NotificationStore()
    private init() {}

    @Published private(set) var items: [AppNotification] = []

    /// Đồng bộ luôn badge đỏ trên icon app. Không làm thì badge do BE gửi cứ tăng dần
    /// và KHÔNG BAO GIỜ về 0 dù user đã đọc hết trong app — app đóng lại vẫn thấy số đỏ.
    @Published private(set) var unreadCount = 0 {
        didSet {
            guard unreadCount != oldValue else { return }
            Task { try? await UNUserNotificationCenter.current().setBadgeCount(unreadCount) }
        }
    }

    /// Thông báo vừa đến (chưa từng thấy) — banner trong app lắng nghe cái này.
    /// Không dùng `@Published` giá trị thường vì banner cần biết từng LẦN đến, kể cả
    /// khi cùng một thông báo được set lại.
    let newNotification = PassthroughSubject<AppNotification, Never>()

    private var knownIds: Set<String> = []
    /// Lần refresh đầu chỉ "gieo" hiện trạng, KHÔNG báo — nếu không thì mở app lên là
    /// banner bắn thông báo cũ nhất vừa tải về.
    private var seeded = false

    /// Làm mới từ server. Best-effort — lỗi mạng trả `false` và giữ nguyên state cũ.
    @discardableResult
    func refresh() async -> Bool {
        guard let page = try? await NotificationService.list(limit: 50) else { return false }
        items = page.items
        unreadCount = page.unreadCount

        let ids = Set(page.items.map(\.id))
        if seeded {
            // items sắp mới→cũ nên phần tử đầu chưa từng thấy chính là cái mới nhất.
            if let fresh = page.items.first(where: { !knownIds.contains($0.id) }) {
                newNotification.send(fresh)
            }
        } else {
            seeded = true
        }
        knownIds = ids
        return true
    }

    /// Đánh dấu 1 thông báo đã đọc — cập nhật local NGAY rồi mới gọi API, để danh sách
    /// phản hồi tức thì thay vì chờ round-trip.
    func markRead(id: String) async {
        if let index = items.firstIndex(where: { $0.id == id }), !items[index].isRead {
            items[index].isRead = true
            unreadCount = max(unreadCount - 1, 0)
        }
        await NotificationService.markRead(id: id)
    }

    func markAllRead() async {
        for index in items.indices where !items[index].isRead {
            items[index].isRead = true
        }
        unreadCount = 0
        await NotificationService.markAllRead()
    }

    /// Gọi khi logout — xoá sạch để tài khoản sau không thấy thông báo của tài khoản trước.
    func clear() {
        knownIds = []
        seeded = false
        unreadCount = 0
        items = []
    }
}
