//
//  BeneficiaryModels.swift
//  nano ewallet
//
//  Mirror be/src/modules/beneficiary — danh bạ người thụ hưởng do user tự thêm.
//

import Foundation

enum BeneficiaryType: String, Codable {
    /// Chuyển ra ngân hàng ngoài — cần bankNo/accNo/accName.
    case bankAccount = "BANK_ACCOUNT"
    /// Chuyển nội bộ tới ví Nano Wallet khác — cần benUsername.
    case wallet = "WALLET"
}

struct Beneficiary: Decodable, Identifiable, Hashable {
    let id: String
    let type: BeneficiaryType
    let bankNo: String?
    let accNo: String?
    let accName: String?
    let benUsername: String?
    let nickname: String?
    let useCount: Int
    let lastUsedAt: String?
    let createdAt: String?

    /// Tên hiển thị ưu tiên: nickname > accName > benUsername.
    var displayName: String {
        nickname ?? accName ?? benUsername ?? "Không tên"
    }
}

struct CreateBeneficiaryRequest: Encodable {
    var type: BeneficiaryType = .bankAccount
    var bankNo: String?
    var accNo: String?
    var accName: String?
    var benUsername: String?
    var nickname: String?
}

struct UpdateBeneficiaryRequest: Encodable {
    let nickname: String?
}

/// Số điện thoại gửi đi để đối chiếu. Tối đa 200 số mỗi lượt (BE khai `ArrayMaxSize`).
///
/// `description` ghi đè để log KHÔNG BAO GIỜ in ra số điện thoại — đây là dữ liệu của người
/// thứ ba, họ không đồng ý gì với app này.
struct MatchContactsRequest: Encodable, CustomStringConvertible {
    let phones: [String]

    var description: String { "MatchContactsRequest(\(phones.count) số)" }
}

/// Một người trong danh bạ máy đang có ví nano hoạt động.
///
/// `description` ghi đè vì lý do y hệt `MatchContactsRequest`.
struct MatchedFriend: Decodable, Identifiable, CustomStringConvertible {
    /// Dạng `0xxxxxxxxx` — BE đã chuẩn hoá.
    let phone: String
    /// Tên chủ ví theo hồ sơ nano (không phải tên trong danh bạ máy).
    let accName: String
    /// Số ví, dùng để chuyển tiền.
    let benUsername: String

    var id: String { benUsername }

    var description: String { "MatchedFriend(\(benUsername))" }
}
