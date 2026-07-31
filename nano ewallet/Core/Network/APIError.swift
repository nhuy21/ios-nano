//
//  APIError.swift
//  nano ewallet
//

import Foundation

/// Lỗi từ tầng network. `message` luôn là tiếng Việt, hiển thị trực tiếp cho user được.
enum APIError: LocalizedError, Equatable {

    /// Không có kết nối internet — mirror `NetworkConnectionInterceptor` bên Android.
    case offline

    /// BE trả lỗi kèm message (4xx/5xx). `statusCode` để phân biệt 401.
    case server(statusCode: Int, message: String)

    /// Response 2xx nhưng thiếu `data` hoặc decode thất bại.
    case decoding(String)

    /// Chưa đăng nhập / không có token.
    case unauthenticated

    /// Lỗi khác (timeout, DNS...).
    case unknown(String)

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case .offline:
            return "Không có kết nối internet"
        case .server(_, let message):
            return message
        case .decoding(let detail):
            return "Dữ liệu trả về không đúng định dạng (\(detail))"
        case .unauthenticated:
            return "Chưa đăng nhập, vui lòng đăng nhập lại"
        case .unknown(let detail):
            return detail
        }
    }

    var isUnauthorized: Bool {
        if case .server(let code, _) = self { return code == 401 }
        return false
    }
}
