//
//  EkycSessionManager.swift
//  nano ewallet
//
//  Mirror ekyc/EkycSessionManager.kt + ekyc/AuthHelper.kt.
//
//  Lấy phiên eKYC từ BACKEND (`POST ekyc/session`) chứ không gọi thẳng gateway CMC —
//  BE chạy login/init/init-session bằng credentials phía máy chủ rồi trả kết quả, nhờ
//  vậy username/password/appId của CMC không nằm trong app (dịch ngược không moi ra được).
//
//  Chuẩn bị SỚM ngay khi mở màn hướng dẫn, để lúc người dùng bấm "Bắt đầu xác thực" thì
//  phiên đã sẵn, không phải đứng chờ chuỗi request.
//

import Foundation
import Combine

/// Các giá trị phiên mà SDK cần — tương ứng `DataUtil` bên Android.
struct EkycSession: Decodable {
    let ekycSessionId: String?
    let session: String?
    let sessionCA: String?
    let tokenCA: String?
    let tokenCAKala: String?
    let appId: String?
    let baseUrl: String?
    let baseUrlCA: String?
    let flow: String?
}

@MainActor
final class EkycSessionManager: ObservableObject {

    static let shared = EkycSessionManager()
    private init() {}

    enum State: Equatable {
        case idle
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .idle
    private(set) var session: EkycSession?

    /// Lời gọi đang chạy — để nhiều nơi gọi `prepare()` cùng lúc chỉ tốn một request,
    /// thay cho `Mutex` bên Android.
    private var inFlight: Task<Bool, Never>?

    var lastError: String? {
        if case .error(let message) = state { return message }
        return nil
    }

    /// Bảo đảm có phiên hợp lệ. Trả `true` nếu sẵn sàng.
    /// - Parameter forceRefresh: bỏ qua cache, lấy phiên mới (dùng khi phiên cũ hết hạn).
    @discardableResult
    func prepare(forceRefresh: Bool = false) async -> Bool {
        if !forceRefresh, state == .ready, session != nil { return true }
        if let inFlight, !forceRefresh { return await inFlight.value }

        let task = Task { () -> Bool in
            state = .loading
            do {
                let result = try await APIClient.shared.request(
                    .post, "ekyc/session", body: EmptyEkycBody(),
                    auth: true, slow: true, as: EkycSession.self
                )
                session = result
                state = .ready
                return true
            } catch let error as APIError {
                state = .error(error.message)
                return false
            } catch {
                state = .error("Không khởi tạo được phiên xác thực")
                return false
            }
        }
        inFlight = task
        let ok = await task.value
        inFlight = nil
        return ok
    }

    /// SDK báo phiên hết hạn — lần sau phải lấy phiên mới.
    func invalidate() {
        session = nil
        state = .idle
    }
}

private struct EmptyEkycBody: Encodable {}
