//
//  nano_ewalletApp.swift
//  nano ewallet
//
//  Created by Le Tran Nhu Y on 30/7/26.
//

import SwiftUI

@main
struct nano_ewalletApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            // `ZStack` thay cho `.overlay { PrivacyScreenOverlay() }`: `.overlay` lập một
            // khung layout chốt theo safe area, khiến MỌI nền của màn bên trong (dù đã
            // `ignoresSafeArea`) chỉ giãn tới mép safe area của khung đó — hở dải trắng ở
            // status bar trên TOÀN app. Màn quét QR không dính lỗi vì nó mở bằng
            // `.fullScreenCover`, tức context trình bày riêng, không nằm trong khung này.
            ZStack {
                // Thiết bị jailbreak/đang bị gỡ lỗi thì chặn hẳn, không vào được chức năng
                // nào — xem SecurityGate trong DeviceSecurityCheck.swift.
                SecurityGate {
                    NavGraph()
                        // PHẢI bắt deep link ở ĐÂY, không phải trong AppDelegate: app dùng
                        // WindowGroup (scene-based) nên UIKit KHÔNG gọi
                        // `application(_:open:options:)` và `application(_:continue:_:)` nữa.
                        // Đặt nhầm chỗ thì link nhận tiền mở app lên rồi đứng im ở Trang chủ.

                        // Custom scheme: nanowallet://pay?...
                        .onOpenURL { url in
                            _ = DeepLinkStore.shared.handle(url: url)
                        }
                        // Universal Link: https://nano.casso.dev/pay?...
                        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                            guard let url = activity.webpageURL else { return }
                            _ = DeepLinkStore.shared.handle(url: url)
                        }
                }

                // Banner chờ tiền về sau "Nạp ví nhanh". Đặt ở gốc để hiện xuyên suốt mọi
                // màn — người dùng quay lại từ app ngân hàng có thể đang đứng ở bất kỳ đâu.
                TopUpWatcher()

                // Che số dư/giao dịch khỏi thẻ preview App Switcher — xem PrivacyScreenOverlay.
                PrivacyScreenOverlay()
            }
        }
    }
}
