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

    // Deep link (Universal Link + nanowallet://) KHÔNG xử lý ở đây. App dùng
    // WindowGroup nên là scene-based, UIKit không gọi `application(_:open:options:)`
    // hay `application(_:continue:_:)` nữa — đặt ở đây là code chết. Xem
    // `.onOpenURL` / `.onContinueUserActivity` trong nano_ewalletApp.swift.

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

    /// App bị ĐÁNH THỨC ở nền để xử lý push (BE gửi `content-available: 1`) — áp số dư và
    /// giao dịch mới vào cache NGAY, để lúc user mở app là đã tươi, không phải đợi vòng
    /// refresh/poll đầu tiên.
    ///
    /// `willPresent`/`didReceive response` không thay được hàm này: cái đầu chỉ chạy khi
    /// app đang mở, cái sau chỉ chạy khi user chủ động bấm thông báo.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let type = userInfo["type"] as? String, type == "TRANSACTION" else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            Self.applyTransactionPush(userInfo)
            completionHandler(.newData)
        }
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
        // Mirror MyFirebaseMessagingService.onMessageReceived: push tới lúc app đang mở
        // thì đồng bộ lại hộp thư + số dư ngay, không đợi nhịp poll 8s.
        let content = notification.request.content
        let info = content.userInfo

        Task { @MainActor in
            // "Loa báo nhận tiền" — đọc trước khi gọi API để phát ngay, không chờ mạng.
            if NotificationPrefs.speakOnReceiveEnabled,
               let amount = Self.receivedAmount(from: info, title: content.title, body: content.body) {
                TtsAnnouncer.shared.announceReceived(amount: amount)
            }

            guard AuthStore.shared.accessToken != nil else { return }
            await NotificationStore.shared.refresh()

            if info["type"] as? String == "TRANSACTION", Self.string(info["txId"]) != nil {
                Self.applyTransactionPush(info)
            } else {
                // Push không mang payload giao dịch (vd yêu cầu xin tiền được chấp nhận —
                // tiền vẫn chuyển thật) -> phải làm mới CẢ số dư lẫn danh sách giao dịch.
                await WalletStore.shared.refresh(force: true)
                await TransactionStore.shared.refreshRecent()
            }
        }
        // Chốt chặn phía client khi user đã tắt "Thông báo" trong app: gỡ token trên BE
        // là best-effort (`try?`), mất mạng thì token vẫn còn và push vẫn tới. Không
        // chặn ở đây thì công tắc đang tắt mà banner vẫn hiện + chuông vẫn kêu.
        // Mirror nhánh `if (NotificationPrefs.isPushEnabled())` bên Android.
        guard NotificationPrefs.isEnabled else {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound, .badge])
    }

    /// Áp payload giao dịch THẲNG vào UI, không gọi lại API — mirror
    /// `applyTransactionPush` bên Android. Đi đường API thì số dư mới hiện chậm hơn đúng
    /// một vòng mạng, mất ý nghĩa "realtime" của push.
    ///
    /// `id` dùng luôn `txId` của server nên lần refresh sau KHÔNG tạo bản ghi trùng.
    @MainActor
    private static func applyTransactionPush(_ info: [AnyHashable: Any]) {
        // Thiếu balanceAfter thì không đoán — gọi API lấy số dư đúng.
        if let balanceAfter = int64(info["balanceAfter"]) {
            WalletStore.shared.setBalance(balanceAfter)
        } else {
            Task { await WalletStore.shared.refresh(force: true) }
        }

        guard let txId = string(info["txId"]) else { return }
        let direction = string(info["direction"])
        let txType = string(info["txType"]) ?? (direction == "IN" ? "TRANSFER_IN" : "TRANSFER_OUT")

        TransactionStore.shared.prepend(
            TransactionEntity(
                id: txId,
                type: txType,
                amount: String(int64(info["amount"]) ?? 0),
                fee: "0",
                description: string(info["description"]),
                cachedBalanceAfter: int64(info["balanceAfter"]).map(String.init),
                bkTransId: nil,
                benBankNo: string(info["benBankNo"]),
                benAccNo: nil,
                benAccName: string(info["benAccName"]),
                benBankName: string(info["benBankName"]),
                status: "SUCCESS",
                createdAt: string(info["createdAt"]) ?? ISO8601DateFormatter().string(from: Date())
            )
        )
    }

    /// Payload FCM về dạng String, nhưng APNs có thể gửi số thật — nhận cả hai.
    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let text = value as? String { return Int64(text) }
        if let number = value as? NSNumber { return number.int64Value }
        return nil
    }

    /// Số tiền (đồng) nếu đây là thông báo TIỀN VÀO ví, ngược lại `nil`.
    /// Mirror `receivedAmountOrNull` bên Android:
    ///  - Ưu tiên payload: `direction == "IN"` + `amount` (backend bản mới).
    ///  - Fallback: tiêu đề là "Nhận tiền"/"Nạp tiền" rồi bóc số từ body (backend bản cũ).
    ///
    /// Payload FCM về dưới dạng String nên `amount` phải parse từ chuỗi, không ép kiểu số.
    private static func receivedAmount(
        from info: [AnyHashable: Any], title: String, body: String
    ) -> Int64? {
        if let direction = info["direction"] as? String {
            guard direction == "IN" else { return nil }
            guard let raw = info["amount"] else { return nil }
            if let text = raw as? String { return Int64(text) }
            if let number = raw as? NSNumber { return number.int64Value }
            return nil
        }

        // Chỉ đọc khi tiêu đề là nhận/nạp tiền — nếu không sẽ đọc cả giao dịch CHI ra.
        let lowered = title.lowercased()
        guard lowered.contains("nhận tiền") || lowered.contains("nạp tiền") else { return nil }

        // Bóc "50.000đ" trong body -> 50000.
        guard let range = body.range(of: "[0-9][0-9.]*\\s*đ", options: .regularExpression) else {
            return nil
        }
        let digits = body[range].filter(\.isNumber)
        return Int64(digits)
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
