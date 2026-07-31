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
