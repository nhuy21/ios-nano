//
//  OnboardingService.swift
//  nano ewallet
//
//  Mirror `EkycApi.walletLinking` — luồng đồng bộ ví Bảo Kim có sẵn (không qua eKYC).
//

import Foundation

/// Body `{}` cho endpoint không cần tham số.
struct EmptyOnboardingBody: Encodable {}

struct WalletLinkingRequest: Encodable {
    let username: String
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case username
        case fullName = "full_name"
    }
}

/// `status`: "READY" (đã có `embed_link`, mở được ngay) hoặc "PENDING" (Bảo Kim còn đang
/// dựng ví, phải gọi lại sau ít giây).
struct AgreementResult: Decodable {
    let status: String?
    let embedLink: String?

    enum CodingKeys: String, CodingKey {
        case status
        case embedLink = "embed_link"
    }
}

/// `embed_link` là URL nhúng WebView để user xác nhận OTP Bảo Kim gửi về số điện thoại
/// đã đăng ký ví.
struct WalletLinkingResult: Decodable {
    let phoneNumber: String?
    let fullName: String?
    let embedLink: String

    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phone_number"
        case fullName = "full_name"
        case embedLink = "embed_link"
    }
}

// MARK: - Đối soát C06

struct C06Request: Encodable {
    let ekycSessionId: String?
    let idCard: String?
    /// Chuỗi JSON dữ liệu chip thô (`sod`, `dg1`, `dg2`, `dg13`...).
    let nfcRawData: String
}

/// `approved == false` nghĩa là chữ ký CSCA không hợp lệ — thẻ giả, phải chặn luồng.
struct C06Result: Decodable {
    let approved: Bool
    let decision: String?
    let exitcode: Int?
}

// MARK: - Nộp hồ sơ

/// Một trường Bảo Kim soi hồ sơ. `status`: 1 = đạt, 2 = sai, 3 = thiếu, 5 = tự xác thực xong.
struct BkField: Decodable, Identifiable, Hashable {
    let key: String
    let value: String?
    let status: String
    let message: String?
    var id: String { key }
}

struct OnboardingResult: Decodable {
    let recordId: String?
    let fields: [BkField]?

    /// Trường đang sai hoặc thiếu — phải cho người dùng sửa rồi gửi lại.
    var fieldsNeedingFix: [BkField] {
        fields?.filter { $0.status == "2" || $0.status == "3" } ?? []
    }
}

struct SubmitEkycRequest: Encodable {
    /// Sinh mới mỗi lần nộp — BE bắt buộc để chống nộp trùng tạo hai hồ sơ bên Bảo Kim.
    let idempotencyKey: String
    let frontSideImageOfIdCard: String?
    let backSideImageOfIdCard: String?
    let selfieImage: String?
    let portraitInCard: String?
    let name: String
    let birthDay: String
    let gender: Int
    let nationality: String
    let idNumber: String
    let issueDate: String
    let expiryDate: String
    let placeOfIssues: String
    let recentLocation: String
    let temporaryLocation: String?
    let business: String?
    let position: String?
    let purposeOfUsing: String?
    let businessAreaId: String?
    let bankNo: String
    let accNo: String
    let accName: String
    let deviceId: String
}

enum OnboardingService {
    /// `POST onboarding/wallet-linking`
    ///
    /// Bảo Kim có thể từ chối NGAY ở đây, chưa cần tới OTP: ví không tồn tại, ví không
    /// hoạt động, số điện thoại đã liên kết, tên không khớp thông tin đăng ký ví.
    static func linkBaoKimWallet(username: String, fullName: String) async throws -> WalletLinkingResult {
        try await APIClient.shared.request(
            .post, "onboarding/wallet-linking",
            body: WalletLinkingRequest(username: username, fullName: fullName),
            auth: true, slow: true, as: WalletLinkingResult.self
        )
    }

