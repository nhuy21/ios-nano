//
//  AuthService.swift
//  nano ewallet
//

import Foundation

/// Gọi API auth của backend — mirror `AuthApi.kt`.
///
/// Giữ nguyên các *side effect* của bản Android (lưu token/pendingPhone/lastPhone ở đâu,
/// khi nào) vì UI phụ thuộc vào đó để điều hướng.
@MainActor
enum AuthService {

    private static var client: APIClient { .shared }
    private static var store: AuthStore { .shared }

    /// Kết quả login/verify — 3 nhánh loại trừ nhau.
    enum AuthOutcome {
        /// Có token, đăng nhập xong. `status` quyết định vào Main hay Onboarding.
        case authenticated(UserAccount?)
        /// Tài khoản PENDING — BE đã gửi lại OTP, vào màn OTP.
        case requireOtp(UserAccount?)
        /// Mật khẩu đúng nhưng máy khác đang đăng nhập — cần xác nhận + OTP SMS.
        case requireDeviceOtp(loginTicket: String, user: UserAccount?)
    }

    // MARK: - Đăng nhập

    /// `POST auth/login`
    /// - Parameter rememberPhone: true khi login từ màn Login đầy đủ → ghi `lastPhone`.
    ///   false khi login từ WelcomeBack (SĐT không đổi) → không ghi lại.
    static func login(
        phone: String,
        password: String,
        rememberPhone: Bool = true
    ) async throws -> AuthOutcome {
        let body = LoginRequest(
            phone: phone,
            password: password,
            deviceId: store.getOrCreateDeviceId(),
            deviceName: AppConfig.deviceName
        )
        let data = try await client.request(.post, "auth/login", body: body, as: AuthData.self)
        return try applyAuthData(data, phone: phone, rememberPhone: rememberPhone, isRegisterOtp: true)
    }

    /// `POST auth/biometric/login` — đổi token sinh trắc (đã đọc được sau khi quét mặt) lấy
    /// session. KHÔNG lưu/gửi mật khẩu.
    ///
    /// Dùng chung `applyAuthData` với login thường vì BE trả đúng 3 nhánh giống nhau: có token /
    /// PENDING / máy khác đang đăng nhập (requireDeviceOtp) — sinh trắc không né được OTP SMS.
    /// `rememberPhone: false` vì token này chỉ có trên máy đã từng đăng nhập, `lastPhone` đã có.
    static func loginWithBiometricToken(_ biometricToken: String) async throws -> AuthOutcome {
        let body = BiometricLoginRequest(
            deviceId: store.getOrCreateDeviceId(),
            biometricToken: biometricToken,
            deviceName: AppConfig.deviceName
        )
        let data = try await client.request(
            .post, "auth/biometric/login", body: body, as: AuthData.self
        )
        return try applyAuthData(data, phone: nil, rememberPhone: false, isRegisterOtp: false)
    }

    // MARK: - Đăng ký

    /// `POST auth/register` — không trả token, BE tạo user PENDING + gửi OTP qua **SMS**.
    static func register(
        phone: String,
        password: String,
        confirmPassword: String,
        email: String
    ) async throws {
        let body = RegisterRequest(
            phone: phone,
            password: password,
            confirmPassword: confirmPassword,
            email: email
        )
        try await client.requestVoid(.post, "auth/register", body: body)
        store.savePendingPhone(phone)
    }

    /// `POST auth/verify-otp` — xác thực OTP đăng ký.
    ///
    /// Lưu ý: BE chuyển status PENDING → KYC_PENDING rồi **gọi lại `login()` nội bộ**, nên
    /// response CÓ THỂ là `requireDeviceOtp` nếu tài khoản đang đăng nhập ở máy khác.
    /// Vì vậy trả `AuthOutcome` chứ không giả định luôn có token.
    static func verifyOtp(_ otp: String) async throws -> AuthOutcome {
        guard let phone = store.pendingPhone else {
            throw APIError.unknown("Không tìm thấy số điện thoại đang chờ xác thực, vui lòng đăng ký lại")
        }
        let body = VerifyOtpRequest(
            phone: phone,
            otp: otp,
            deviceId: store.getOrCreateDeviceId(),
            deviceName: AppConfig.deviceName
        )
        let data = try await client.request(.post, "auth/verify-otp", body: body, as: AuthData.self)
        let outcome = try applyAuthData(data, phone: phone, rememberPhone: true, isRegisterOtp: false)
        if case .authenticated = outcome {
            store.clearPendingPhone()
        }
        return outcome
    }

    /// `POST auth/resend-verification`
    ///
    /// Cảnh báo cooldown: BE chặn khi OTP cũ **còn hiệu lực** → cooldown thực tế là
    /// trọn 5 phút TTL, không phải 60s. Response không có `retryAfter`, client tự đếm.
    static func resendOtp() async throws {
        guard let phone = store.pendingPhone else {
            throw APIError.unknown("Không tìm thấy số điện thoại đang chờ xác thực, vui lòng đăng ký lại")
        }
        try await client.requestVoid(
            .post, "auth/resend-verification", body: PhoneOnlyRequest(phone: phone)
        )
    }

    // MARK: - Quên mật khẩu

    /// `POST auth/send-password-reset` — cooldown cũng là trọn 5 phút TTL.
    static func sendPasswordReset(phone: String) async throws {
        try await client.requestVoid(
            .post, "auth/send-password-reset", body: PhoneOnlyRequest(phone: phone)
        )
    }

