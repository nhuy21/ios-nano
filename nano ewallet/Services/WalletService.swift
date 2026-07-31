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
}
