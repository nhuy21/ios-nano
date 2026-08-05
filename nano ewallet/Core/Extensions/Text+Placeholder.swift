//
//  Text+Placeholder.swift
//  nano ewallet
//
//  Placeholder cho `TextField` với màu/font của app.
//
//  `TextField("Nhập...", text:)` để nguyên thì placeholder lấy màu của HỆ THỐNG — xám rất
//  nhạt, trên nền trắng của các ô input trong app gần như chìm hẳn. Chỉ `prompt:` mới đổi
//  được màu placeholder; `.foregroundStyle` bên ngoài chỉ ăn vào chữ người dùng gõ.
//
//  Android tô màu placeholder rõ ràng ở từng ô (`GrayLabel` = #8A9990 = `payMuted`), nên
//  đây là màu mặc định ở đây.
//

import SwiftUI

extension Text {
    /// Placeholder chuẩn của app — dùng cho tham số `prompt:` của `TextField`.
    ///
    ///     TextField("", text: $query, prompt: .appPlaceholder("Tìm ngân hàng..."))
    static func appPlaceholder(
        _ text: String,
        size: CGFloat = 14,
        color: Color = AppColor.payMuted
    ) -> Text {
        Text(text)
            .font(AppFont.beVietnamPro(size))
            .foregroundColor(color)
    }
}
