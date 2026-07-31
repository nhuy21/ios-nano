//
//  AppConfig.swift
//  nano ewallet
//

import Foundation
import UIKit

/// Cấu hình lấy từ Info.plist (giá trị bơm vào từ .env qua Config.xcconfig).
/// Xem Scripts/env-to-xcconfig.sh và README.
enum AppConfig {

    /// Base URL của backend — **đã bao gồm `/api/v1`**.
    /// Endpoint chỉ truyền path ngắn: `client.get("wallet/me")`, KHÔNG viết `/api/v1/wallet/me`.
    static let baseURL: URL = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "BE_BASE_URL") as? String,
              !raw.isEmpty,
              let url = URL(string: raw) else {
            fatalError(
                """
                Thiếu BE_BASE_URL. Kiểm tra:
                  1. File .env có dòng BE_BASE_URL=https://nano.casso.dev/api/v1
                  2. Đã chạy Scripts/env-to-xcconfig.sh để sinh Config.xcconfig
                  3. Config.xcconfig đã gán cho project (Project > Info > Configurations)
                """
            )
        }
        return url
    }()

    /// Tên thiết bị gửi kèm login/verify-otp — mirror `"${Build.MANUFACTURER} ${Build.MODEL}"`
    /// bên Android. iOS không cho đọc model thương mại (vd "iPhone 15 Pro"), nên dùng
    /// tên user đặt cho máy, đã đủ để phân biệt thiết bị trong màn quản lý phiên.
    @MainActor
    static var deviceName: String {
        UIDevice.current.name
    }
}
