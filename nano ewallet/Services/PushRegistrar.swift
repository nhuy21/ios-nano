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
    /// Fire-and-forget giống Android (lỗi chỉ log, không chặn UI, best-effort).
    func onFcmTokenRefresh(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        Task { @MainActor in
            let deviceId = AuthStore.shared.getOrCreateDeviceId()
            let body = RegisterDeviceRequest(token: token, deviceId: deviceId)
            do {
                try await APIClient.shared.requestVoid(.post, "devices/register", body: body, auth: true)
            } catch {
                print("[Push] Đăng ký device token lỗi: \(error)")
            }
        }
    }

    /// Gọi khi logout hoặc user tắt push — mirror DeviceTokenApi.unregister. Best-effort.
    func unregister() async {
        let deviceId = AuthStore.shared.getOrCreateDeviceId()
        let body = UnregisterDeviceRequest(deviceId: deviceId)
        try? await APIClient.shared.requestVoid(.post, "devices/unregister", body: body, auth: true)
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
