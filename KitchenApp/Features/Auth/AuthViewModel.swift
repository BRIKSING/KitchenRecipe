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
            let tokens: AuthTokens = try await api.request(.login(body), body: body)
            api.setTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
            storeUserInfo(email: email, username: nil)
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
            storeUserInfo(email: email, username: username)
            isAuthenticated = true
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }

    func logout() {
        Task {
            try? await api.request(.logout) as EmptyResponse
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

// EmptyResponse (для эндпоинтов без тела ответа, напр. logout)
// определён в Shared/Models/Models.swift — здесь дублировать нельзя
// (иначе "Invalid redeclaration of 'EmptyResponse'").
