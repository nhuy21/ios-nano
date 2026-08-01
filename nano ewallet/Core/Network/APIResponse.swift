//
//  APIResponse.swift
//  nano ewallet
//

import Foundation

/// Envelope BE bọc quanh mọi response: `{ success, statusCode, message, data }`.
/// Xem be/src/format-response/.
nonisolated struct APIResponse<T: Decodable>: Decodable {
    let success: Bool?
    let statusCode: Int?
    let message: BEMessage?
    let data: T?
}

/// Response không có `data` (register, logout, resend-otp...).
nonisolated struct APIEmptyResponse: Decodable {
    let success: Bool?
    let statusCode: Int?
    let message: BEMessage?
}

/// `message` của BE có thể là **string** hoặc **array of string** — NestJS ValidationPipe
/// trả array khi có nhiều lỗi validate. Bọc lại để decode được cả hai dạng.
nonisolated enum BEMessage: Decodable {
    case single(String)
    case multiple([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .single(text)
        } else if let list = try? container.decode([String].self) {
            self = .multiple(list)
        } else {
            self = .multiple([])
        }
    }

    /// Chuỗi hiển thị cho user — nhiều lỗi thì lấy lỗi đầu (giống Android chỉ hiện 1 message).
    var text: String? {
        switch self {
        case .single(let value):
            return value.isEmpty ? nil : value
        case .multiple(let values):
            return values.first
        }
    }
}
