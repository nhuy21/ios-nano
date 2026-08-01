//
//  String+Initials.swift
//  nano ewallet
//
//  Mirror initialsOf() lặp lại ở ConversationScreen.kt/BankTransferScreen.kt/
//  ContactsScreen.kt — avatar chữ cái: ≥2 từ thì lấy chữ đầu của TỪ ĐẦU + TỪ CUỐI
//  (vd "Đặng Ngọc Khiêu" -> "ĐK"), chỉ 1 từ thì lấy 2 ký tự đầu của từ đó.
//

import Foundation

extension String {
    var nameInitials: String {
        let parts = trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .filter { !$0.isEmpty }
        guard let first = parts.first else { return "?" }
        if parts.count >= 2, let last = parts.last {
            return "\(first.prefix(1))\(last.prefix(1))".uppercased()
        }
        return String(first.prefix(2)).uppercased()
    }
}
