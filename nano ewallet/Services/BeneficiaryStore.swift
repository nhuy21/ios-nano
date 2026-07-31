//
//  BeneficiaryStore.swift
//  nano ewallet
//
//  Mirror BeneficiaryCache.kt — cache in-memory (không persist đĩa), dùng chung
//  cho ContactsView + Home (mục "Chuyển tiền nhanh" khi nối API thật sau này).
//

import Foundation
import Combine

@MainActor
final class BeneficiaryStore: ObservableObject {

    static let shared = BeneficiaryStore()
    private init() {}

    @Published private(set) var beneficiaries: [Beneficiary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private var isLoaded = false

    /// Trả cache ngay nếu đã có, chỉ gọi API lần đầu hoặc khi `force`.
    func get(force: Bool = false) async -> [Beneficiary] {
        if isLoaded && !force { return beneficiaries }
        await refresh()
        return beneficiaries
    }

    func refresh() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            beneficiaries = try await BeneficiaryService.list()
            isLoaded = true
        } catch {
            loadError = (error as? APIError)?.message ?? "Không tải được danh bạ"
        }
    }

    func create(_ request: CreateBeneficiaryRequest) async throws -> Beneficiary {
        let created = try await BeneficiaryService.create(request)
        beneficiaries.insert(created, at: 0)
        return created
    }

    func updateNickname(id: String, nickname: String?) async throws {
        let updated = try await BeneficiaryService.updateNickname(id: id, nickname: nickname)
        if let index = beneficiaries.firstIndex(where: { $0.id == id }) {
            beneficiaries[index] = updated
        }
    }

    func delete(id: String) async throws {
        try await BeneficiaryService.delete(id: id)
        beneficiaries.removeAll { $0.id == id }
    }

    func touch(id: String) {
        Task { await BeneficiaryService.touch(id: id) }
    }

    func clear() {
        beneficiaries = []
        isLoaded = false
        loadError = nil
    }
}
