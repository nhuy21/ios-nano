//
//  APIClient.swift
//  nano ewallet
//

import Foundation

/// Client HTTP duy nhất của app — thay OkHttp + Gson bên Android.
///
/// Khác Android ở 1 điểm có chủ ý: Android gắn token thủ công trong từng API object
/// (`authorizedBuilder`), ở đây gắn tập trung qua tham số `auth:` cho gọn và khó quên.
///
/// Refresh token khi 401: dùng single-flight (`actor TokenRefresher`) để nhiều request 401
/// cùng lúc chỉ refresh 1 lần rồi cùng retry — mirror `TokenAuthenticator` bên Android
/// (retry đúng 1 lần, không lặp vô hạn).
final class APIClient {

    static let shared = APIClient()

    /// Timeout thường: 20s (mirror client `default` bên Android).
    private let session: URLSession
    /// Timeout dài: 60s cho onboarding/submit, create-agreement, transfer, money-request
    /// (mirror client `slow` bên Android).
    private let slowSession: URLSession

    private let refresher = TokenRefresher()

    private init() {
        func makeSession(timeout: TimeInterval) -> URLSession {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeout
            config.timeoutIntervalForResource = timeout
            config.waitsForConnectivity = false
            return URLSession(configuration: config)
        }
        session = makeSession(timeout: 20)
        slowSession = makeSession(timeout: 60)
    }

    // MARK: - Public API

    /// Gọi API trả về `data` kiểu `T`.
    /// - Parameters:
    ///   - path: path ngắn, KHÔNG có `/api/v1` (đã nằm trong `AppConfig.baseURL`).
    ///   - auth: true = gắn `Authorization: Bearer`, tự refresh khi 401.
    ///   - slow: true = dùng timeout 60s.
    @discardableResult
    func request<T: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: Encodable? = nil,
        query: [String: String]? = nil,
        auth: Bool = false,
        slow: Bool = false,
        as type: T.Type
    ) async throws -> T {
        let data = try await performWithRefresh(
            method, path, body: body, query: query, auth: auth, slow: slow
        )
        let envelope: APIResponse<T>
        do {
            envelope = try JSONDecoder.beDecoder.decode(APIResponse<T>.self, from: data)
        } catch {
            throw APIError.decoding("\(error)")
        }
        guard let payload = envelope.data else {
            // Case riêng, không gộp vào `.decoding`: interceptor của BE loại bỏ hẳn field
            // `data` khi giá trị null, nên có endpoint (giao dịch) coi đây là hợp lệ.
            throw APIError.missingData(path: path)
        }
        return payload
    }

    /// Gọi API không cần đọc `data` (register, logout, resend-otp...).
    func requestVoid(
        _ method: HTTPMethod,
        _ path: String,
        body: Encodable? = nil,
        query: [String: String]? = nil,
        auth: Bool = false,
        slow: Bool = false
    ) async throws {
        _ = try await performWithRefresh(
            method, path, body: body, query: query, auth: auth, slow: slow
        )
    }

    // MARK: - Refresh 401 (single-flight, retry 1 lần)

    private func performWithRefresh(
        _ method: HTTPMethod,
        _ path: String,
        body: Encodable?,
        query: [String: String]?,
        auth: Bool,
        slow: Bool
    ) async throws -> Data {
        do {
            return try await perform(method, path, body: body, query: query, auth: auth, slow: slow)
        } catch let error as APIError where error.isUnauthorized && auth {
            // Chỉ thử refresh 1 lần. Nếu refresh cũng fail -> ném lỗi để AppState đăng xuất.
            let tokenBeforeRefresh = KeychainStore.get(.accessToken)
            try await refresher.refreshIfNeeded(previousToken: tokenBeforeRefresh)
            return try await perform(method, path, body: body, query: query, auth: auth, slow: slow)
        }
    }

    // MARK: - Thực thi request

    private func perform(
        _ method: HTTPMethod,
        _ path: String,
        body: Encodable?,
        query: [String: String]?,
        auth: Bool,
        slow: Bool
    ) async throws -> Data {
        var url = AppConfig.baseURL.appendingPathComponent(path)
        if let query, !query.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let built = components?.url { url = built }
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if auth {
            guard let token = KeychainStore.get(.accessToken) else {
                throw APIError.unauthenticated
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            do {
                request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            } catch {
                throw APIError.decoding("không encode được body: \(error)")
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await (slow ? slowSession : session).data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw APIError.offline
            default:
                throw APIError.unknown(urlError.localizedDescription)
            }
        } catch {
            throw APIError.unknown(error.localizedDescription)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(statusCode) else {
            // Lấy message tiếng Việt từ envelope lỗi nếu có.
            let parsed = try? JSONDecoder.beDecoder.decode(APIEmptyResponse.self, from: data)
            throw APIError.server(
                statusCode: statusCode,
                message: parsed?.message?.text ?? "Đã có lỗi xảy ra (HTTP \(statusCode))"
            )
        }
        return data
    }
}

// MARK: - Hỗ trợ

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

/// Cho phép truyền `Encodable` tồn tại (existential) vào `JSONEncoder`.
private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void
    init(_ wrapped: Encodable) {
        encodeClosure = wrapped.encode(to:)
    }
    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

extension JSONDecoder {
    /// BE trả ISO-8601 (có/không millisecond) — dùng chung 1 decoder cho toàn app.
    nonisolated static let beDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: raw) {
                return date
            }
            if let date = ISO8601DateFormatter.standard.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Ngày không đúng ISO-8601: \(raw)")
            )
        }
        return decoder
    }()
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard = ISO8601DateFormatter()
}
