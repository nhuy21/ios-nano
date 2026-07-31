//
//  NotificationPrefs.swift
//  nano ewallet
//

import Foundation

/// Lưu tuỳ chọn thông báo của user — tương ứng NotificationPrefs.kt phía Android.
/// Giữ đúng 2 cờ và giá trị mặc định như Android.
enum NotificationPrefs {
    private static let defaults = UserDefaults.standard

    private static let pushEnabledKey = "push_enabled"
    private static let speakOnReceiveKey = "speak_received_enabled"

    /// Bật/tắt nhận push. Mặc định BẬT (giống Android).
    static var isEnabled: Bool {
        get { defaults.object(forKey: pushEnabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: pushEnabledKey) }
    }

    /// Đọc to số tiền khi nhận được chuyển khoản. Mặc định TẮT (giống Android).
    static var speakOnReceiveEnabled: Bool {
        get { defaults.object(forKey: speakOnReceiveKey) as? Bool ?? false }
        set { defaults.set(newValue, forKey: speakOnReceiveKey) }
    }
}
