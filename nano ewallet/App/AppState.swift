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
        //
        // Có ảnh vừa chia sẻ từ app khác đang chờ thì KHÔNG đặt cờ: người dùng chia sẻ ảnh
        // là đã chọn xong người nhận, mở QR bắt quét thêm mã nữa là sai ý. Phải chặn ngay
        // TỪ ĐÂY chứ không chặn ở `MainTabView`: việc bóc tách ảnh là bất đồng bộ (OCR/gọi
        // API mất vài giây) nên nhánh QR luôn chạy xong trước, người dùng thấy màn quét mở
        // ra rồi mới bị đẩy sang màn chuyển tiền.
        defer {
            if root == .authenticated, !SharedImageStore.hasPending {
                DeepLinkStore.shared.requestDefaultQr()
            }
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
            let session = try await AuthService.refresh()
            _ = try? await minimumDelay
            // Refresh THÀNH CÔNG nghĩa là BE đã nhận refresh token và cấp token mới — phiên
            // chắc chắn còn sống. Response không kèm `user` thì lấy status đã lưu, KHÔNG để
            // `route` nhận `nil` rồi rơi vào nhánh "không rõ status" và đẩy về màn đăng nhập.
            route(
                status: session.status ?? store.lastKnownStatus,
                phone: session.phone ?? store.userPhone ?? lastPhone
            )
        } catch {
            _ = try? await minimumDelay
            // CHỈ 401/403 mới là hết phiên. Mất mạng, timeout, DNS/TLS lỗi, BE 5xx, decode
            // sai... đều là sự cố tạm thời: token vẫn dùng được nên vào bằng trạng thái đã
            // cache, KHÔNG bắt đăng nhập lại. Trước đây mọi lỗi không phải `.offline` đều bị
            // coi là hết phiên — đó là lý do thỉnh thoảng mở app lại thấy màn đăng nhập, mà
            // thoát vào lại thì vào bình thường.
            if APIError.from(transport: error).isSessionEnded {
                root = .unauthenticated(lastPhone: lastPhone)
            } else {
                applyCachedFallback(lastPhone: lastPhone)
            }
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
        // `AuthService.logout()` đã dọn hết: token, khoá sinh trắc, và mọi cache theo user
        // (ví, giao dịch, danh bạ, hộp thư). Không lặp lại ở đây để chỉ có MỘT nơi phải nhớ.
        await AuthService.logout()
        root = .unauthenticated(lastPhone: nil)
    }

    /// Chuyển thẳng về màn Login đầy đủ — dùng khi user bấm "Đăng nhập bằng tài khoản khác"
    /// ở WelcomeBack (đã tự xoá `lastPhone` trước khi gọi).
    func forceUnauthenticated(lastPhone: String?) {
        root = .unauthenticated(lastPhone: lastPhone)
    }

    // MARK: - Private

    /// Không gọi được `auth/refresh` vì sự cố tạm thời (mất mạng, timeout, DNS/TLS, BE 5xx) —
    /// dùng cache đã lưu lúc login/refresh thành công gần nhất (mirror nhánh
    /// `catch IOException` trong SplashScreen.kt).
    /// Cũng theo quy tắc "chỉ ACTIVE mới vào Home" như `route(status:phone:)`: trước đây
    /// nhánh này chỉ hỏi `cachedStatus != nil`, nên cache `PENDING`/`BLOCKED` gặp lúc mất
    /// mạng là vào thẳng Home.
    private func applyCachedFallback(lastPhone: String?) {
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
