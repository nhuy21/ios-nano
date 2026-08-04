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
    /// Hộp thư thông báo — mirror NotificationScreen.kt.
    case notifications
    /// Nút "Liên kết" trên balance card — Android mở thẳng màn ngân hàng liên kết
    /// (Routes.LINKED_BANKS), không phải dialog "sắp có".
    case linkedBanks

    /// Chuyển khoản ngân hàng — MỘT màn gộp người nhận + số tiền + nội dung.
    /// `draft == nil`: nhập tay (chọn bank + gõ STK). `draft != nil`: người nhận đã
    /// có sẵn (danh bạ / QR / pay link) — thẻ khoá, có thể kèm số tiền/nội dung cố định.
    case bankTransfer(draft: BankTransferDraft?)
    /// Chuyển ví-ví — nhập tay (username) hoặc đã có sẵn từ danh bạ.
    case walletTransfer(draft: WalletTransferDraft?)
    /// Màn nhập số tiền/nội dung (luồng ví) — người nhận đã xác thực xong ở màn trước.
    case walletTransferAmount(WalletTransferDraft)
    /// Màn kết quả — giao dịch đã thực thi xong (SUCCESS hoặc PENDING đối soát).
    case transferSuccess(TransferSuccessInfo)
    /// Cuộc thoại xin tiền với 1 người (mirror ConversationScreen.kt) — key theo bkUsername.
    case conversation(otherName: String, otherBkUsername: String)
    /// "QR của tôi" — mã nhận tiền tự build EMVCo, mirror ReceiveQrScreen.kt. Quét QR
    /// (camera) KHÔNG nằm trong HomeRoute — mở riêng qua QrScanNavigationView
    /// (fullScreenCover ở MainTabView), vì Android cũng trượt dọc lên như modal riêng.
    case receiveQr
    /// Rút tiền về TK ngân hàng — mirror WithdrawScreen.kt. "Nạp tiền" không có route
    /// riêng, chỉ mở lại `.receiveQr` (Android cũng vậy — user tự chuyển khoản vào VA).
    case withdraw
}

/// Dữ liệu hiển thị màn kết quả — gộp chung cho cả 2 luồng bank/wallet (Android tách
/// làm 2 màn riêng). Gộp được, nhưng phải mang đủ trường riêng của từng luồng chứ
/// không nhồi vào một chuỗi rồi đoán ngược lại.
struct TransferSuccessInfo: Hashable {
    enum Kind: Hashable {
        case wallet
        case bank
    }

    var kind: Kind
    var amount: Int64
    var recipientName: String
    /// Tên ngân hàng nhận — chỉ luồng `.bank`.
    var bankName: String?
    /// Số tài khoản (bank) hoặc username ví.
    var accountNumber: String
    var noteLabel: String
    var note: String
    /// Mã giao dịch thật từ Bảo Kim (`bk_trans_id`/`trans_id`). `nil` khi BE không trả
    /// về — biên lai hiện "—". KHÔNG sinh mã giả: biên lai là thứ người dùng lưu lại
    /// và gửi đi làm bằng chứng, in một mã bịa lên đó còn tệ hơn để trống.
    var transactionCode: String?
    /// Thời gian xử lý thật (giây), đo quanh lời gọi API. `nil` thì ẩn hẳn dòng
    /// "hoàn thành trong X giây" thay vì bịa một con số.
    var elapsedSeconds: Double?
    /// Bảo Kim trả `status == "PENDING"` (code 99) — tiền đã trừ nhưng ngân hàng chưa
    /// chốt. Phải hiện "đang xử lý", không được báo "thành công".
    var isProcessing: Bool = false
    /// Phí giao dịch thật (`fee_amount`). `nil` thì ẩn dòng phí.
    var feeAmount: Int64?
}

/// Người nhận ngân hàng đã xác thực sẵn (danh bạ / QR / pay link) truyền vào
/// BankTransferView để khoá thẻ người nhận, mirror `TransferDraft` bên Android.
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

/// Người nhận ví-ví. `nil` ở `HomeRoute.walletTransfer` = chế độ nhập tay; có giá trị =
/// đã xác thực từ danh bạ/QR/OneTouch/giọng nói/pay-link nên `WalletTransferAmountView`
/// khoá phần chọn người nhận lại.
struct WalletTransferDraft: Hashable {
    var username: String
    var holderName: String
    var payLinkToken: String?
    /// Số tiền bóc được từ nội dung dán (OneTouch) — điền sẵn nhưng vẫn cho sửa.
    var prefillAmount: Int64?
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
