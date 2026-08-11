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

    /// Response 2xx nhưng KHÔNG có field `data`. Tách riêng khỏi `.decoding` vì có
    /// endpoint coi đây là hợp lệ: interceptor của BE loại bỏ `data` khi giá trị null,
    /// nên luồng giao dịch phải hiểu là "đã xong, không kèm chi tiết" thay vì lỗi
    /// (xem `TransferService.performTransfer`).
    case missingData(path: String)

    /// Chưa đăng nhập / không có token.
    case unauthenticated

    /// Lỗi khác (timeout, DNS...).
    case unknown(String)

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case .offline:
            return "Không có kết nối internet"
        case .server(let code, let message):
            // BE (và Bảo Kim phía sau) đôi khi trả message trống rỗng kiểu "Error"/"Bad
            // Request" — hiện nguyên xi thì người dùng không biết chuyện gì, mà mình cũng
            // không lần được lỗi từ ảnh chụp màn hình họ gửi. Kèm mã HTTP cho những message
            // vô nghĩa như vậy; message có nội dung thật thì giữ nguyên, không làm rối.
            let trimmed = message.trimmingCharacters(in: .whitespaces)
            let uninformative = ["error", "bad request", "internal server error", "forbidden", ""]
            if uninformative.contains(trimmed.lowercased()) {
                return "Yêu cầu không hợp lệ (HTTP \(code))"
            }
            return message
        case .decoding(let detail):
            return "Dữ liệu trả về không đúng định dạng (\(detail))"
        case .missingData(let path):
            return "Dữ liệu trả về không đúng định dạng (thiếu `data` @ \(path))"
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
