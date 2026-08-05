//
//  AppState.swift
//  nano ewallet
//

import Foundation
import Combine

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
        // Mở app hàng ngày (đã có phiên) thì mặc định vào màn quét QR — mirror
        // `DeepLinkStore.requestDefaultQr()` trong callback Splash bên Android.
        // Chỉ ĐẶT CỜ, không mở thẳng: deep link có thể tới sau vài nhịp, mở ngay sẽ đua
        // và đè lên link nhận tiền. MainTabView quyết định sau khi chắc chắn không còn
        // deep link nào chờ. `defer` để nhánh nào kết thúc ở `.authenticated` cũng chạy.
        defer {
            if root == .authenticated { DeepLinkStore.shared.requestDefaultQr() }
        }

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
    ///
    /// CHỈ `ACTIVE` được vào Home. `nil` (status thiếu, lạ, hoặc gọi từ chỗ không có
    /// status) phải về Login: gộp `nil` chung với `.active` biến mọi chỗ thiếu status
    /// thành một đường vào Home không qua xác thực — nút back ở màn OTP từng lọt đúng
    /// theo cách này (tài khoản `PENDING` chưa verify OTP mà vẫn dùng được các tab).
    func route(status rawStatus: String?, phone: String?) {
        switch UserStatus(raw: rawStatus) {
        case .kycPending:
            if let phone {
                root = .onboarding(phone: phone)
            } else {
                // Không biết SĐT thì không dựng được luồng onboarding. Về Login chứ không
                // vào Home: tài khoản KYC_PENDING chưa có ví, vào Home là màn hình rỗng.
                root = .unauthenticated(lastPhone: AuthStore.shared.lastPhone)
            }
        case .active:
            root = .authenticated
        case .pending:
            if let phone {
                root = .needOtp(phone: phone)
            } else {
                root = .unauthenticated(lastPhone: nil)
            }
        case .blocked:
            root = .unauthenticated(lastPhone: nil)
        case .none:
            root = .unauthenticated(lastPhone: AuthStore.shared.lastPhone)
        }
    }

    func logout() async {
        await AuthService.logout()
        // Xoá hộp thư trong bộ nhớ — không xoá thì tài khoản đăng nhập sau sẽ thấy
        // thông báo của tài khoản trước cho tới lần refresh kế tiếp.
        NotificationStore.shared.clear()
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
    /// Cũng theo quy tắc "chỉ ACTIVE mới vào Home" như `route(status:phone:)`: trước đây
    /// nhánh này chỉ hỏi `cachedStatus != nil`, nên cache `PENDING`/`BLOCKED` gặp lúc mất
    /// mạng là vào thẳng Home.
    private func applyOfflineFallback(lastPhone: String?) {
        let store = AuthStore.shared
        let cachedStatus = UserStatus(raw: store.lastKnownStatus)

        switch cachedStatus {
        case .kycPending:
            if let phone = store.userPhone ?? lastPhone {
                root = .onboarding(phone: phone)
            } else {
                root = .unauthenticated(lastPhone: lastPhone)
            }
        case .active:
            root = .authenticated
        case .pending, .blocked, .none:
            // Không dựng màn OTP ở đây dù cache là PENDING: gửi lại OTP cần mạng, mà nhánh
            // này chạy đúng lúc không có mạng.
            root = .unauthenticated(lastPhone: lastPhone)
        }
    }
}
