//
//  NumericKeyboardToolbar.swift
//  nano ewallet
//

import SwiftUI

/// Bàn phím số (`.numberPad`/`.phonePad`) trên iOS KHÔNG có hàng phím Return/Next —
/// đây là giới hạn hệ thống, khác bàn phím chữ. Modifier này thêm 1 thanh nhỏ ngay
/// trên bàn phím với nút điều hướng (mirror trải nghiệm `imeAction` bên Android:
/// "Tiếp theo" nhảy field kế tiếp, "Xong" ẩn bàn phím/submit).
struct NumericKeyboardToolbar: ViewModifier {
    let label: String
    let action: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(label, action: action)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColor.brand)
            }
        }
    }
}

extension View {
    /// `label`: "Tiếp theo" khi còn field sau, "Xong" khi là field cuối cùng.
    func numericKeyboardToolbar(label: String = "Tiếp theo", action: @escaping () -> Void) -> some View {
        modifier(NumericKeyboardToolbar(label: label, action: action))
    }
}
