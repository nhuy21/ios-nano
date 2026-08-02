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
}

/// Body `{}` cho các endpoint POST không cần tham số.
private struct EmptyBody: Encodable {}
