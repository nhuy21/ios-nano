//
//  Route.swift
//  nano ewallet
//

import Foundation

/// Điểm đến điều hướng — thay 37 route string bên Android bằng enum type-safe.
/// Phase 1 chỉ khai các route auth + onboarding choice; bổ sung dần theo phase.
enum Route: Hashable {
    // Auth
    case login
    case register
    case otp(phone: String)
    case forgotPassword
    case welcomeBack(phone: String)

    // Onboarding
    case walletOnboardingChoice(phone: String)

    // TODO (Phase 3): walletLinkBaoKim, cccdScan, kycReview, walletRules...
}

/// Route con của tab Settings — cây điều hướng riêng (NavigationStack độc lập với Auth).
enum SettingsRoute: Hashable {
    case security
    case changePassword
    case pinLimit
    case devices
    case linkedBanks
    case termsOfUse
}

/// Route con của tab Home.
enum HomeRoute: Hashable {
    case history
    case contacts
}

/// Trạng thái gốc của app — quyết định cây điều hướng nào được hiển thị.
/// Mirror cách `SplashScreen` + `AppNavHost` phân nhánh bên Android.
enum AppRootState: Equatable {
    /// Đang kiểm tra phiên (Splash).
    case loading
    /// Chưa đăng nhập, có `lastPhone` → vào WelcomeBack; không có → Login.
    case unauthenticated(lastPhone: String?)
    /// Đăng ký chưa verify OTP.
    case needOtp(phone: String)
    /// Đã có token nhưng chưa có ví → luồng onboarding.
    case onboarding(phone: String)
    /// Đủ điều kiện dùng app.
    case authenticated
}
