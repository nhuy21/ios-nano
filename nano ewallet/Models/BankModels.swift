//
//  BankModels.swift
//  nano ewallet
//
//  Mirror be/src/modules/bank — GET banks.
//

import Foundation

struct Bank: Decodable, Identifiable, Hashable {
    let id: Int
    let bin: String
    let shortName: String
    let name: String
    let logoUrl: String?
    let isVietQr: Bool
    let isNapas: Bool
    let isDisburse: Bool
    let brandColor: String?
    let isActive: Bool
}
