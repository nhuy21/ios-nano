//
//  SceneDelegate.swift
//  nano ewallet
//
//  App khai UIApplicationSceneManifest (scene-based) — Quick Action (long-press icon) PHẢI
//  đi qua UIWindowSceneDelegate, KHÔNG rơi về UIApplicationDelegate.performActionFor/
//  launchOptions[.shortcutItem] (2 chỗ đó là code chết khi app đã scene-based, xem
//  AppDelegate.swift). Đăng ký class này qua `application(_:configurationForConnecting:)`.
//

import UIKit

final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    /// App bị TERMINATE, mở lại bằng Quick Action — shortcut item nằm ở
    /// `connectionOptions.shortcutItem`, KHÔNG phải `launchOptions` của UIApplicationDelegate.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            DeepLinkStore.shared.handleShortcut(type: shortcutItem.type)
        }
    }

    /// App ĐANG SỐNG (foreground/background) — mirror MainActivity.handleDeepLink nhánh
    /// App Shortcut, nhưng ở tầng scene delegate đúng chỗ thay vì app delegate.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let handled = DeepLinkStore.shared.handleShortcut(type: shortcutItem.type)
        completionHandler(handled)
    }
}
