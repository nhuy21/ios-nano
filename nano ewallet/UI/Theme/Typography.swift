//
//  Typography.swift
//  nano ewallet
//
//  Mirror ui/theme/Type.kt. sp → pt tỉ lệ 1:1.
//

import SwiftUI
import UIKit

/// Font của app. Cần copy 5 file BeVietnamPro + Baloo2 từ
/// `flash-wallet/app/src/main/res/font/` vào project và khai `UIAppFonts` trong Info.plist.
///
/// Khi CHƯA nhúng file font: `.custom()` với tên không tồn tại rơi về system font nhưng
/// MẤT LUÔN weight -> chữ đáng lẽ bold hiện ra mỏng như regular ở khắp app. Nên phải tự
/// kiểm tra font có nạp được không, không thì dùng `.system(size:weight:)` để giữ đúng độ đậm.
enum AppFont {

    /// Cache kết quả tra font — `UIFont(name:size:)` gọi mỗi lần dựng Text sẽ tốn.
    private static var availability: [String: Bool] = [:]

    private static func isAvailable(_ name: String) -> Bool {
        if let cached = availability[name] { return cached }
        let exists = UIFont(name: name, size: 12) != nil
        availability[name] = exists
        return exists
    }

    private static func font(_ name: String, _ size: CGFloat, _ weight: Font.Weight) -> Font {
        isAvailable(name) ? .custom(name, size: size) : .system(size: size, weight: weight)
    }

    // MARK: Be Vietnam Pro — font chính

    static func beVietnamPro(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        font(beVietnamProName(weight), size, weight)
    }

    private static func beVietnamProName(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium: return "BeVietnamPro-Medium"
        case .semibold: return "BeVietnamPro-SemiBold"
        case .bold: return "BeVietnamPro-Bold"
        case .heavy, .black: return "BeVietnamPro-ExtraBold"
        default: return "BeVietnamPro-Regular"
        }
    }

    // MARK: Baloo2 — chỉ dùng cho số dư và vài tiêu đề

    static func baloo2(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        // Baloo2 bên Android là variable font, iOS cần file static theo weight.
        // baloo2.ttf là VARIABLE font, chỉ expose đúng 1 face "Baloo2-Regular" — không
        // có Baloo2-Bold/SemiBold/... như bên Android. Nên nạp face đó rồi áp weight
        // lên trên để iOS tự chọn instance theo trục weight.
        let effective: Font.Weight = (weight == .regular) ? .bold : weight
        let name = "Baloo2-Regular"
        return isAvailable(name)
            ? .custom(name, size: size).weight(effective)
            : .system(size: size, weight: effective)
    }
}

/// Type scale lấy đúng từ `Type.kt`.
extension Font {
    static let appDisplayLarge = AppFont.beVietnamPro(36, .bold)
    static let appHeadlineLarge = AppFont.beVietnamPro(28, .bold)
    static let appHeadlineMedium = AppFont.beVietnamPro(22, .semibold)
    static let appTitleLarge = AppFont.beVietnamPro(18, .bold)
    static let appTitleMedium = AppFont.beVietnamPro(16, .semibold)
    static let appTitleSmall = AppFont.beVietnamPro(14, .medium)
    static let appBodyLarge = AppFont.beVietnamPro(16)
    static let appBodyMedium = AppFont.beVietnamPro(14)
    static let appBodySmall = AppFont.beVietnamPro(12)
    static let appLabelLarge = AppFont.beVietnamPro(14, .medium)
    static let appLabelSmall = AppFont.beVietnamPro(11, .medium)
}
