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
/// "Nạp ví nhanh" — mở thẳng app ngân hàng NGUỒN (nơi người dùng đang có tiền) với số tài
/// khoản VA của ví + số tiền đã điền sẵn, qua deeplink công khai dl.vietqr.io/pay.
///
/// Không phải mở app theo bundle id: đây là một URL `https://` bình thường, VietQR nhận rồi
/// tự chuyển tiếp sang app ngân hàng. Nhờ vậy iOS không cần khai `LSApplicationQueriesSchemes`,
/// và máy chưa cài app ngân hàng thì rơi về trang web của VietQR thay vì bấm xong không thấy gì.
///
/// ĐIỀU KIỆN ĐỂ AUTOFILL CHẠY (bản Android đã kiểm chứng bằng HTTP thật, không phải suy đoán):
///  1. Phải gửi ĐỦ cả `am` (số tiền) VÀ `url` (callback). Thiếu một trong hai thì server chỉ
///     trả intent trần — app ngân hàng mở lên đứng ở màn chính, không điền gì. Vì vậy ô số
///     tiền ở màn chọn là BẮT BUỘC.
///  2. `url` chỉ nhận `https://` — custom scheme (`nanowallet://`) bị từ chối.
///  3. `tn` không dài quá ~41 ký tự.
enum QuickTopUpDeeplink {

    /// Query param đánh dấu callback của luồng này.
    static let returnParam = "topup_return"

    /// Universal Link của app (đã khai `/pay*` trong apple-app-site-association) — vừa hợp lệ
    /// với server VietQR (bắt buộc https), vừa mở lại được app sau khi chuyển tiền xong.
    /// KHÔNG kèm `req_token` nên không kích hoạt luồng Pay Link; `topup_return=1` để app biết
    /// đây là "vừa nạp tiền xong" và đưa về Trang chủ xem số dư, thay vì màn quét QR mặc định.
    private static let callbackURL = "https://nano.casso.dev/pay?\(returnParam)=1"

    struct SourceBank: Identifiable, Hashable {
        let appId: String
        let displayName: String
        /// Icon app trên App Store.
        let logoUrl: String
        /// BIN NAPAS — dùng vẽ logo vector LOCAL trong lúc ảnh chưa tải xong, và làm chỗ dựa
        /// nếu mạng hỏng. Nhờ vậy danh sách không bao giờ trống chỗ.
        let bin: String

        var id: String { appId }
    }

    /// Ngân hàng NGUỒN người dùng chọn để chuyển đi — không liên quan tới ngân hàng của chính
    /// VA ví, vì đây luôn là chuyển liên ngân hàng qua NAPAS tới đúng VA đó.
    /// Chỉ liệt kê 5 app đã xác nhận autofill được; ngân hàng ngoài danh sách không hiện ra,
    /// đó cũng chính là cách chặn trường hợp mở lên mà không điền được gì.
    static let supportedBanks: [SourceBank] = [
        SourceBank(
            appId: "icb",
            displayName: "VietinBank iPay",
            logoUrl: "https://is4-ssl.mzstatic.com/image/thumb/Purple112/v4/14/04/b8/1404b8f4-a91f-f8bf-7af5-1a0e59bbdf19/AppIcon-0-0-1x_U007emarketing-0-0-0-7-0-0-sRGB-0-0-0-GLES2_U002c0-512MB-85-220-0-0.png/1200x630wa.png",
            bin: "970415"
        ),
        SourceBank(
            appId: "bidv",
            displayName: "BIDV SmartBanking",
            logoUrl: "https://is1-ssl.mzstatic.com/image/thumb/Purple112/v4/88/1b/e6/881be6df-e9b6-8b66-e0fb-2499ac874734/AppIcon-1x_U007emarketing-0-6-0-0-85-220.png/1200x630wa.png",
            bin: "970418"
        ),
        SourceBank(
            appId: "ocb",
            displayName: "OCB OMNI",
            logoUrl: "https://is4-ssl.mzstatic.com/image/thumb/Purple122/v4/f0/66/94/f066942c-2cc6-2c87-407b-a38f2e99656f/AppIcon-0-0-1x_U007emarketing-0-0-0-10-0-0-sRGB-0-0-0-GLES2_U002c0-512MB-85-220-0-0.png/1200x630wa.png",
            bin: "970448"
        ),
        SourceBank(
            appId: "acb",
            displayName: "ACB ONE",
            logoUrl: "https://is4-ssl.mzstatic.com/image/thumb/Purple122/v4/a1/ae/1e/a1ae1e68-2d58-92bc-9ec5-42917a59f767/AppIcon-1x_U007emarketing-0-7-0-0-85-220.png/1200x630wa.png",
            bin: "970416"
        ),
        SourceBank(
            appId: "mb",
            displayName: "MB Bank",
            logoUrl: "https://is2-ssl.mzstatic.com/image/thumb/Purple122/v4/f4/0a/b6/f40ab6a2-e67d-e267-9c46-ae03dfa238a9/AppIcon-0-0-1x_U007emarketing-0-0-0-7-0-0-sRGB-0-0-0-GLES2_U002c0-512MB-85-220-0-0.png/1200x630wa.png",
            bin: "970422"
        ),
    ]

    /// BIN NAPAS -> mã ngắn của dl.vietqr.io, dùng cho phần sau dấu `@` của tham số `ba`.
    /// VA của ví có thể nằm ở ngân hàng NGOÀI 5 app nguồn ở trên nên map này rộng hơn.
    private static let binToShortCode: [String: String] = [
        "970415": "icb",   // VietinBank
        "970418": "bidv",  // BIDV
        "970448": "ocb",   // OCB
        "970416": "acb",   // ACB
        "970422": "mb",    // MB Bank
        "970436": "vcb",   // Vietcombank
        "970407": "tcb",   // Techcombank
        "970432": "vpb",   // VPBank
        "970423": "tpb",   // TPBank
        "970403": "scb",   // Sacombank (không nhầm với SCB — Ngân hàng Sài Gòn)
    ]

