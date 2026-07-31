//
//  NotificationPrefs.swift
//  nano ewallet
//

import Foundation

/// Lưu tuỳ chọn thông báo của user — tương ứng NotificationPrefs.kt phía Android.
enum NotificationPrefs {
    private static let defaults = UserDefaults.standard
    private static let enabledKey = "notification_enabled"

    static var isEnabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }
}
