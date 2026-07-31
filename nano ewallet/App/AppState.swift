//
//  AppState.swift
//  nano ewallet
//

import Foundation

/// Điều phối trạng thái gốc của app — mirror logic trong `SplashScreen.kt`.
///
/// Quyết định vào Login / WelcomeBack / Onboarding / Main dựa trên: có token không,
/// gọi `auth/refresh` được không, và nếu mất mạng thì fallback vào trạng thái đã cache.
@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()
    private init() {}

    @Published private(set) var root: AppRootState = .loading

    /// Gọi 1 lần lúc Splash hiện lên.
    func bootstrap() async {
        let store = AuthStore.shared
        let lastPhone = store.lastPhone

        // Giữ độ trễ splash tối thiểu giống Android (2.2s) để logo không chớp tắt.
        async let minimumDelay: Void = Task.sleep(nanoseconds: 2_200_000_000)

        guard store.accessToken != nil, store.refreshToken != nil else {
            _ = try? await minimumDelay
            root = .unauthenticated(lastPhone: lastPhone)
            return
        }

        do {
            let outcome = try await AuthService.refresh()
            _ = try? await minimumDelay
            apply(outcome: outcome, fallbackPhone: lastPhone)
        } catch let error as APIError {
            _ = try? await minimumDelay
            if case .offline = error {
                applyOfflineFallback(lastPhone: lastPhone)
            } else {
                // Server từ chối (401/403 — refresh token hết hạn/thu hồi) → về Login/WelcomeBack.
                root = .unauthenticated(lastPhone: lastPhone)
            }
        } catch {
            _ = try? await minimumDelay
            root = .unauthenticated(lastPhone: lastPhone)
        }
    }

    /// Gọi sau khi 1 trong các luồng auth (Login/Otp/WelcomeBack/DeviceOtp) hoàn tất.
    func apply(outcome: AuthService.AuthOutcome, fallbackPhone: String?) {
        switch outcome {
        case .authenticated(let user):
            route(status: user?.status, phone: user?.phone ?? fallbackPhone)
        case .requireOtp(let user):
            if let phone = user?.phone ?? fallbackPhone {
                root = .needOtp(phone: phone)
            } else {
                root = .unauthenticated(lastPhone: nil)
            }
        case .requireDeviceOtp:
            // UI tầng trên xử lý hộp thoại xác nhận + gửi/verify device OTP;
            // AppState chỉ nhận kết quả cuối cùng qua `apply` một lần nữa.
            break
        }
    }

    /// Sau khi có `status` xác thực từ server — nguồn duy nhất quyết định điều hướng.
    func route(status rawStatus: String?, phone: String?) {
        switch UserStatus(raw: rawStatus) {
        case .kycPending:
            if let phone {
                root = .onboarding(phone: phone)
            } else {
                root = .authenticated
            }
        case .active, .none:
            root = .authenticated
        case .pending:
            if let phone {
                root = .needOtp(phone: phone)
            } else {
                root = .unauthenticated(lastPhone: nil)
            }
        case .blocked:
            root = .unauthenticated(lastPhone: nil)
        }
    }

    func logout() async {
        await AuthService.logout()
        root = .unauthenticated(lastPhone: nil)
    }

    /// Chuyển thẳng về màn Login đầy đủ — dùng khi user bấm "Đăng nhập bằng tài khoản khác"
    /// ở WelcomeBack (đã tự xoá `lastPhone` trước khi gọi).
    func forceUnauthenticated(lastPhone: String?) {
        root = .unauthenticated(lastPhone: lastPhone)
    }

    // MARK: - Private

    /// Mất mạng lúc refresh — dùng cache đã lưu lúc login/refresh thành công gần nhất
    /// (mirror nhánh `catch IOException` trong SplashScreen.kt).
    private func applyOfflineFallback(lastPhone: String?) {
        let store = AuthStore.shared
        let cachedStatus = UserStatus(raw: store.lastKnownStatus)

        if cachedStatus == .kycPending, let phone = store.userPhone ?? lastPhone {
            root = .onboarding(phone: phone)
        } else if cachedStatus != nil {
            root = .authenticated
        } else if let lastPhone {
            root = .unauthenticated(lastPhone: lastPhone)
        } else {
            root = .unauthenticated(lastPhone: nil)
        }
    }
}
