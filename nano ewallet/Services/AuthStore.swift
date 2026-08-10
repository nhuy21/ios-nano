//
//  AuthStore.swift
//  nano ewallet
//

import Foundation
import Combine

/// Lưu trữ phiên đăng nhập — mirror `AuthStore.kt` (EncryptedSharedPreferences → Keychain).
///
/// `deviceId` **phải ổn định qua các lần cài lại**: BE khoá phiên theo `(userId, deviceId)`,
/// nếu deviceId đổi thì mỗi lần cài lại app sẽ bị coi là máy mới → bắt OTP SMS.
/// Vì vậy dùng Keychain (giữ qua reinstall), KHÔNG dùng `identifierForVendor`.
@MainActor
final class AuthStore: ObservableObject {

    static let shared = AuthStore()
    private init() {
        userFullName = KeychainStore.get(.userFullName)
    }

    /// Tên hiển thị — Home/Settings quan sát để cập nhật ngay khi login xong
    /// (mirror `StateFlow<String?>` bên Android).
    @Published private(set) var userFullName: String?

    // MARK: - Device ID

    /// Sinh 1 lần rồi giữ mãi.
    func getOrCreateDeviceId() -> String {
        if let existing = KeychainStore.get(.deviceId) { return existing }
        let newId = UUID().uuidString
        KeychainStore.set(newId, for: .deviceId)
        return newId
    }

    // MARK: - Token

    func saveTokens(access: String, refresh: String) {
        KeychainStore.set(access, for: .accessToken)
        KeychainStore.set(refresh, for: .refreshToken)
    }

    var accessToken: String? { KeychainStore.get(.accessToken) }
    var refreshToken: String? { KeychainStore.get(.refreshToken) }

    /// Tăng lên mỗi lần phiên kết thúc. Dùng làm tín hiệu huỷ cho các tiến trình nền sống ở
    /// gốc cây view (vd `TopUpWatcher`): chúng KHÔNG bị huỷ khi điều hướng về màn Login, nên
    /// không có mốc này thì vòng chờ tiền về của tài khoản vừa đăng xuất vẫn chạy tiếp.
    @Published private(set) var sessionRevision = 0

    /// Xoá token + hồ sơ user. KHÔNG xoá `lastPhone` (xem `clearLastPhone`).
    func clearTokens() {
        KeychainStore.remove(.accessToken)
        KeychainStore.remove(.refreshToken)
        clearUser()
        sessionRevision &+= 1
    }

    // MARK: - Hồ sơ user

    /// Bỏ qua field nil để không ghi đè giá trị cũ bằng rỗng (giống Android).
    ///
    /// `status` là **nguồn duy nhất** để Splash điều hướng khi mất mạng không gọi được
    /// `auth/refresh` — chỉ ghi khi server vừa xác nhận, không suy đoán.
    func saveUser(_ user: UserAccount) {
        if let id = user.id { KeychainStore.set(id, for: .userId) }
        if let phone = user.phone { KeychainStore.set(phone, for: .userPhone) }
        if let fullName = user.fullName {
            KeychainStore.set(fullName, for: .userFullName)
            userFullName = fullName
        }
        if let status = user.status { KeychainStore.set(status, for: .lastKnownStatus) }
    }

    var userId: String? { KeychainStore.get(.userId) }
    var userPhone: String? { KeychainStore.get(.userPhone) }
    var lastKnownStatus: String? { KeychainStore.get(.lastKnownStatus) }

    private func clearUser() {
        [.userId, .userPhone, .userFullName, .lastKnownStatus].forEach(KeychainStore.remove)
        userFullName = nil
    }

    // MARK: - SĐT chờ xác thực OTP

    /// Lưu lúc register để màn OTP tự đọc lại, không cần truyền qua navigation.
    func savePendingPhone(_ phone: String) {
        KeychainStore.set(phone, for: .pendingPhone)
    }

    var pendingPhone: String? { KeychainStore.get(.pendingPhone) }

    func clearPendingPhone() {
        KeychainStore.remove(.pendingPhone)
    }

    // MARK: - SĐT đăng nhập gần nhất

    /// Có giá trị → mở app vào thẳng "Chào mừng trở lại" thay vì màn Login đầy đủ.
    /// Chỉ xoá khi user **chủ động** đăng xuất; token hết hạn thì GIỮ để lần sau chỉ cần
    /// nhập lại mật khẩu.
    func saveLastPhone(_ phone: String) {
        KeychainStore.set(phone, for: .lastPhone)
    }

    var lastPhone: String? { KeychainStore.get(.lastPhone) }

    func clearLastPhone() {
        KeychainStore.remove(.lastPhone)
    }
}
