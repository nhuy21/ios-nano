//
//  WalletService.swift
//  nano ewallet
//

import Foundation

/// Gọi API ví — mirror phần `getMyWallet()` trong EkycApi.kt.
enum WalletService {
    /// `GET wallet/me`
    static func getMyWallet() async throws -> WalletInfo {
        try await APIClient.shared.request(.get, "wallet/me", auth: true, as: WalletInfo.self)
    }

    /// `POST wallet/check-wallet-info` — đối soát ví trực tiếp từ Bảo Kim. Dùng để xác
    /// nhận webhook đã kích hoạt ví (tạo bản ghi wallets) sau khi user xác nhận OTP xong
    /// trên WebView liên kết. Ném lỗi nếu webhook chưa kịp xử lý — bên gọi tự thử lại.
    static func checkWalletInfoFromBaoKim() async throws {
        try await APIClient.shared.requestVoid(
            .post, "wallet/check-wallet-info", body: EmptyBody(), auth: true, slow: true
        )
    }

    /// `POST wallet/unlink` — huỷ liên kết ví Bảo Kim.
    ///
    /// Áp dụng cho MỌI ví — cả ví đồng bộ từ ví có sẵn lẫn ví mở mới qua eKYC (hồ sơ eKYC phía
    /// Bảo Kim vẫn còn nguyên nên liên kết lại được). Ví và số dư bên Bảo Kim giữ nguyên, người dùng liên kết lại được sau. BE tự
    /// xác thực `password` (6 chữ số) nên app chỉ cần forward.
    static func unlinkWallet(password: String) async throws {
        try await APIClient.shared.requestVoid(
            .post, "wallet/unlink", body: UnlinkWalletRequest(password: password), auth: true
        )
    }
}

/// Body `{}` cho các endpoint POST không cần tham số.
private struct EmptyBody: Encodable {}

private struct UnlinkWalletRequest: Encodable {
    let password: String
}
