import SwiftUI
import SwiftData

@main
struct KitchenRecipeApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        SecurityAudit.run()
        #if DEBUG
        injectUITestingState()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(authViewModel)
            .errorBanner()
        }
        .modelContainer(for: [DraftRecipe.self, CachedRecipeDetail.self])
    }

    #if DEBUG
    // Allows XCUITests to bypass real auth by injecting a placeholder token.
    // Only active in DEBUG builds when the launch argument is present.
    private func injectUITestingState() {
        guard CommandLine.arguments.contains("UI_TESTING_BYPASS_AUTH") else { return }
        APIClient.shared.setTokens(
            access: "ui-test-access-token",
            refresh: "ui-test-refresh-token"
        )
    }
    #endif
}
