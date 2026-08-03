//
//  Color.swift
//  nano ewallet
//
//  Giá trị lấy đúng từ ui/theme/Color.kt bên Android.
//

import SwiftUI

extension Color {
    /// `nonisolated` vì project bật `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: không
    /// có nó, init thuần tính toán này bị suy ra `@MainActor` và không gọi được từ
    /// context nonisolated (vd hàm helper dựng màu trong BankTransferView).
    nonisolated init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Parse "#RRGGBB" từ `brandColor` do BE trả (logo/thẻ ngân hàng).
    nonisolated init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

/// Bảng màu app. Theme là **light-only** (Android không có dark scheme).
enum AppColor {

    // MARK: Ví nano — xanh lá, màu chủ đạo
    // Tên biến bên Android là `PayCoral` (giữ từ thời rebrand coral → green), ở đây
    // đặt tên theo màu thật để tránh nhầm.

    /// #00A85E — primary
    static let brand = Color(hex: 0x00A85E)
    /// #E6F7EE
    static let brandSoft = Color(hex: 0xE6F7EE)
    /// #111C17 — text chính
    static let payInk = Color(hex: 0x111C17)
    /// #8A9990 — text phụ
    static let payMuted = Color(hex: 0x8A9990)
    /// #AAB7B0 — placeholder
    static let payPlaceholder = Color(hex: 0xAAB7B0)
    /// #E5E7EB — viền input
    static let payInputBorder = Color(hex: 0xE5E7EB)
    /// #DEE8E3
    static let payDivider = Color(hex: 0xDEE8E3)
    /// #EAF9F1 — gradient nền trên
    static let payBgTop = Color(hex: 0xEAF9F1)
    /// #D6F2E4 — gradient nền dưới
    static let payBgBottom = Color(hex: 0xD6F2E4)

    // MARK: Neutral

    /// #0B0B0C
    static let ink = Color(hex: 0x0B0B0C)
    static let bgWhite = Color(hex: 0xFFFFFF)
    /// #F6F6F7
    static let bgSoft = Color(hex: 0xF6F6F7)
    /// #F4F4F6
    static let bgLight = Color(hex: 0xF4F4F6)
    /// #ECECEE — đường kẻ
    static let line = Color(hex: 0xECECEE)
    /// #93939B
    static let muted = Color(hex: 0x93939B)

    // MARK: Trạng thái

    /// #19B36B
    static let ok = Color(hex: 0x19B36B)
    static let okSoft = Color(hex: 0xE6F9F0)
    /// #B8860B
    static let warn = Color(hex: 0xB8860B)
    static let warnSoft = Color(hex: 0xFFF8E1)
    /// #E53935
    static let error = Color(hex: 0xE53935)
    static let errorSoft = Color(hex: 0xFFEBEE)

    // MARK: Accent tím

    /// #7C5CFF
    static let accent = Color(hex: 0x7C5CFF)
    static let accentSoft = Color(hex: 0xEFEBFF)

    // MARK: Xanh dương — thẻ ngân hàng / biểu đồ

    /// #1A4DB8
    static let primary = Color(hex: 0x1A4DB8)
    static let primaryDark = Color(hex: 0x0D2870)
    static let primaryDeep = Color(hex: 0x060E2E)
    static let primaryLight = Color(hex: 0x2E63D4)
    static let primarySoft = Color(hex: 0xE8EEFB)

    // MARK: Tiền vào / ra

    static let greenIncome = Color(hex: 0x19B36B)
    static let blueExpense = Color(hex: 0x1A4DB8)
}
