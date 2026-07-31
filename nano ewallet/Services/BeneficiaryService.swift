//
//  BeneficiaryService.swift
//  nano ewallet
//
//  Mirror BeneficiaryApi.kt.
//

import Foundation

enum BeneficiaryService {
    /// `GET beneficiaries`
    static func list() async throws -> [Beneficiary] {
        try await APIClient.shared.request(.get, "beneficiaries", auth: true, as: [Beneficiary].self)
    }

    /// `POST beneficiaries`
    static func create(_ request: CreateBeneficiaryRequest) async throws -> Beneficiary {
        try await APIClient.shared.request(.post, "beneficiaries", body: request, auth: true, as: Beneficiary.self)
    }

    /// `PATCH beneficiaries/:id`
    static func updateNickname(id: String, nickname: String?) async throws -> Beneficiary {
        try await APIClient.shared.request(
            .patch, "beneficiaries/\(id)",
            body: UpdateBeneficiaryRequest(nickname: nickname),
            auth: true, as: Beneficiary.self
        )
    }

    /// `DELETE beneficiaries/:id`
    static func delete(id: String) async throws {
        try await APIClient.shared.requestVoid(.delete, "beneficiaries/\(id)", auth: true)
    }

    /// `POST beneficiaries/:id/touch` — best-effort, cập nhật lastUsedAt/useCount khi chọn dùng.
    static func touch(id: String) async {
        try? await APIClient.shared.requestVoid(.post, "beneficiaries/\(id)/touch", auth: true)
    }
}
