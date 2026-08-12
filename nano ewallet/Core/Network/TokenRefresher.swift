//
//  TokenRefresher.swift
//  nano ewallet
//

import Foundation

/// Trạng thái phiên sau một lượt `auth/refresh` — chỉ những gì Splash cần để điều hướng.
struct RefreshedSession: Sendable {
    /// `status` server vừa xác nhận. `nil` khi response KHÔNG kèm `user`: nơi gọi phải dùng
    /// `AuthStore.lastKnownStatus` thay thế, tuyệt đối không coi đó là hết phiên — refresh
    /// thành công đã chứng minh phiên còn sống.
    let status: String?
    let phone: String?
}

/// Refresh access token an toàn khi nhiều request cùng nhận 401.
///
/// Mirror `TokenAuthenticator` bên Android: nếu 5 request 401 cùng lúc thì chỉ gọi
/// `auth/refresh` **một lần**, các request còn lại chờ cùng kết quả rồi retry.
/// Cơ chế dedupe: so token lúc request thất bại với token hiện tại — nếu đã khác nghĩa là
/// ai đó vừa refresh xong, không cần refresh lại.
///
/// BE cấp refresh token MỚI mỗi lượt và thu hồi token cũ, nên hai lượt refresh song song thì
/// bên tới sau gửi token đã bị thay và nhận 401. Vì vậy MỌI đường refresh của app — request
/// 401 lẫn bootstrap ở Splash — phải đi qua `shared`, không ai được tự gọi `auth/refresh`.
actor TokenRefresher {

    /// Hàng đợi refresh DUY NHẤT của app. Mỗi nơi giữ một instance riêng thì single-flight chỉ
    /// còn tác dụng trong phạm vi nơi đó, hai instance vẫn refresh song song và huỷ token của
    /// nhau — đúng lỗi "mở app thỉnh thoảng bắt đăng nhập lại dù token vẫn còn".
    static let shared = TokenRefresher()

    private var inFlight: Task<RefreshedSession, Error>?
    /// Số thứ tự của lượt refresh đang giữ `inFlight`. `Task` là struct nên không so sánh
    /// được bằng `===`; đánh số là cách nhận ra "chỗ mình gán còn đó hay đã bị lượt sau thay".
    private var inFlightId = 0

    @discardableResult
    func refreshIfNeeded(previousToken: String?) async throws -> RefreshedSession {
        // Ai đó đã refresh xong trong lúc mình chờ -> token hiện tại đã mới, khỏi gọi lại.
        // Lượt đó vừa xác nhận phiên còn sống nên trả về trạng thái nó đã lưu.
        if let current = KeychainStore.get(.accessToken), current != previousToken {
            return Self.storedSession()
        }

        if let inFlight {
            return try await inFlight.value
        }

        let task = Task<RefreshedSession, Error> { try await Self.performRefresh() }
        inFlightId &+= 1
        let myId = inFlightId
        inFlight = task
        // Chỉ dọn khi `inFlight` VẪN là lượt của mình, KHÔNG `defer { inFlight = nil }` vô
        // điều kiện: lượt refresh sau có thể đã gán `inFlight` mới trong lúc lượt này còn
        // đang chờ mạng, xoá thẳng sẽ mất Task mới đó — các request tới sau không còn chỗ
        // bám, lại tự gọi refresh thêm lần nữa.
        defer { if inFlightId == myId { inFlight = nil } }
        return try await task.value
    }

    // MARK: - Private

    /// Trạng thái đã lưu lúc lượt refresh trước ghi vào — đọc thẳng Keychain (`nonisolated`)
    /// nên không phải nhảy sang MainActor của `AuthStore`.
    private static func storedSession() -> RefreshedSession {
        RefreshedSession(
            status: KeychainStore.get(.lastKnownStatus),
            phone: KeychainStore.get(.userPhone)
        )
    }

    /// Gọi `auth/refresh` bằng URLSession riêng để không đệ quy qua APIClient
    /// (APIClient bắt 401 -> gọi refresher -> nếu refresher lại dùng APIClient sẽ vòng lặp).
    private static func performRefresh() async throws -> RefreshedSession {
        guard let refreshToken = KeychainStore.get(.refreshToken) else {
            throw APIError.unauthenticated
        }
        let deviceId = await AuthStore.shared.getOrCreateDeviceId()

        var request = URLRequest(url: AppConfig.baseURL.appendingPathComponent("auth/refresh"))
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RefreshRequest(deviceId: deviceId, refreshToken: refreshToken)
        )

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession(configuration: config).data(for: request)
        } catch {
            // Phân loại y như `APIClient` (mất mạng / timeout / DNS-TLS), KHÔNG để lỗi thô lọt
            // ra ngoài: nơi gọi phân biệt "hết phiên" với "sự cố tạm thời" qua `APIError`.
            throw APIError.from(transport: error)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(statusCode) else {
            // Giữ nguyên mã HTTP thay vì quy hết về `.unauthenticated`: chỉ 401/403 mới là
            // refresh token hết hạn/bị thu hồi. Gộp cả 5xx vào đó thì BE lỗi hay đang restart
            // là mọi người dùng bị đăng xuất oan.
            switch statusCode {
            case 401, 403:
                // Câu tiếng Việt của mình, KHÔNG lấy message BE: chỗ này BE trả "Unauthorized"
                // và nó hiện thẳng lên cho người dùng.
                throw APIError.server(
                    statusCode: statusCode,
                    message: "Phiên đăng nhập đã hết, vui lòng đăng nhập lại"
                )
            default:
                let parsed = try? JSONDecoder.beDecoder.decode(APIEmptyResponse.self, from: data)
                throw APIError.server(
                    statusCode: statusCode,
                    message: parsed?.message?.text ?? "Không làm mới được phiên (HTTP \(statusCode))"
                )
            }
        }

        let envelope = try JSONDecoder.beDecoder.decode(APIResponse<AuthData>.self, from: data)
        guard let authData = envelope.data,
              let accessToken = authData.accessToken,
              let newRefreshToken = authData.refreshToken else {
            throw APIError.unauthenticated
        }

        await AuthStore.shared.saveTokens(access: accessToken, refresh: newRefreshToken)
        if let user = authData.user {
            await AuthStore.shared.saveUser(user)
        }
        return RefreshedSession(status: authData.user?.status, phone: authData.user?.phone)
    }
}
