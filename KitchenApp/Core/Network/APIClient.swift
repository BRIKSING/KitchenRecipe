import Foundation

// MARK: - APIClient

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private var baseURL: URL

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.baseURL = URL(string: UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:3000")!
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public API

    func updateBaseURL(_ url: URL) {
        baseURL = url
    }

    func setTokens(access: String, refresh: String) {
        KeychainService.accessToken  = access
        KeychainService.refreshToken = refresh
    }

    func clearTokens() {
        KeychainService.clearAll()
    }

    var isAuthenticated: Bool { KeychainService.accessToken != nil }

    // MARK: - Generic request

    func request<T: Decodable>(_ endpoint: Endpoint, body: Encodable? = nil) async throws -> T {
        let urlRequest = try buildRequest(endpoint, body: body)
        return try await execute(urlRequest, endpoint: endpoint)
    }

    // MARK: - Multipart upload

    func upload(imageData: Data, mimeType: String = "image/jpeg", to endpoint: Endpoint) async throws -> UploadResponse {
        var request = try buildRequest(endpoint, body: nil)
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipart(data: imageData, mimeType: mimeType, boundary: boundary)
        return try await execute(request, endpoint: endpoint)
    }

    // MARK: - Build URLRequest

    private func buildRequest(_ endpoint: Endpoint, body: Encodable?) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false)!
        components.queryItems = endpoint.queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = endpoint.method

        // logout инвалидирует refresh-токен, и бэкенд ждёт его в Authorization-заголовке.
        // Все остальные защищённые роуты используют access-токен.
        let authToken: String?
        switch endpoint {
        case .logout: authToken = KeychainService.refreshToken
        default:      authToken = KeychainService.accessToken
        }
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        return request
    }

    // MARK: - Execute with retry and token refresh

    private func execute<T: Decodable>(_ request: URLRequest, endpoint: Endpoint, retries: Int = 3) async throws -> T {
        do {
            return try await performRequest(request)
        } catch NetworkError.unauthorized {
            // Attempt token refresh once
            if let newToken = try? await refreshAccessToken() {
                var retried = request
                retried.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                return try await performRequest(retried)
            }
            throw NetworkError.unauthorized
        } catch NetworkError.noConnection where retries > 1 {
            // Exponential backoff for network errors
            let delay = UInt64(pow(2.0, Double(4 - retries))) * 1_000_000_000
            try? await Task.sleep(nanoseconds: delay)
            return try await execute(request, endpoint: endpoint, retries: retries - 1)
        }
    }

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.noConnection
        }

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.unknown(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200...299:
            // 204 No Content / пустое тело (logout, delete) — отдаём EmptyResponse без декодирования.
            if data.isEmpty, let empty = EmptyResponse() as? T {
                return empty
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw NetworkError.decodingError(error)
            }
        case 401:
            throw NetworkError.unauthorized
        default:
            // Бэкенд отдаёт ошибки в формате { detail, code }.
            let message: String
            if let payload = try? decoder.decode(ServerErrorPayload.self, from: data) {
                message = payload.detail
            } else {
                message = String(data: data, encoding: .utf8) ?? "Unknown error"
            }
            throw NetworkError.serverError(http.statusCode, message)
        }
    }

    // MARK: - Token refresh

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken = KeychainService.refreshToken else {
            throw NetworkError.unauthorized
        }

        struct RefreshResponse: Decodable { let access_token: String }

        let components = URLComponents(url: baseURL.appendingPathComponent("/auth/refresh"), resolvingAgainstBaseURL: false)!
        var req = URLRequest(url: components.url!)
        req.httpMethod = "POST"
        // Бэкенд читает refresh-токен из Authorization: Bearer, а не из тела запроса.
        req.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await session.data(for: req)
        let result = try decoder.decode(RefreshResponse.self, from: data)
        KeychainService.accessToken = result.access_token
        return result.access_token
    }

    // MARK: - Multipart helpers

    private func buildMultipart(data: Data, mimeType: String, boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(data)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }
}

// MARK: - Server error payload

/// Формат ошибок бэкенда: { "detail": "...", "code": "ERROR_CODE" }
private struct ServerErrorPayload: Decodable {
    let detail: String
    let code: String?
}