    /// Dựng URL cho ngân hàng nguồn `sourceAppId` chuyển tới VA của ví hiện tại.
    /// - Returns: `nil` khi ví chưa có VA, hoặc ngân hàng của VA không tra được mã ngắn —
    ///   không dựng URL thiếu tham số rồi đẩy người dùng sang app ngân hàng trống trơn.
    static func buildURL(sourceAppId: String, amount: Int64?) -> URL? {
        let wallet = WalletStore.shared
        guard let vaNumber = wallet.vaNumber, !vaNumber.isEmpty,
              let vaBankNo = wallet.vaBankNo, !vaBankNo.isEmpty,
              let destShortCode = binToShortCode[vaBankNo] else {
            return nil
        }

        // Giữ NGẮN — quá ~41 ký tự là server ngừng sinh mã, mất autofill.
        let note = "Nap vi BK \(vaNumber)"
        let beneficiaryName = noAccent(
            wallet.accName.flatMap { $0.isEmpty ? nil : $0 } ?? "Vi Nano"
        )

        // Tự ghép chuỗi query thay vì dùng `URLComponents.queryItems`: bộ đó chỉ mã hoá những
        // ký tự KHÔNG hợp lệ trong query, mà `?`, `=`, `&` lại hợp lệ nên nó để nguyên. Tham số
        // `url` mang trọn một URL có sẵn `?topup_return=1` bên trong — để nguyên thì server đọc
        // `url` bị cắt ngang và `topup_return=1` biến thành tham số của chính dl.vietqr.io,
        // hỏng đúng cái điều kiện bắt buộc để autofill hoạt động.
        var query = [
            "app=\(escape(sourceAppId))",
            "ba=\(escape("\(vaNumber)@\(destShortCode)"))",
        ]
        if let amount, amount > 0 {
            query.append("am=\(amount)")
        }
        query.append("tn=\(escape(note))")
        query.append("bn=\(escape(beneficiaryName))")
        query.append("url=\(escape(callbackURL))")
        return URL(string: "https://dl.vietqr.io/pay?" + query.joined(separator: "&"))
    }

    /// Mã hoá đúng kiểu `URLEncoder` bên Android: mọi ký tự ngoài nhóm không dè dặt đều
    /// thành `%XX`, kể cả `:` `/` `?` `=` `&` `@`.
    private static func escape(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// Bỏ dấu tiếng Việt. `tn`/`bn` đi qua EMV QR/NAPAS, nhiều hệ thống bên đó không xử lý
    /// đúng ký tự Unicode có dấu. `đ`/`Đ` phải thay tay vì không tách ra được như các dấu khác.
    private static func noAccent(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
    }
}

@MainActor
final class DeepLinkStore: ObservableObject {
    static let shared = DeepLinkStore()
    private init() {}

    /// Pay link đang chờ (Universal Link https://nano.casso.dev/pay hoặc nanowallet://pay).
    @Published private(set) var pendingPayToken: String?

    /// Mở màn hội thoại xin tiền với 1 người (từ push MONEY_REQUEST).
    @Published private(set) var pendingConversationBkUsername: String?

    /// Vừa từ app ngân hàng quay về sau "Nạp ví nhanh" -> vào Trang chủ để thấy số dư,
    /// không mở màn quét QR mặc định.
    @Published private(set) var pendingTopUpReturn = false

    /// Số dư chốt NGAY TRƯỚC khi rời sang app ngân hàng — mốc để biết tiền đã về hay chưa.
    ///
    /// Phải chốt từ lúc đó chứ không đọc lại khi quay về: tiền có thể đã vào trong lúc người
    /// dùng còn đang ở app ngân hàng, mốc đọc muộn sẽ đã bao gồm khoản mới nên so sánh không
    /// bao giờ thấy tăng — banner quay vô ích rồi tắt dù thực tế tiền đã về.
    private(set) var balanceBeforeTopUp: Int64?

    /// Gọi ngay trước khi mở app ngân hàng.
    func markTopUpStarted(balanceBefore: Int64?) {
        balanceBeforeTopUp = balanceBefore
    }

    /// Xoá mốc sau khi đã xác nhận tiền về. Nhánh hết giờ chờ thì GIỮ lại: nút "Đồng bộ" trên
    /// banner vẫn cần mốc này để so sánh.
    func clearTopUpBaseline() {
        balanceBeforeTopUp = nil
    }

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
            || pendingQuickTransferDraft != nil || pendingTopUpReturn
    }

    // MARK: - Phát

    /// Nhận URL từ Universal Link / custom scheme. Trả false nếu không phải link của app.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard isPayLink(url) else { return false }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        // Quay về từ app ngân hàng sau "Nạp ví nhanh". Dùng CHUNG đường `/pay` với link nhận
        // tiền (server VietQR bắt buộc callback là https, mà app chỉ xác thực được đường này),
        // phân biệt nhau bằng có `req_token` hay không — nhánh này phải xét TRƯỚC, nếu không
        // nó rơi xuống guard bên dưới rồi bị trả `false` và mất luôn callback.
        if queryItems?.contains(where: { $0.name == QuickTopUpDeeplink.returnParam }) == true {
            pendingTopUpReturn = true
            return true
        }

        // BE dùng query `req_token` (xem MainActivity.handleDeepLink bên Android).
        guard let token = queryItems?
            .first(where: { $0.name == "req_token" })?.value,
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
    func consumeTopUpReturn() -> Bool {
        defer { pendingTopUpReturn = false }
        return pendingTopUpReturn
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
