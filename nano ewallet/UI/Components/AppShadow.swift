//
//  AppShadow.swift
//  nano ewallet
//
//  Hai shadow lặp lại khắp các màn auth bên Android — gom lại 1 chỗ.
//

import SwiftUI

extension View {
    /// Shadow của input/card: Android `elevation 8.dp, r16, color 0x14784628` (nâu ấm 8%).
    func inputShadow() -> some View {
        shadow(color: Color(hex: 0x784628).opacity(0x14 / 255.0), radius: 8, x: 0, y: 3)
    }

    /// Shadow của nút chính: Android `elevation 8.3.dp, r16, color 0x5900A24A` (xanh 35%).
    func primaryButtonShadow() -> some View {
        shadow(color: Color(hex: 0x00A24A).opacity(0x59 / 255.0), radius: 8, x: 0, y: 4)
    }

    /// Shadow nhẹ cho nút back tròn: `elevation 4.dp, CircleShape, 0x14784628`.
    func circleButtonShadow() -> some View {
        shadow(color: Color(hex: 0x784628).opacity(0x14 / 255.0), radius: 4, x: 0, y: 2)
    }
}
