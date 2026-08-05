//
//  ThousandsSeparated.swift
//  nano ewallet
//
//  Format số tiền có dấu chấm phân nghìn NGAY TRONG LÚC GÕ.
//
//  Không dùng `Binding` tính toán (get trả chuỗi đã format) được: khi ô đang được focus,
//  SwiftUI giữ bộ đệm text riêng và không đọc lại `get`, nên chữ hiển thị vẫn là số thô.
//  Cách chạy đúng là bind thẳng vào @State rồi ghi đè lại giá trị trong `onChange`.
//

import SwiftUI

extension View {
    /// Gắn vào ô nhập tiền: mỗi lần text đổi thì lọc lấy chữ số, cắt theo `maxDigits`
    /// rồi ghi lại dạng "1.234.567".
    func thousandsSeparated(_ text: Binding<String>, maxDigits: Int = 9) -> some View {
        onChangeCompat(of: text.wrappedValue) { _, newValue in
            let digits = String(newValue.filter(\.isNumber).prefix(maxDigits))
            let formatted = digits.isEmpty ? "" : (Int(digits) ?? 0).vndGrouped
            if formatted != newValue { text.wrappedValue = formatted }
        }
    }
}

extension String {
    /// Chữ số thuần của chuỗi tiền đã format — dùng để lấy giá trị thật khi gửi lên API.
    var amountDigits: String { filter(\.isNumber) }

    var amountValue: Int64 { Int64(amountDigits) ?? 0 }
}
