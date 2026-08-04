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
        /// Giới thiệu các bước eKYC trước khi mở SDK.
        case cccdScan
        /// Xem lại thông tin chip + bổ sung + chọn tài khoản nhận tiền.
        case kycReview
        /// Đang gọi create-agreement (Bảo Kim cần 2-5 phút dựng ví).
        case preparingAgreement
        /// Ký thoả thuận mở ví.
        case agreement(embedLink: String)
        case linkBaoKim
        /// Bảo Kim từ chối ngay lúc gửi yêu cầu liên kết, chưa tới bước OTP.
        case linkFailed(message: String)
        /// Đang nhúng trang OTP của Bảo Kim.
        case linking(embedLink: String)
        /// Ví đã đồng bộ xong — đọc quy tắc giao dịch một lần rồi vào Home.
        case rules
        case pinLimit
    }

    @State private var step: Step = .choice
    /// Không mở được SDK eKYC (phiên hỏng, không tìm được màn để trình bày).
    @State private var ekycError: String?

    var body: some View {
        content
            .alert(
                "Không mở được xác thực định danh",
                isPresented: Binding(get: { ekycError != nil }, set: { if !$0 { ekycError = nil } })
            ) {
                Button("Đã hiểu", role: .cancel) { ekycError = nil }
            } message: {
                Text(ekycError ?? "")
            }
    }

    /// Hồ sơ đã sạch lỗi — xin thoả thuận mở ví. BE không tự thử lại nên phải poll ở đây.
    private func prepareAgreement() {
        step = .preparingAgreement
        Task {
            do {
                let embedLink = try await OnboardingService.createAgreementAndPoll()
                step = .agreement(embedLink: embedLink)
            } catch let error as APIError {
                ekycError = error.message
                step = .kycReview
            } catch {
                ekycError = "Không tạo được thoả thuận mở ví, vui lòng thử lại"
                step = .kycReview
            }
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
                    onCreateNewWallet: { step = .cccdScan }
                )
                .hidesSystemNavigationBar()
            }

        case .cccdScan:
            NavigationStack {
                CccdScanView(
                    onBack: { step = .choice },
                    onStartEkyc: {
                        Task {
                            await EkycLauncher.start(
                                onCompleted: { _ in step = .kycReview },
                                onFailed: { message in ekycError = message }
                            )
                        }
                    }
                )
                .hidesSystemNavigationBar()
            }

        case .kycReview:
            KycReviewView(
                onBack: { step = .cccdScan },
                onSubmitted: { prepareAgreement() }
            )

        case .preparingAgreement:
            OnboardingLoadingView(message: "Đang chuẩn bị thoả thuận mở ví...")

        case .agreement(let embedLink):
            // Trang của Bảo Kim tự có nút đồng ý, không có URL callback báo về nên không
            // biết chính xác lúc nào user bấm xong. Cả hai lối ra đều dẫn tới màn quy tắc:
            // "Hoàn tất" có đối soát ví trước, thoát ngang thì không.
            AgreementWebView(
                embedLink: embedLink,
                onBack: { step = .rules },
                onLinked: { step = .rules }
            )

        case .linkBaoKim:
            NavigationStack {
                WalletLinkBaoKimView(
                    onBack: { step = .choice },
                    onSubmit: { link in step = .linking(embedLink: link) },
                    onError: { message in step = .linkFailed(message: message) }
                )
                .hidesSystemNavigationBar()
            }

        case .linkFailed(let message):
            WalletLinkErrorView(
                message: message,
                // "Thử lại" quay về form với thông tin đã nhập — mấy lỗi này thường phải
                // sửa số ví hoặc tên cho khớp thông tin đăng ký bên Bảo Kim.
                onRetry: { step = .linkBaoKim },
                onLogout: { Task { await appState.logout() } }
            )

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
                    // Token/khoá sinh trắc gắn với TÀI KHOẢN vừa rời đi. Không xoá thì sau khi
                    // đăng nhập tài khoản khác, WelcomeBack vẫn thấy "đã bật Face ID" và quét mặt
                    // sẽ đăng nhập lại vào tài khoản CŨ — sai hoàn toàn ý người dùng.
                    BiometricTokenStore.remove()
                    BiometricKeyStore.deleteKey()
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
