//
//  BankService.swift
//  nano ewallet
//

import Foundation
import Combine

struct LookupAccountRequest: Encodable {
    let bin: String
    let accountNumber: String
}

struct LookupAccountResponse: Decodable {
    let accountName: String
}

struct ParseQrRequest: Encodable {
    let rawQrData: String
}

struct ParseMessageRequest: Encodable {
    let rawMessage: String
}

/// Response `POST banks/parse-qr` — mirror bank.service.ts parseAndEnrich(). `amount`/`content`
/// null nghĩa là QR "động" (không cố định số tiền/nội dung) -> user được sửa (isXxxEditable).
struct ParsedQr: Decodable {
    let bankBin: String
    let bankName: String?
    let accountNumber: String
    let accountName: String
    let amount: Int?
    let content: String?
    let isAmountEditable: Bool
    let isContentEditable: Bool
}

enum BankService {
    /// `GET banks`
    static func list() async throws -> [Bank] {
        try await APIClient.shared.request(.get, "banks", auth: true, as: [Bank].self)
    }

    /// `POST banks/lookup` — tra cứu tên chủ tài khoản trước khi thêm vào danh bạ/chuyển khoản.
    static func lookupAccount(bin: String, accountNumber: String) async throws -> String {
        let response = try await APIClient.shared.request(
            .post, "banks/lookup",
            body: LookupAccountRequest(bin: bin, accountNumber: accountNumber),
            auth: true, as: LookupAccountResponse.self
        )
        return response.accountName
    }

    /// `POST banks/parse-qr` — verify CRC + bóc STK/ngân hàng/số tiền/nội dung từ QR VietQR
    /// (EMVCo), tự tra tên chủ TK luôn. Dùng cho màn quét QR trước khi vào TransferScreen.
    static func parseQr(rawQrData: String) async throws -> ParsedQr {
        try await APIClient.shared.request(
            .post, "banks/parse-qr", body: ParseQrRequest(rawQrData: rawQrData), auth: true, as: ParsedQr.self
        )
    }

    /// `POST banks/parse-message` — bóc ngân hàng/STK/số tiền/nội dung từ tin nhắn
    /// chuyển khoản dán vào (OneTouch). Trả cùng shape `ParsedQr` để dùng chung màn
    /// chuyển khoản với luồng quét QR.
    static func parseMessage(rawMessage: String) async throws -> ParsedQr {
        try await APIClient.shared.request(
            .post, "banks/parse-message",
            body: ParseMessageRequest(rawMessage: rawMessage), auth: true, slow: true, as: ParsedQr.self
        )
    }
}

/// Cache danh sách bank trong bộ nhớ — mirror `BankCache.kt` (danh sách gần như tĩnh,
/// không cần invalidate, chỉ tải 1 lần trong phiên).
@MainActor
final class BankCache: ObservableObject {
    static let shared = BankCache()
    private init() {}

    @Published private(set) var banks: [Bank] = []
    private var isLoading = false

    func get() async -> [Bank] {
        if !banks.isEmpty || isLoading { return banks }
        isLoading = true
        defer { isLoading = false }
        banks = (try? await BankService.list()) ?? []
        return banks
    }

    func bank(bin: String?) -> Bank? {
        guard let bin else { return nil }
        return banks.first { $0.bin == bin }
    }
}
