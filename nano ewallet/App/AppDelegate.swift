//
//  AppDelegate.swift
//  nano ewallet
//

import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

/// Tương ứng phần khởi tạo trong MainActivity.kt + MyFirebaseMessagingService.kt phía Android.
///
/// YÊU CẦU BUILD: cần thêm package firebase-ios-sdk trong Xcode
/// (File > Add Package Dependencies... > https://github.com/firebase/firebase-ios-sdk),
/// chọn product `FirebaseMessaging`. Chưa thêm thì file này không compile.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Đọc GoogleService-Info.plist (bundle id vn.casso.nano, project nanocasso26)
        FirebaseApp.configure()

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        PushRegistrar.shared.registerForPushNotifications(application: application)
        return true
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        // Universal Links: https://nano.casso.dev/pay?... -> mở app thẳng
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return false }
        return DeepLinkStore.shared.handle(url: url)
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        // Custom scheme dự phòng: nanowallet://pay?...
        return DeepLinkStore.shared.handle(url: url)
    }

    /// APNs token -> giao cho Firebase để nó cấp FCM token tương ứng.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Không chặn app — chỉ là push không dùng được (vd Simulator, thiếu capability).
        print("[Push] Đăng ký remote notification thất bại: \(error.localizedDescription)")
    }
}

// MARK: - FCM token

extension AppDelegate: MessagingDelegate {
    /// Gọi khi Firebase cấp token mới hoặc token bị refresh — mirror `onNewToken` bên Android.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        PushRegistrar.shared.onFcmTokenRefresh(fcmToken)
    }
}

// MARK: - Hiển thị notification khi app đang mở

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // TODO (Phase 2+): mirror MyFirebaseMessagingService.onMessageReceived — với
        // type == "TRANSACTION" thì áp balanceAfter vào WalletCache + prepend transaction
        // thay vì gọi lại API.
        completionHandler([.banner, .sound, .badge])
    }

    /// User bấm vào notification — mirror phần deep link trong MainActivity.handleDeepLink.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let type = info["type"] as? String,
           type.hasPrefix("MONEY_REQUEST"),
           let other = info["otherBkUsername"] as? String,
           !other.isEmpty {
            DeepLinkStore.shared.openConversation(bkUsername: other)
        }
        completionHandler()
    }
}
