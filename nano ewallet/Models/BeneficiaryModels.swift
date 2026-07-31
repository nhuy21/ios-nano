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
