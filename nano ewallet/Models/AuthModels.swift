//
//  AuthModels.swift
//  nano ewallet
//
//  DTO mirror 1-1 theo be/src/auth/dto/auth.dto.ts — tên field phải khớp tuyệt đối.
//

import Foundation

// MARK: - Response

/// `data` của login / verify-otp / verify-device-otp / refresh.
///
/// `accessToken`/`refreshToken` là **nil** trong 2 trường hợp BE cố tình không cấp token:
/// - `requireOtp`: tài khoản còn PENDING (chưa verify OTP đăng ký), BE đã gửi lại OTP.
/// - `requireDeviceOtp`: mật khẩu ĐÚNG nhưng máy khác đang đăng nhập → BE trả `loginTicket`.
nonisolated struct AuthData: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let user: UserAccount?
    let requireOtp: Bool?
    let requireDeviceOtp: Bool?
    let loginTicket: String?
}

nonisolated struct UserAccount: Decodable {
    let id: String?
    let phone: String?
    let fullName: String?
    let status: String?
}

/// `data` của send-device-otp — SĐT nhận OTP để màn nhập OTP hiển thị "đã gửi tới 09xx***".
struct SendDeviceOtpData: Decodable {
    let phone: String?
}

struct DeviceSession: Decodable, Identifiable {
    let deviceId: String
    let deviceName: String?
    let lastUsedAt: String
    let createdAt: String
    let status: String

    var id: String { deviceId }
}

/// Trạng thái tài khoản — quyết định điều hướng sau khi đăng nhập.
/// Nguồn: be/src/enums.
enum UserStatus: String {
    /// Đăng ký xong, chưa verify OTP. `login` KHÔNG cấp token, trả `requireOtp` → màn OTP.
    case pending = "PENDING"
    /// Đã verify OTP, chưa xong eKYC. **Token VẪN được cấp** → đã đăng nhập nhưng phải
    /// vào luồng onboarding (WalletOnboardingChoice).
    case kycPending = "KYC_PENDING"
    /// Hoàn tất onboarding → vào Main.
    case active = "ACTIVE"
    /// Bị khoá — trạng thái cuối, phải đăng xuất.
    case blocked = "BLOCKED"

    init?(raw: String?) {
        guard let raw, let value = UserStatus(rawValue: raw) else { return nil }
        self = value
    }
}

// MARK: - Request

struct LoginRequest: Encodable {
    let phone: String
    let password: String
    let deviceId: String
    let deviceName: String
}

struct RegisterRequest: Encodable {
    let phone: String
    let password: String
    let confirmPassword: String
    let email: String
}

struct VerifyOtpRequest: Encodable {
    let phone: String
    let otp: String
    let deviceId: String
    let deviceName: String
}

struct PhoneOnlyRequest: Encodable {
    let phone: String
}

struct ResetPasswordRequest: Encodable {
    let phone: String
    let otp: String
    let newPassword: String
    let confirmPassword: String
}

nonisolated struct RefreshRequest: Encodable {
    let deviceId: String
    let refreshToken: String
}

struct DeviceIdRequest: Encodable {
    let deviceId: String
}

struct SendDeviceOtpRequest: Encodable {
    let loginTicket: String
}

struct VerifyDeviceOtpRequest: Encodable {
    let loginTicket: String
    let otp: String
}

// MARK: - Validate (mirror @Matches ở BE để chặn sớm, đỡ 1 vòng request)

enum AuthValidator {

    /// BE chạy `normalizePhone` TRƯỚC khi validate `^[0-9]{10,11}$`:
    /// - Xoá `[\s+\-()]`
    /// - `0…` → `84…`, hoặc giữ `84…`
    /// - Đầu số khác `0`/`84` → BE ném "Số điện thoại không hợp lệ"
    ///
    /// Nên client chỉ cần chặn dạng chắc chắn sai, tránh chặn oan số hợp lệ.
    static func isValidPhone(_ phone: String) -> Bool {
        normalizePhone(phone) != nil
    }

    /// Chuẩn hoá giống `be/src/common/utils.ts` — dùng khi cần so sánh/hiển thị.
    /// Trả nil nếu không hợp lệ.
    static func normalizePhone(_ raw: String) -> String? {
        let stripped = raw.filter { !" +-()".contains($0) }
        guard stripped.allSatisfy(\.isNumber), !stripped.isEmpty else { return nil }

        let normalized: String
        if stripped.hasPrefix("0") {
            normalized = "84" + stripped.dropFirst()
        } else if stripped.hasPrefix("84") {
            normalized = stripped
        } else {
            return nil
        }
        return (10...11).contains(normalized.count) ? normalized : nil
    }

    /// BE: `@Matches(/^[0-9]{6}$/)` — mật khẩu là 6 CHỮ SỐ (không phải chữ).
    static func isValidPassword(_ password: String) -> Bool {
        password.count == 6 && password.allSatisfy(\.isNumber)
    }

    /// BE: `@Matches(/^[0-9]{6}$/)`
    static func isValidOtp(_ otp: String) -> Bool {
        otp.count == 6 && otp.allSatisfy(\.isNumber)
    }

    /// BE: `@Matches(/^[^\s@]+@[^\s@]+\.[^\s@]+$/)`
    static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}
