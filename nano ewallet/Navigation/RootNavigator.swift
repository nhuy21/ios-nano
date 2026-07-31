//
//  RootNavigator.swift
//  nano ewallet
//
//  Mirror phần AppNavHost liên quan auth/onboarding trong MainActivity.kt.
//  Chuyển cây điều hướng theo AppRootState do AppState quyết định (bootstrap ở Splash).
//
//  Phase 1 chỉ có Auth + WalletOnboardingChoice. Nhánh `.authenticated` và các bước
//  onboarding sau Choice (CccdScan, KycReview...) sẽ nối ở Phase 2/3.
//

import SwiftUI

struct RootNavigator: View {
    @StateObject private var appState = AppState.shared

    var body: some View {
        Group {
            switch appState.root {
            case .loading:
                SplashView()
            case .unauthenticated(let lastPhone):
                AuthFlow(lastPhone: lastPhone)
            case .needOtp(let phone):
                // Bọc trong NavigationStack riêng để có back-gesture tới Login khi cần.
                NavigationStack {
                    OtpView(
                        phone: phone,
                        onBack: { appState.route(status: nil, phone: nil) },
                        onVerified: { appState.route(status: UserStatus.kycPending.rawValue, phone: phone) }
                    )
                }
            case .onboarding(let phone):
                NavigationStack {
                    WalletOnboardingChoiceView(
                        onBack: { Task { await appState.logout() } },
                        onSyncBaoKim: {
                            // TODO (Phase 3): điều hướng WalletLinkBaoKimView(phone)
                        },
                        onCreateNewWallet: {
                            // TODO (Phase 3): điều hướng CccdScanView(phone)
                        }
                    )
                }
                .id(phone) // đảm bảo state reset nếu phone đổi (hiếm khi xảy ra)
            case .authenticated:
                // TODO (Phase 2): thay bằng MainTabView thật.
                MainScreen()
            }
        }
        .animation(.default, value: appState.root)
    }
}

/// Cây điều hướng Auth — Login là root, các màn khác push lên trên.
/// Mirror chuỗi route SPLASH→LOGIN/WELCOME_BACK→REGISTER/OTP/FORGOT_PASSWORD.
private struct AuthFlow: View {
    let lastPhone: String?

    @StateObject private var appState = AppState.shared
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            rootView
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        if let lastPhone {
            WelcomeBackView(
                phone: lastPhone,
                onLogin: { status in appState.route(status: status, phone: lastPhone) },
                onUseAnotherAccount: {
                    AuthStore.shared.clearLastPhone()
                    appState.forceUnauthenticated(lastPhone: nil)
                },
                onForgotPassword: { path.append(.forgotPassword) }
            )
        } else {
            LoginView(
                onLogin: { phone, status in appState.route(status: status, phone: phone) },
                onRegister: { path.append(.register) },
                onForgotPassword: { path.append(.forgotPassword) }
            )
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .register:
            RegisterView(
                onBack: { path.removeLast() },
                onNext: { phone in path.append(.otp(phone: phone)) },
                onLogin: { path.removeAll() }
            )
        case .otp(let phone):
            OtpView(
                phone: phone,
                onBack: { path.removeLast() },
                onVerified: {
                    appState.route(status: UserStatus.kycPending.rawValue, phone: phone)
                }
            )
        case .forgotPassword:
            ForgotPasswordView(
                onBack: { path.removeLast() },
                onBackToLogin: { path.removeAll() }
            )
        case .login, .welcomeBack, .walletOnboardingChoice:
            EmptyView() // không push tới các route này trong cây Auth
        }
    }
}
