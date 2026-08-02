//
//  DateFormatter+App.swift
//  nano ewallet
//
//  Ngày giờ trong app phải hiển thị và tính toán GIỐNG NHAU trên mọi máy, không đổi
//  theo cài đặt Ngôn ngữ & Vùng của người dùng. `DateFormatter()` và `Calendar.current`
//  mặc định lấy lịch theo máy nên không đảm bảo điều đó — dùng 2 helper dưới đây thay thế.
//

import Foundation

extension DateFormatter {
    /// Formatter hiển thị ngày/giờ, ghim lịch Gregory. `vi_VN` để phần chữ (tên tháng,
    /// thứ) ra tiếng Việt ở những format có chữ.
    static func app(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }
}

extension Calendar {
    /// Lịch dùng cho mọi phép so ngày trong app (hôm nay / hôm qua / cùng ngày / cộng trừ ngày).
    static let app = Calendar(identifier: .gregorian)
}
