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
    /// CHỈ có ở `banks/parse-message`, và chỉ khi văn bản chứa TỪ 2 TÀI KHOẢN THẬT trở lên
    /// (BE đã tra tên từng cái và loại số nào không tra ra — số điện thoại, ngày tháng, số
    /// tiền đều rụng ở bước đó). Các trường phía trên vẫn là tài khoản BE tự chọn như cũ,
    /// nên `nil` = hành xử y hệt trước đây.
    let accounts: [ParsedAccount]?
}

/// Một tài khoản trong `ParsedQr.accounts` — BE đã tra ra tên chủ tài khoản thật.
struct ParsedAccount: Decodable, Hashable {
    let bankBin: String
    let bankName: String?
    let accountNumber: String
    let accountName: String
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
    /// Lượt tải đang chạy — lời gọi trùng CHỜ nó thay vì tự gọi API lần nữa.
    ///
    /// Trước đây chỉ có cờ `isLoading` và lời gọi trúng lúc đang tải sẽ nhận về mảng RỖNG
    /// ngay lập tức. Màn nào copy kết quả đó vào `@State` trong `.task` (chạy đúng một lần)
    /// là ôm danh sách rỗng vĩnh viễn — đúng lỗi "bấm chọn ngân hàng mà danh sách trống".
    private var loadTask: Task<[Bank], Never>?

    func get() async -> [Bank] {
        if !banks.isEmpty { return banks }
        if let loadTask { return await loadTask.value }

        let task = Task<[Bank], Never> { [weak self] in
            let fetched = (try? await BankService.list()) ?? []
            self?.banks = fetched
            self?.loadTask = nil
            return fetched
        }
        loadTask = task
        return await task.value
    }

    func bank(bin: String?) -> Bank? {
        guard let bin else { return nil }
        return banks.first { $0.bin == bin }
    }
}
