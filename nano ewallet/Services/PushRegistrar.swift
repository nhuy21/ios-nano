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
        // User đã tắt thông báo -> KHÔNG đăng ký lại. Thiếu guard này thì mỗi lần
        // Firebase refresh token (hoặc chỉ cần mở lại app) là device tự đăng ký lại lên
        // BE, push quay về dù công tắc vẫn đang tắt. Mirror `onNewToken` bên Android.
        guard NotificationPrefs.isEnabled else { return }
        Task { @MainActor in
            // Chưa đăng nhập thì chưa có ví để gắn token — gọi lên sẽ nhận 401 và chỉ
            // tổ làm nhiễu log. Token sẽ được đăng ký lại sau khi login qua
            // `syncCurrentToken()`. Mirror guard `getAccessToken() == null` bên Android.
            guard AuthStore.shared.accessToken != nil else { return }
            let deviceId = AuthStore.shared.getOrCreateDeviceId()
            let body = RegisterDeviceRequest(token: token, deviceId: deviceId)
            do {
                try await APIClient.shared.requestVoid(.post, "devices/register", body: body, auth: true)
            } catch APIError.unauthenticated {
                // Phiên hết giữa chừng: hoặc user đăng xuất xen vào, hoặc refresh token đã
                // hết hạn (hay gặp khi cài đè build mới sau thời gian dài không mở app).
                //
                // KHÔNG tự sửa gì ở đây vì hai trường hợp đó khác hẳn nhau về hậu quả:
                //  - Phiên hết thật -> app tự đưa về Login, đăng nhập lại là `syncCurrentToken`
                //    đăng ký lại token. Không sao.
                //  - Phiên VẪN CÒN mà vẫn lỗi -> máy này sẽ KHÔNG nhận được push nào.
                // Log kèm trạng thái phiên để lần sau nhìn là phân biệt được ngay, thay vì
                // nuốt lỗi rồi mất luôn dấu vết.
                let stillSignedIn = AuthStore.shared.accessToken != nil
                print(
                    "[Push] Đăng ký device token lỗi: unauthenticated "
                        + "(phiên \(stillSignedIn ? "VẪN CÒN — cần xem lại" : "đã hết, sẽ đăng ký lại sau khi đăng nhập"))"
                )
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

    /// Kết quả bật push từ màn Cài đặt.
    enum EnableResult {
        case enabled
        /// User đã từ chối quyền ở cấp hệ thống — app không tự xin lại được, phải vào
        /// Cài đặt iOS. Đăng ký token lúc này vô nghĩa vì iOS chặn hiển thị.
        case deniedInSystemSettings
    }

    /// Bật push từ toggle trong Cài đặt. Kiểm tra quyền TRƯỚC khi đăng ký token — nếu
    /// chỉ gọi `syncCurrentToken()` như trước thì token vẫn lên BE, toggle vẫn xanh,
    /// nhưng iOS chặn hiển thị nên người dùng không nhận được thông báo nào.
    @MainActor
    func enablePush() async -> EnableResult {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus

        switch status {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return .deniedInSystemSettings }
        case .denied:
            return .deniedInSystemSettings
        default:
            break
        }

        NotificationPrefs.isEnabled = true
        UIApplication.shared.registerForRemoteNotifications()
        syncCurrentToken()
        return .enabled
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
