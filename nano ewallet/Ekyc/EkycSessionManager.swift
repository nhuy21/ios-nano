//
//  EkycSessionManager.swift
//  nano ewallet
//

import Foundation

/// Quản lý phiên eKYC (CCCD scan, face verify) — tương ứng EkycSessionManager.kt phía Android.
final class EkycSessionManager {
    static let shared = EkycSessionManager()
    private init() {}

    private(set) var currentSessionId: String?

    func startSession() -> String {
        let sessionId = UUID().uuidString
        currentSessionId = sessionId
        return sessionId
    }

    func endSession() {
        currentSessionId = nil
    }
}
