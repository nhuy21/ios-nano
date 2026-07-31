//
//  KeychainStore.swift
//  nano ewallet
//

import Foundation
import Security

/// Đọc/ghi Keychain — thay `EncryptedSharedPreferences` bên Android.
///
/// Dùng `kSecAttrAccessibleAfterFirstUnlock` để token đọc được sau lần mở máy đầu tiên
/// (cần cho push/background refresh), nhưng không đọc được khi máy còn khoá lần đầu.
enum KeychainStore {

    private static let service = "dev.casso.nanowallet.auth"

    // MARK: - API

    static func set(_ value: String, for key: Key) {
        guard let data = value.data(using: .utf8) else { return }

        // Xoá bản cũ trước rồi thêm mới — đơn giản và tránh mọi trường hợp update lỗi.
        remove(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Keys

    /// Giữ đúng 9 key như `AuthStore.kt` để dễ đối chiếu khi debug.
    enum Key: String {
        case deviceId = "device_id"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case pendingPhone = "pending_otp_phone"
        case lastPhone = "last_logged_in_phone"
        case userId = "user_id"
        case userPhone = "user_phone"
        case userFullName = "user_full_name"
        case lastKnownStatus = "last_known_status"
    }
}
