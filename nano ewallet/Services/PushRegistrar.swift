//
//  PushRegistrar.swift
//  nano ewallet
//

import UIKit
import UserNotifications
import FirebaseMessaging

/// Đăng ký push notification — tương ứng PushRegistrar.kt phía Android.
///
/// Luồng: xin quyền -> registerForRemoteNotifications -> APNs token (AppDelegate giao cho
/// Firebase) -> Firebase cấp FCM token -> `onFcmTokenRefresh` gửi lên BE.
final class PushRegistrar {
    static let shared = PushRegistrar()
    private init() {}

    /// Xin quyền hiện thông báo rồi đăng ký nhận remote notification.
    func registerForPushNotifications(application: UIApplication) {
        // Android bỏ qua nếu user tắt push trong Settings — mirror hành vi đó.
        guard NotificationPrefs.isEnabled else { return }

        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    print("[Push] Xin quyền lỗi: \(error.localizedDescription)")
                }
                guard granted else { return }
                Task { @MainActor in
                    application.registerForRemoteNotifications()
                }
            }
    }

    /// Firebase cấp/refresh FCM token -> đăng ký với BE.
    /// Fire-and-forget giống Android (lỗi chỉ log, không chặn UI).
    func onFcmTokenRefresh(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        Task {
            // TODO (Phase 2): POST devices/register
            //   body: { token, deviceId, platform: "IOS" }
            //   deviceId lấy từ KeychainStore (UUID sinh 1 lần, giữ nguyên qua các lần cài lại)
            //   Android gửi platform "ANDROID" — iOS phải gửi "IOS".
        }
    }

    /// Gọi khi logout hoặc user tắt push — mirror DeviceTokenApi.unregister.
    func unregister() async {
        // TODO (Phase 2): POST devices/unregister với body { deviceId }
    }

    /// Lấy FCM token hiện tại (dùng khi bật lại push trong Settings).
    func syncCurrentToken() {
        guard NotificationPrefs.isEnabled else { return }
        Messaging.messaging().token { [weak self] token, error in
            if let error {
                print("[Push] Lấy FCM token lỗi: \(error.localizedDescription)")
                return
            }
            self?.onFcmTokenRefresh(token)
        }
    }
}
