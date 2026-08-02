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

    /// Mở app hàng ngày (không có deep link) -> mặc định vào màn quét QR.
    ///
    /// Đặt CỜ thay vì điều hướng thẳng lúc bootstrap xong: deep link có thể tới sau vài
    /// nhịp, điều hướng ngay sẽ đua nhau và ra kết quả khác nhau tuỳ máy nhanh/chậm.
    /// Nơi quan sát chỉ mở QR khi chắc chắn không còn deep link nào chờ.
    @Published private(set) var pendingDefaultQr = false

    /// Còn deep link nào đang chờ xử lý không — dùng để QR không đè lên link nhận tiền.
    var hasPendingDeepLink: Bool {
        pendingPayToken != nil || pendingConversationBkUsername != nil
    }

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

    func requestDefaultQr() {
        pendingDefaultQr = true
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

    @discardableResult
    func consumeDefaultQr() -> Bool {
        defer { pendingDefaultQr = false }
        return pendingDefaultQr
    }

    // MARK: - Private

    private func isPayLink(_ url: URL) -> Bool {
        if url.scheme == "nanowallet", url.host == "pay" { return true }
        if url.scheme == "https", url.host == "nano.casso.dev", url.path.hasPrefix("/pay") { return true }
        return false
    }
}
