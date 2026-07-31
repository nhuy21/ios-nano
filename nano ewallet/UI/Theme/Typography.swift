//
//  Typography.swift
//  nano ewallet
//
//  Mirror ui/theme/Type.kt. sp → pt tỉ lệ 1:1.
//

import SwiftUI

/// Font của app. Cần copy 5 file BeVietnamPro + Baloo2 từ
/// `flash-wallet/app/src/main/res/font/` vào project và khai `UIAppFonts` trong Info.plist.
///
/// Trước khi có file font, các hàm dưới tự fallback về system font nên UI vẫn chạy.
enum AppFont {

    // MARK: Be Vietnam Pro — font chính

    static func beVietnamPro(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(beVietnamProName(weight), size: size)
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
        let name: String
        switch weight {
        case .medium: return .custom("Baloo2-Medium", size: size)
        case .semibold: name = "Baloo2-SemiBold"
        case .heavy, .black: name = "Baloo2-ExtraBold"
        default: name = "Baloo2-Bold"
        }
        return .custom(name, size: size)
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
