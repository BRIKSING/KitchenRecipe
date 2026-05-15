import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false

    private let api = APIClient.shared

    func login(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let body = LoginRequest(email: email, password: password)
            let tokens: AuthTokens = try await api.request(.login(body), body: body)
            api.setTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
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
            let tokens: AuthTokens = try await api.request(.register(body), body: body)
            api.setTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
            isAuthenticated = true
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }

    func logout() {
        Task {
            try? await api.request(.logout) as EmptyResponse
            api.clearTokens()
            isAuthenticated = false
        }
    }
}

// Helper for endpoints that return no body
struct EmptyResponse: Decodable {}
