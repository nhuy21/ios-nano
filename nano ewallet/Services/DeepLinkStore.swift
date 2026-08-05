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

    /// Home Screen Quick Action "Chuyển tiền tới ví" — mirror Shortcuts.ACTION_WALLET_TRANSFER
    /// bên Android (nhánh không kèm benUsername, tức nhập tay chứ không phải "Chuyển cho X").
    @Published private(set) var pendingWalletTransferShortcut = false

    /// Quick Action "Chuyển khoản ngân hàng".
    @Published private(set) var pendingBankTransferShortcut = false

    /// Siri "chuyển tiền tới ví" ở tầng 2 (limitPin < amount ≤ limitFace) — draft đã điền sẵn
    /// người nhận/số tiền, người dùng tự xem lại rồi xác nhận như luồng thường. Xem
    /// `QuickTransferIntent` và docs/siri-quick-transfer.md mục 1/4.
    @Published private(set) var pendingQuickTransferDraft: WalletTransferDraft?

    /// Còn deep link nào đang chờ xử lý không — dùng để QR không đè lên link nhận tiền.
    var hasPendingDeepLink: Bool {
        pendingPayToken != nil || pendingConversationBkUsername != nil
            || pendingWalletTransferShortcut || pendingBankTransferShortcut
            || pendingQuickTransferDraft != nil
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

    /// Gọi từ `QuickTransferIntent.perform()` khi intent quyết định giao dịch cần
    /// mở app xác nhận (tầng 2, limitPin < amount ≤ limitFace).
    func requestQuickTransfer(draft: WalletTransferDraft) {
        pendingQuickTransferDraft = draft
    }

    /// `UIApplicationShortcutItem.type` của 2 Quick Action khai trong Info.plist
    /// (`UIApplicationShortcutItems`). PHẢI giữ đúng 2 chuỗi này khớp với Info.plist — đây là
    /// XML tĩnh nên không tham chiếu hằng số Swift được, không có cách nào compiler tự phát
    /// hiện lệch. Đổi 1 bên mà quên bên kia thì Quick Action rơi thẳng vào `default: return
    /// false` — không crash, không log, chỉ lặng lẽ không làm gì khi người dùng bấm.
    private enum ShortcutType {
        static let walletTransfer = "vn.casso.nano.shortcut.walletTransfer"
        static let bankTransfer = "vn.casso.nano.shortcut.bankTransfer"
    }

    /// Nhận `UIApplicationShortcutItem.type` từ Quick Action (gọi từ AppDelegate) — trả `false`
    /// nếu type lạ không khớp shortcut nào của app.
    @discardableResult
    func handleShortcut(type: String) -> Bool {
        switch type {
        case ShortcutType.walletTransfer:
            pendingWalletTransferShortcut = true
            return true
        case ShortcutType.bankTransfer:
            pendingBankTransferShortcut = true
            return true
        default:
            return false
        }
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

    @discardableResult
    func consumeWalletTransferShortcut() -> Bool {
        defer { pendingWalletTransferShortcut = false }
        return pendingWalletTransferShortcut
    }

    @discardableResult
    func consumeBankTransferShortcut() -> Bool {
        defer { pendingBankTransferShortcut = false }
        return pendingBankTransferShortcut
    }

    func consumeQuickTransfer() -> WalletTransferDraft? {
        defer { pendingQuickTransferDraft = nil }
        return pendingQuickTransferDraft
    }

    // MARK: - Private

    private func isPayLink(_ url: URL) -> Bool {
        if url.scheme == "nanowallet", url.host == "pay" { return true }
        if url.scheme == "https", url.host == "nano.casso.dev", url.path.hasPrefix("/pay") { return true }
        return false
    }
}
