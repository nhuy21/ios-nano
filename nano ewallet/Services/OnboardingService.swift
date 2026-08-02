//
//  OnboardingService.swift
//  nano ewallet
//
//  Mirror `EkycApi.walletLinking` — luồng đồng bộ ví Bảo Kim có sẵn (không qua eKYC).
//

import Foundation

struct WalletLinkingRequest: Encodable {
    let username: String
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case username
        case fullName = "full_name"
    }
}

/// `embed_link` là URL nhúng WebView để user xác nhận OTP Bảo Kim gửi về số điện thoại
/// đã đăng ký ví.
struct WalletLinkingResult: Decodable {
    let phoneNumber: String?
    let fullName: String?
    let embedLink: String

    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phone_number"
        case fullName = "full_name"
        case embedLink = "embed_link"
    }
}

enum OnboardingService {
    /// `POST onboarding/wallet-linking`
    ///
    /// Bảo Kim có thể từ chối NGAY ở đây, chưa cần tới OTP: ví không tồn tại, ví không
    /// hoạt động, số điện thoại đã liên kết, tên không khớp thông tin đăng ký ví.
    static func linkBaoKimWallet(username: String, fullName: String) async throws -> WalletLinkingResult {
        try await APIClient.shared.request(
            .post, "onboarding/wallet-linking",
            body: WalletLinkingRequest(username: username, fullName: fullName),
            auth: true, slow: true, as: WalletLinkingResult.self
        )
    }
}
