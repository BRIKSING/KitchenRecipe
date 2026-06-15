import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var userEmail: String?
    @Published var userUsername: String?

    private let api = APIClient.shared

    init() {
        isAuthenticated = api.isAuthenticated
        userEmail    = UserDefaults.standard.string(forKey: "user.email")
        userUsername = UserDefaults.standard.string(forKey: "user.username")
    }

    func login(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let body = LoginRequest(email: email, password: password)
            let resp: AuthResponse = try await api.request(.login(body), body: body)
            api.setTokens(access: resp.accessToken, refresh: resp.refreshToken)
            storeUserInfo(email: resp.user?.email ?? email, username: resp.user?.username)
            isAuthenticated = true
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }

    func register(email: String, username: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let body = RegisterRequest(email: email, username: username, password: password)
            let resp: AuthResponse = try await api.request(.register(body), body: body)
            api.setTokens(access: resp.accessToken, refresh: resp.refreshToken)
            storeUserInfo(email: resp.user?.email ?? email, username: resp.user?.username ?? username)
            isAuthenticated = true
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }

    func logout() {
        Task {
            await api.logout()
            api.clearTokens()
            clearUserInfo()
            isAuthenticated = false
        }
    }

    // MARK: - Private

    private func storeUserInfo(email: String, username: String?) {
        userEmail = email
        UserDefaults.standard.set(email, forKey: "user.email")
        if let username {
            userUsername = username
            UserDefaults.standard.set(username, forKey: "user.username")
        }
    }

    private func clearUserInfo() {
        userEmail = nil
        userUsername = nil
        UserDefaults.standard.removeObject(forKey: "user.email")
        UserDefaults.standard.removeObject(forKey: "user.username")
    }
}

// MARK: - Auth response

/// Ответ бэкенда на `/auth/login` и `/auth/register`.
/// Содержит пару токенов и сведения о пользователе (`user`).
private struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case user
    }

    struct AuthUser: Decodable {
        let id: UUID
        let email: String
        let username: String
        let isAdmin: Bool

        enum CodingKeys: String, CodingKey {
            case id, email, username
            case isAdmin = "is_admin"
        }
    }
}
