//
//  PushRegistrar.swift
//  nano ewallet
//

import UIKit
import UserNotifications

/// Đăng ký push notification — tương ứng PushRegistrar.kt phía Android.
final class PushRegistrar {
    static let shared = PushRegistrar()
    private init() {}

    func registerForPushNotifications(application: UIApplication) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }

    func onDeviceTokenReceived(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        // TODO: gửi token lên BE giống PushRegistrar.kt (hoặc gán cho Firebase Messaging APNs token khi thêm SDK)
        _ = token
    }
}
