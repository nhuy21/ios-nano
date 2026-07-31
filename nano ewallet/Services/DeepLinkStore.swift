//
//  DeepLinkStore.swift
//  nano ewallet
//

import Foundation
import Combine

/// Cầu nối deep link (Intent/URL/push) -> UI, tương ứng DeepLinkStore.kt phía Android.
///
/// Cách dùng: nơi phát (AppDelegate) gọi `request*`/`handle`, phía UI quan sát rồi gọi
/// `consume*` để lấy 1 lần rồi tự xoá — tránh điều hướng lặp khi View recompose.
@MainActor
final class DeepLinkStore: ObservableObject {
    static let shared = DeepLinkStore()
    private init() {}

    /// Pay link đang chờ (Universal Link https://nano.casso.dev/pay hoặc nanowallet://pay).
    @Published private(set) var pendingPayToken: String?

    /// Mở màn hội thoại xin tiền với 1 người (từ push MONEY_REQUEST).
    @Published private(set) var pendingConversationBkUsername: String?

    // MARK: - Phát

    /// Nhận URL từ Universal Link / custom scheme. Trả false nếu không phải link của app.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard isPayLink(url) else { return false }
        // BE dùng query `req_token` (xem MainActivity.handleDeepLink bên Android).
        guard let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "req_token" })?.value,
              !token.isEmpty else { return false }
        pendingPayToken = token
        return true
    }

    func openConversation(bkUsername: String) {
        pendingConversationBkUsername = bkUsername
    }

    // MARK: - Tiêu thụ (lấy 1 lần)

    func consumePayToken() -> String? {
        defer { pendingPayToken = nil }
        return pendingPayToken
    }

    func consumeConversation() -> String? {
        defer { pendingConversationBkUsername = nil }
        return pendingConversationBkUsername
    }

    // MARK: - Private

    private func isPayLink(_ url: URL) -> Bool {
        if url.scheme == "nanowallet", url.host == "pay" { return true }
        if url.scheme == "https", url.host == "nano.casso.dev", url.path.hasPrefix("/pay") { return true }
        return false
    }
}
