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

    /// Trường chữ bóc từ OCR/NFC.
    @Published var idCardNumber: String?
    @Published var fullName: String?
    @Published var dateOfBirth: String?
    @Published var gender: String?
    @Published var address: String?
    @Published var issueDate: String?
    @Published var expireDate: String?

    var hasAllImages: Bool {
        frontImageBase64 != nil && backImageBase64 != nil && livenessPortraitBase64 != nil
    }

    func clear() {
        frontImageBase64 = nil
        backImageBase64 = nil
        livenessPortraitBase64 = nil
        nfcRaw = nil
        idCardNumber = nil
        fullName = nil
        dateOfBirth = nil
        gender = nil
        address = nil
        issueDate = nil
        expireDate = nil
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
