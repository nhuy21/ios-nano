//
//  KycOptions.swift
//  nano ewallet
//

import Foundation

/// Tuỳ chọn cấu hình cho luồng eKYC — tương ứng KycOptions.kt phía Android.
struct KycOptions {
    var requireFaceLiveness: Bool = true
    var requireNfcRead: Bool = false
}