    /// `POST ekyc/c06/check` — đối soát passive authentication chip NFC.
    ///
    /// Gửi dữ liệu chip THÔ lên BE; BE tự parse, login CA rồi hỏi CMC. Trả về thẻ có thật
    /// hay không (chữ ký CSCA hợp lệ).
    static func verifyC06(
        ekycSessionId: String?, idCard: String?, nfcRawData: String
    ) async throws -> C06Result {
        try await APIClient.shared.request(
            .post, "ekyc/c06/check",
            body: C06Request(ekycSessionId: ekycSessionId, idCard: idCard, nfcRawData: nfcRawData),
            auth: true, slow: true, as: C06Result.self
        )
    }

    /// `POST onboarding/submit` — nộp hồ sơ eKYC kèm tài khoản ngân hàng nhận tiền.
    static func submitEkyc(
        payload: PendingKycSnapshot, bankNo: String, accNo: String, accName: String
    ) async throws -> OnboardingResult {
        let body = SubmitEkycRequest(
            idempotencyKey: UUID().uuidString,
            frontSideImageOfIdCard: payload.frontImageBase64,
            backSideImageOfIdCard: payload.backImageBase64,
            selfieImage: payload.livenessPortraitBase64,
            portraitInCard: payload.portraitInCardBase64,
            name: payload.fullName,
            birthDay: payload.dateOfBirth,
            gender: payload.genderCode,
            nationality: "VN",
            idNumber: payload.idCardNumber,
            issueDate: payload.issueDate,
            expiryDate: payload.expireDate,
            // Chip NFC không trả nơi cấp — mọi CCCD gắn chip đều in cơ quan này.
            placeOfIssues: payload.placeOfIssues ?? "Cục Cảnh sát QLHC về TTXH",
            recentLocation: payload.address,
            temporaryLocation: payload.temporaryLocation,
            business: payload.business,
            position: payload.position,
            purposeOfUsing: payload.purposeOfUsing,
            businessAreaId: payload.businessAreaId,
            bankNo: bankNo, accNo: accNo, accName: accName,
            deviceId: AuthStore.shared.getOrCreateDeviceId()
        )
        return try await APIClient.shared.request(
            .post, "onboarding/submit", body: body,
            auth: true, slow: true, as: OnboardingResult.self
        )
    }

    /// `POST onboarding/create-agreement` — một lần gọi. Trả `PENDING` khi Bảo Kim còn
    /// đang xử lý ví; đó KHÔNG phải lỗi. Dùng `createAgreementAndPoll` thay vì gọi thẳng.
    private static func createAgreementOnce() async throws -> AgreementResult {
        try await APIClient.shared.request(
            .post, "onboarding/create-agreement", body: EmptyOnboardingBody(),
            auth: true, slow: true, as: AgreementResult.self
        )
    }

    /// Gọi lại `create-agreement` tới khi Bảo Kim dựng xong ví (`READY` + có `embed_link`).
    ///
    /// BE cố tình KHÔNG tự thử lại để khỏi treo request HTTP, nên client phải tự lặp. Hết
    /// hạn chờ mà vẫn `PENDING` thì báo lỗi rõ ràng, không mở WebView với link rỗng.
    static func createAgreementAndPoll(
        interval: UInt64 = 10_000_000_000, maxWait: TimeInterval = 5 * 60
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(maxWait)
        while true {
            let result = try await createAgreementOnce()
            if result.status == "READY", let link = result.embedLink, !link.isEmpty {
                return link
            }
            if Date() >= deadline {
                throw APIError.unknown("Bảo Kim xử lý quá lâu, vui lòng thử lại sau")
            }
            try await Task.sleep(nanoseconds: interval)
        }
    }

    /// `POST onboarding/update` — chỉ gửi các trường cần sửa (đang status 2/3).
    /// - Parameter fields: khoá theo tên BE nhận ("name", "placeOfIssues", "bankNo"...).
    static func updateEkyc(fields: [String: String]) async throws -> OnboardingResult {
        var body = fields
        body["deviceId"] = AuthStore.shared.getOrCreateDeviceId()
        return try await APIClient.shared.request(
            .post, "onboarding/update", body: body,
            auth: true, slow: true, as: OnboardingResult.self
        )
    }
}
