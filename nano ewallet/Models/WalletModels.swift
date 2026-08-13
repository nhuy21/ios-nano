//
//  WalletModels.swift
//  nano ewallet
//
//  DTO mirror be/src/modules/wallet (GET wallet/me). BIGINT ở BE trả về dạng
//  String (driver `pg` serialize int8 thành string, tránh mất precision qua JSON)
//  — cachedBalance/limitPIN/limitFace đều String, KHÔNG phải Int.
//

import Foundation

struct WalletInfo: Decodable {
    let bkUsername: String?
    let qrPath: String?
    let vaNumber: String?
    let vaBankNo: String?
    let cachedBalance: String
    let status: String
    let limitPIN: String
    let limitFace: String
    let bankNo: String?
    let accNo: String?
    let accName: String?
    let bankLinkedAt: String?

    /// `cachedBalance` ép về Int64 để tính toán/hiển thị. `nil` nếu BE trả chuỗi bất thường.
    var balance: Int64? { Int64(cachedBalance) }
    var limitPinAmount: Int64? { Int64(limitPIN) }
    var limitFaceAmount: Int64? { Int64(limitFace) }

    var isActive: Bool { status == WalletStatus.active.rawValue }
}

enum WalletStatus: String {
    case inactive = "INACTIVE"
    case active = "ACTIVE"
}
