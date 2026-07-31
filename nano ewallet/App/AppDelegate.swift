//
//  AppDelegate.swift
//  nano ewallet
//

import UIKit
import UserNotifications

/// Tương ứng phần khởi tạo trong MainActivity.kt + MyFirebaseMessagingService.kt phía Android.
/// TODO: thêm Firebase package (File > Add Package Dependencies... > firebase-ios-sdk)
/// rồi gọi FirebaseApp.configure() + gán MessagingDelegate ở đây.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
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

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushRegistrar.shared.onDeviceTokenReceived(deviceToken)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