    /// `POST auth/reset-password`
    static func resetPassword(
        phone: String,
        otp: String,
        newPassword: String,
        confirmPassword: String
    ) async throws {
        let body = ResetPasswordRequest(
            phone: phone,
            otp: otp,
            newPassword: newPassword,
            confirmPassword: confirmPassword
        )
        try await client.requestVoid(.post, "auth/reset-password", body: body)
    }

    // MARK: - Đăng nhập máy mới (device OTP)

    /// `POST auth/send-device-otp` — trả SĐT nhận OTP để hiển thị dạng che.
    /// Gọi sau khi user đồng ý đăng xuất thiết bị kia.
    @discardableResult
    static func sendDeviceOtp(loginTicket: String) async throws -> String? {
        let data = try await client.request(
            .post, "auth/send-device-otp",
            body: SendDeviceOtpRequest(loginTicket: loginTicket),
            as: SendDeviceOtpData.self
        )
        return data.phone
    }

    /// `POST auth/verify-device-otp` — OTP đúng → BE đăng xuất mọi máy khác rồi cấp token.
    /// `loginTicket` và OTP dùng 1 lần; sai/hết hạn phải đăng nhập lại từ đầu.
    static func verifyDeviceOtp(loginTicket: String, otp: String) async throws -> AuthOutcome {
        let body = VerifyDeviceOtpRequest(loginTicket: loginTicket, otp: otp)
        let data = try await client.request(
            .post, "auth/verify-device-otp", body: body, as: AuthData.self
        )
        return try applyAuthData(data, phone: nil, rememberPhone: false, isRegisterOtp: false)
    }

    // MARK: - Phiên

    /// `POST auth/refresh` — dùng ở Splash để kiểm tra phiên còn sống + lấy status mới nhất.
    static func refresh() async throws -> AuthOutcome {
        guard let refreshToken = store.refreshToken else {
            throw APIError.unauthenticated
        }
        let body = RefreshRequest(
            deviceId: store.getOrCreateDeviceId(),
            refreshToken: refreshToken
        )
        let data = try await client.request(.post, "auth/refresh", body: body, as: AuthData.self)
        return try applyAuthData(data, phone: nil, rememberPhone: false, isRegisterOtp: false)
    }

    /// `POST auth/logout` — best-effort: API lỗi vẫn phải đăng xuất được cục bộ.
    /// Xoá cả `lastPhone` → lần mở app sau về màn Login đầy đủ (khác với token hết hạn).
    static func logout() async {
        if store.accessToken != nil {
            await PushRegistrar.shared.unregister()
            let body = DeviceIdRequest(deviceId: store.getOrCreateDeviceId())
            try? await client.requestVoid(.post, "auth/logout", body: body, auth: true)
        }
        store.clearTokens()
        store.clearLastPhone()
        // BE đã thu hồi phía server trong `logout` (xem auth.service.ts), nhưng token/khoá trên
        // MÁY phải xoá theo: để lại thì WelcomeBack vẫn hiện nút Face ID rồi quét mặt xong mới
        // báo lỗi, và khoá ký giao dịch thành khoá mồ côi.
        BiometricTokenStore.remove()
        BiometricKeyStore.deleteKey()
        WalletStore.shared.clear()
        TransactionStore.shared.clear()
        BeneficiaryStore.shared.clear()
    }

    /// `GET auth/devices` — thiết bị đang đăng nhập, active trước rồi `lastUsedAt` giảm dần.
    static func getDevices() async throws -> [DeviceSession] {
        try await client.request(.get, "auth/devices", auth: true, as: [DeviceSession].self)
    }

    /// `POST auth/remove-device` — xoá hẳn 1 thiết bị khỏi danh sách.
    static func removeDevice(deviceId: String) async throws {
        try await client.requestVoid(
            .post, "auth/remove-device", body: DeviceIdRequest(deviceId: deviceId), auth: true
        )
    }

    // MARK: - Private

    /// Phân nhánh response + lưu trạng thái, dùng chung cho login/verify-otp/verify-device-otp/refresh.
    private static func applyAuthData(
        _ data: AuthData,
        phone: String?,
        rememberPhone: Bool,
        isRegisterOtp: Bool
    ) throws -> AuthOutcome {
        if let user = data.user {
            store.saveUser(user)
        }

        // Nhánh B: máy khác đang đăng nhập. KHÔNG lưu pendingPhone — đây không phải OTP
        // đăng ký, lưu vào sẽ khiến màn OTP tưởng đang verify tài khoản mới.
        if data.requireDeviceOtp == true {
            guard let ticket = data.loginTicket else {
                throw APIError.decoding("requireDeviceOtp nhưng thiếu loginTicket")
            }
            if rememberPhone, let phone { store.saveLastPhone(phone) }
            return .requireDeviceOtp(loginTicket: ticket, user: data.user)
        }

        // Nhánh A: PENDING — BE không cấp token, đã gửi lại OTP.
        if data.requireOtp == true || data.accessToken == nil {
            if rememberPhone, let phone { store.saveLastPhone(phone) }
            if isRegisterOtp, let phone { store.savePendingPhone(phone) }
            return .requireOtp(data.user)
        }

        // Nhánh C: có token.
        guard let accessToken = data.accessToken, let refreshToken = data.refreshToken else {
            throw APIError.decoding("thiếu accessToken/refreshToken")
        }
        store.saveTokens(access: accessToken, refresh: refreshToken)
        if rememberPhone, let phone { store.saveLastPhone(phone) }
        PushRegistrar.shared.syncCurrentToken()
        return .authenticated(data.user)
    }
}
