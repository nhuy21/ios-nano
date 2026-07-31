//
//  EkycUploader.swift
//  nano ewallet
//

import Foundation

/// Upload ảnh/video eKYC lên BE — tương ứng EkycUploader.kt phía Android.
/// Cần match đúng DTO/flow ở be/src, không tự thêm logic phụ.
enum EkycUploader {
    static func upload(sessionId: String, imageData: Data, fieldName: String) async throws {
        // TODO: implement multipart upload theo đúng contract be/src/modules/kyc
    }
}
