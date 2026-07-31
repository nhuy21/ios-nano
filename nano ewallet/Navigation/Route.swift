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

    /// Chuyển khoản ngân hàng — nhập tay (chọn bank + STK) hoặc đã có sẵn từ danh bạ.
    case bankTransfer(draft: BankTransferDraft?)
    /// Chuyển ví-ví — nhập tay (username) hoặc đã có sẵn từ danh bạ.
    case walletTransfer(draft: WalletTransferDraft?)
    /// Màn nhập số tiền/nội dung — người nhận đã xác thực xong ở màn trước.
    case bankTransferAmount(BankTransferDraft)
    case walletTransferAmount(WalletTransferDraft)
    /// Màn kết quả — giao dịch đã thực thi xong (SUCCESS hoặc PENDING đối soát).
    case transferSuccess(TransferSuccessInfo)
    /// Cuộc thoại xin tiền với 1 người (mirror ConversationScreen.kt) — key theo bkUsername.
    case conversation(otherName: String, otherBkUsername: String)
    /// "QR của tôi" — mã nhận tiền tự build EMVCo, mirror ReceiveQrScreen.kt. Quét QR
    /// (camera) KHÔNG nằm trong HomeRoute — mở riêng qua QrScanNavigationView
    /// (fullScreenCover ở MainTabView), vì Android cũng trượt dọc lên như modal riêng.
    case receiveQr
}

/// Dữ liệu hiển thị màn kết quả — gộp chung cho cả 2 luồng bank/wallet.
struct TransferSuccessInfo: Hashable {
    var amount: Int64
    var recipientName: String
    var recipientDetail: String
    var noteLabel: String
    var note: String
}

/// Người nhận ngân hàng đã xác thực (hoặc đang chờ xác thực) — cầu nối giữa
/// BankTransferView -> TransferAmountView, mirror `TransferDraft` bên Android.
struct BankTransferDraft: Hashable {
    var bin: String
    var bankName: String
    var accNo: String
    var accType: Int
    var holderName: String
    /// QR "động" cố định sẵn số tiền/nội dung -> field tương ứng bị khoá, không cho sửa.
    var prefillAmount: Int?
    var prefillContent: String?
    var amountEditable: Bool = true
    var contentEditable: Bool = true
    /// Vào từ Pay Link (`reqToken`) -> gọi `PayLinkService.consume` sau khi giao dịch SUCCESS.
    var payLinkToken: String?
}

/// Người nhận ví-ví đã xác thực — cầu nối giữa WalletTransferView -> WalletTransferAmountView.
struct WalletTransferDraft: Hashable {
    var username: String
    var holderName: String
    var payLinkToken: String?
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
