//
//  DeepLinkStore.swift
//  nano ewallet
//

import Foundation
import Combine

/// Lưu & phát deep link đang chờ xử lý — tương ứng DeepLinkStore.kt phía Android.
/// Hỗ trợ Universal Links (https://nano.casso.dev/pay) và custom scheme (nanowallet://pay).
final class DeepLinkStore: ObservableObject {
    static let shared = DeepLinkStore()
    private init() {}

    @Published var pendingURL: URL?

    @discardableResult
    func handle(url: URL) -> Bool {
        guard isSupported(url) else { return false }
        pendingURL = url
        return true
    }

    private func isSupported(_ url: URL) -> Bool {
        if url.scheme == "nanowallet", url.host == "pay" { return true }
        if url.scheme == "https", url.host == "nano.casso.dev", url.path.hasPrefix("/pay") { return true }
        return false
    }
}
