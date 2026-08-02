//
//  RootNavigator.swift
//  nano ewallet
//
//  Mirror phần AppNavHost liên quan auth/onboarding trong MainActivity.kt.
//  Chuyển cây điều hướng theo AppRootState do AppState quyết định (bootstrap ở Splash).
//
//  Phase 1: Auth + WalletOnboardingChoice + khung Main (Home/Settings placeholder).
//  Các bước onboarding sau Choice (CccdScan, KycReview...) sẽ nối ở Phase 3.
//

import SwiftUI
import Combine

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
                    .hidesSystemNavigationBar()
                }
            case .onboarding(let phone):
                OnboardingFlow()
                    .id(phone) // đảm bảo state reset nếu phone đổi (hiếm khi xảy ra)
            case .authenticated:
                MainTabView()
            }
        }
        .animation(.default, value: appState.root)
    }
}

/// Cây onboarding sau khi đăng nhập nhưng chưa có ví — mirror nhánh
/// WALLET_ONBOARDING_CHOICE → WALLET_LINK_BAOKIM → WALLET_RULES trong MainActivity.kt.
///
/// Giữ bước bằng state cục bộ thay vì `NavigationStack` path: `embed_link` là URL dài,
/// nhét vào route argument thì phải encode/decode lằng nhằng (Android cũng giữ state
/// cục bộ vì lý do này). Các bước ở đây không có back-gesture nên cũng không cần stack.
private struct OnboardingFlow: View {

    @StateObject private var appState = AppState.shared

    private enum Step {
        case choice
        case linkBaoKim
        /// Đang nhúng trang OTP của Bảo Kim.
        case linking(embedLink: String)
        /// Ví đã đồng bộ xong — đọc quy tắc giao dịch một lần rồi vào Home.
        case rules
        case pinLimit
    }

    @State private var step: Step = .choice
    /// Bảo Kim từ chối ngay lúc gửi yêu cầu liên kết (ví không tồn tại, ví khoá, SĐT đã
    /// liên kết, tên không khớp).
    @State private var linkError: String?

    var body: some View {
        content
            .alert(
                "Không liên kết được ví",
                isPresented: Binding(get: { linkError != nil }, set: { if !$0 { linkError = nil } })
            ) {
                Button("Đã hiểu", role: .cancel) { linkError = nil }
            } message: {
                Text(linkError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .choice:
            NavigationStack {
                WalletOnboardingChoiceView(
                    onBack: { Task { await appState.logout() } },
                    onSyncBaoKim: { step = .linkBaoKim },
                    onCreateNewWallet: {
                        // TODO: điều hướng CccdScanView(phone) khi luồng eKYC hoàn thiện.
                    }
                )
                .hidesSystemNavigationBar()
            }

        case .linkBaoKim:
            NavigationStack {
                WalletLinkBaoKimView(
                    onBack: { step = .choice },
                    onSubmit: { link in step = .linking(embedLink: link) },
                    onError: { message in linkError = message }
                )
                .hidesSystemNavigationBar()
            }

        case .linking(let embedLink):
            WalletLinkingWebView(
                embedLink: embedLink,
                onBack: { step = .linkBaoKim },
                onLinked: { step = .rules }
            )

        case .rules:
            WalletRulesView(
                onStart: { appState.route(status: UserStatus.active.rawValue, phone: nil) },
                onAdjustLimit: { step = .pinLimit }
            )

        case .pinLimit:
            PinLimitView(onBack: { step = .rules })
        }
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
                .hidesSystemNavigationBar()
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                        .hidesSystemNavigationBar()
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
