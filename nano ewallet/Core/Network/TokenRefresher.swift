//
//  TokenRefresher.swift
//  nano ewallet
//

import Foundation

/// Refresh access token an toàn khi nhiều request cùng nhận 401.
///
/// Mirror `TokenAuthenticator` bên Android: nếu 5 request 401 cùng lúc thì chỉ gọi
/// `auth/refresh` **một lần**, các request còn lại chờ cùng kết quả rồi retry.
/// Cơ chế dedupe: so token lúc request thất bại với token hiện tại — nếu đã khác nghĩa là
/// ai đó vừa refresh xong, không cần refresh lại.
actor TokenRefresher {

    private var inFlight: Task<Void, Error>?

    func refreshIfNeeded(previousToken: String?) async throws {
        // Ai đó đã refresh xong trong lúc mình chờ -> token hiện tại đã mới, khỏi gọi lại.
        if let current = KeychainStore.get(.accessToken), current != previousToken {
            return
        }

        if let inFlight {
            try await inFlight.value
            return
        }

        let task = Task<Void, Error> { try await Self.performRefresh() }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }

    // MARK: - Private

    /// Gọi `auth/refresh` bằng URLSession riêng để không đệ quy qua APIClient
    /// (APIClient bắt 401 -> gọi refresher -> nếu refresher lại dùng APIClient sẽ vòng lặp).
    private static func performRefresh() async throws {
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
        let (data, response) = try await URLSession(configuration: config).data(for: request)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(statusCode) else {
            // Refresh token hết hạn/bị thu hồi -> phiên chấm dứt, AppState sẽ đưa về Login.
            throw APIError.unauthenticated
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
    }
}
