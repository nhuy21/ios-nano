//
//  Int+VND.swift
//  nano ewallet
//
//  Format số tiền kiểu Việt Nam: chấm phân nghìn, hậu tố "đ". Mirror cách hiển thị
//  tiền bên Android (vd "1.234.567 đ").
//

import Foundation

extension Int {
    /// Chỉ nhóm nghìn, KHÔNG kèm đơn vị — để nơi gọi tự ghép đơn vị riêng
    /// (số dư ở Home dùng "VNĐ" thay vì "đ").
    var vndGrouped: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        let number = NSNumber(value: abs(self))
        let formatted = formatter.string(from: number) ?? "\(abs(self))"
        return "\(self < 0 ? "-" : "")\(formatted)"
    }

    var vndFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        let number = NSNumber(value: abs(self))
        let formatted = formatter.string(from: number) ?? "\(abs(self))"
        return "\(self < 0 ? "-" : "")\(formatted) đ"
    }

    /// Có dấu +/- ở đầu, dùng cho dòng lịch sử giao dịch.
    var vndSigned: String {
        let sign = self >= 0 ? "+" : ""
        return "\(sign)\(vndFormatted)"
    }
}
