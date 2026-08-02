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
    }
}
