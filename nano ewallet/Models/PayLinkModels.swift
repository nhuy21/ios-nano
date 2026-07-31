//
//  PayLinkModels.swift
//  nano ewallet
//
//  Mirror be/src/modules/pay-link/dto/pay-link.dto.ts + PayLinkApi.kt.
//

import Foundation

enum PayLinkKind: String, Decodable {
    case wallet = "WALLET"
    case bank = "BANK"
}

/// `POST pay-links` — amount/note optional, người trả tự nhập nếu bỏ trống.
struct CreatePayLinkRequest: Encodable {
    var amount: Int?
    var note: String?
    var accNo: String?
    var bankNo: String?
}

struct CreatePayLinkResult: Decodable {
    let reqToken: String
    let url: String
}

/// `GET pay-links/:reqToken` — dữ liệu CHUẨN từ server, app không tin query của URL.
struct PayLinkInfo: Decodable {
    let reqToken: String
    let payKind: PayLinkKind
    let benUsername: String?
    let accNo: String?
    let bankNo: String?
    let bankShortName: String?
    let accName: String?
    let amount: String?
    let note: String?
    let status: String

    var amountValue: Int? { amount.flatMap { Int($0) } }
}
