//
//  BiometricTokenStore.swift
//  nano ewallet
//
//  Token đăng nhập sinh trắc, lưu Keychain có ACL SINH TRẮC — đọc được là phải quét mặt.
//
//  Tách khỏi `KeychainStore` (dùng `kSecAttrAccessibleAfterFirstUnlock`, không cần sinh trắc):
//  refreshToken ở đó được `TokenRefresher` dùng TỰ ĐỘNG ở nền, để sau ACL sinh trắc thì mỗi lần
//  làm mới access token lại bật Face ID lên giữa lúc đang dùng app, và trong background thì fail.
//  Token ở file này chỉ đọc khi người dùng chủ động đăng nhập lại.
//

import Foundation
import LocalAuthentication
import Security

nonisolated enum BiometricTokenStore {

    private static let service = "dev.casso.nanowallet.biometric"
    private static let account = "biometric_login_token"

    /// Ghi token. Trả false nếu Keychain từ chối (máy chưa đặt mật mã, chưa thiết lập Face ID...)
    /// — người gọi PHẢI xử lý, không được coi như đã bật xong.
    @discardableResult
    static func save(_ token: String) -> Bool {
        remove()

        guard let data = token.data(using: .utf8) else { return false }

        // `.biometryCurrentSet`: thêm/đổi khuôn mặt trong Cài đặt iOS là mục này tự vô hiệu —
        // kẻ có mật mã máy không thể thêm khuôn mặt của mình rồi đăng nhập.
        // `...ThisDeviceOnly`: không sync iCloud, không vào backup.
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &accessError
        ) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Đọc token — iOS TỰ hiện Face ID vì mục có ACL sinh trắc. `nil` khi huỷ/thất bại/khoá đã
    /// bị vô hiệu (đổi khuôn mặt).
    ///
    /// `localizedFallbackTitle = ""` để ẩn nút "Nhập mật mã": mật mã MỞ MÁY không được thay cho
    /// đăng nhập tài khoản. Muốn dùng mật khẩu app thì bấm nút riêng trên UI của mình.
    static func read(reason: String) -> String? {
        let context = LAContext()
        context.localizedReason = reason
        context.localizedFallbackTitle = ""

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Có token hay chưa — KHÔNG bật Face ID.
    ///
    /// Chỉ hỏi thuộc tính (`kSecReturnAttributes`), không xin dữ liệu, nên Keychain không cần mở
    /// khoá. `errSecInteractionNotAllowed` = mục CÓ nhưng cần xác thực -> vẫn tính là đã bật.
    static func exists() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
