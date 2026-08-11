//
//  PendingKyc.swift
//  nano ewallet
//
//  Mirror ekyc/PendingKycPayload.kt — giỏ đựng kết quả eKYC giữa lúc SDK đóng lại và
//  lúc màn bổ sung thông tin gửi hồ sơ lên BE.
//
//  Ảnh để dạng base64 vì SDK trả thẳng base64, đổi qua `Data` rồi đổi lại chỉ tốn công.
//

import Foundation
import Combine

/// Bản chốt bất biến để nộp hồ sơ — tách khỏi store đang thay đổi liên tục, tránh
/// trường hợp người dùng sửa dở giữa lúc request đang bay.
struct PendingKycSnapshot {
    let frontImageBase64: String?
    let backImageBase64: String?
    let livenessPortraitBase64: String?
    let portraitInCardBase64: String?
    let fullName: String
    let dateOfBirth: String
    let genderCode: Int
    let idCardNumber: String
    let issueDate: String
    let expireDate: String
    let placeOfIssues: String?
    let address: String
    let temporaryLocation: String?
    let business: String?
    let position: String?
    let purposeOfUsing: String?
    let businessAreaId: String?
}

@MainActor
final class PendingKyc: ObservableObject {

    static let shared = PendingKyc()
    private init() {}

    @Published var frontImageBase64: String?
    @Published var backImageBase64: String?
    @Published var livenessPortraitBase64: String?

    /// Dữ liệu chip NFC thô (`sod`, `dg1`, `dg2`, `dg13`...) — BE cần nguyên vẹn để đối
    /// soát passive authentication với C06.
    @Published var nfcRaw: [String: Any]?

    /// Ảnh chân dung lấy từ chip — khác `livenessPortraitBase64` (ảnh chụp lúc xác thực).
    @Published var portraitInCardBase64: String?

    /// Trường chữ bóc từ OCR/NFC.
    @Published var idCardNumber: String?
    @Published var fullName: String?
    @Published var dateOfBirth: String?
    @Published var gender: String?
    @Published var address: String?
    @Published var issueDate: String?
    @Published var expireDate: String?
    /// Chip KHÔNG mang nơi cấp — lấy từ OCR mặt sau thẻ; OCR cũng không đọc được thì lúc
    /// nộp hồ sơ điền giá trị mặc định.
    @Published var placeOfIssues: String?

    /// Người dùng tự nhập/chọn ở màn bổ sung thông tin.
    @Published var temporaryLocation: String?
    @Published var business: String?
    @Published var position: String?
    @Published var purposeOfUsing: String?
    @Published var businessAreaId: String?

    var hasAllImages: Bool {
        frontImageBase64 != nil && backImageBase64 != nil && livenessPortraitBase64 != nil
    }

    /// Chuỗi JSON của dữ liệu chip — BE nhận `nfcRawData` dạng chuỗi, không phải object.
    var nfcRawJson: String? {
        guard let nfcRaw,
              let data = try? JSONSerialization.data(withJSONObject: nfcRaw)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Quy ước Bảo Kim: 1 nam, 2 nữ, 3 khác. Chip trả chuỗi tiếng Việt.
    var genderCode: Int {
        switch gender?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "nam": return 1
        case "nữ", "nu": return 2
        default: return 3
        }
    }

    /// Chốt dữ liệu để nộp. `nil` khi thiếu trường bắt buộc mà chip phải có — thiếu thì
    /// phải quét lại CCCD chứ không nộp hồ sơ khuyết.
    func snapshot() -> PendingKycSnapshot? {
        guard let fullName, let dateOfBirth, let idCardNumber,
              let issueDate, let expireDate, let address
        else { return nil }
        return PendingKycSnapshot(
            frontImageBase64: frontImageBase64,
            backImageBase64: backImageBase64,
            livenessPortraitBase64: livenessPortraitBase64,
            portraitInCardBase64: portraitInCardBase64,
            fullName: fullName,
            dateOfBirth: dateOfBirth,
            genderCode: genderCode,
            idCardNumber: idCardNumber,
            issueDate: issueDate,
            expireDate: expireDate,
            placeOfIssues: placeOfIssues,
            address: address,
            temporaryLocation: temporaryLocation,
            business: business,
            position: position,
            purposeOfUsing: purposeOfUsing,
            businessAreaId: businessAreaId
        )
    }

    func clear() {
        frontImageBase64 = nil
        backImageBase64 = nil
        livenessPortraitBase64 = nil
        portraitInCardBase64 = nil
        nfcRaw = nil
        idCardNumber = nil
        fullName = nil
        dateOfBirth = nil
        gender = nil
        address = nil
        issueDate = nil
        expireDate = nil
        placeOfIssues = nil
        temporaryLocation = nil
        business = nil
        position = nil
        purposeOfUsing = nil
        businessAreaId = nil
    }

    /// Tóm tắt để soi log — CHỈ in độ dài base64, không in nội dung ảnh.
    var summary: String {
        """
        PendingKyc(front=\(frontImageBase64?.count ?? 0), back=\(backImageBase64?.count ?? 0), \
        liveness=\(livenessPortraitBase64?.count ?? 0), nfcKeys=\(nfcRaw?.keys.sorted() ?? []), \
        id=\(idCardNumber ?? "-"), name=\(fullName ?? "-"))
        """
    }
}
