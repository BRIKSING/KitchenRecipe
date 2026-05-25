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
            .environmentObject(ICloudSyncService.shared)
            .errorBanner()
        }
        // Draft recipes: try CloudKit-backed store first (requires iCloud entitlement +
        // iCloud key-value store capability in the Xcode project). Falls back to local
        // storage gracefully if CloudKit is unavailable or the entitlement is missing.
        //
        // CachedRecipeDetail is always kept local — it is device-specific cache only
        // and does not need to follow the user across devices.
        .modelContainer(buildModelContainer())
    }

    // MARK: - ModelContainer factory

    private func buildModelContainer() -> ModelContainer {
        // Attempt 1: CloudKit-backed drafts + local cache (two separate stores)
        if let container = tryBuildCloudKitContainer() {
            return container
        }
        // Attempt 2: fully local fallback
        return buildLocalContainer()
    }

    /// Returns a `ModelContainer` where `DraftRecipe` is backed by CloudKit (private DB)
    /// and `CachedRecipeDetail` lives in a separate, local-only store.
    ///
    /// Throws if the app lacks the required CloudKit entitlement or iCloud is unavailable.
    private func tryBuildCloudKitContainer() -> ModelContainer? {
        guard ICloudSyncService.shared.isICloudAvailable else { return nil }
        return try? ModelContainer(
            for: DraftRecipe.self, CachedRecipeDetail.self,
            configurations:
                // Drafts — iCloud private database; auto-resolves to the bundle's container ID.
                ModelConfiguration(
                    "KitchenDrafts",
                    schema: Schema([DraftRecipe.self]),
                    cloudKitDatabase: .automatic
                ),
                // Cache — local only; no CloudKit.
                ModelConfiguration(
                    "KitchenCache",
                    schema: Schema([CachedRecipeDetail.self]),
                    cloudKitDatabase: .none
                )
        )
    }

    /// Fully local fallback — no iCloud required.
    private func buildLocalContainer() -> ModelContainer {
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: [DraftRecipe.self, CachedRecipeDetail.self])
    }

    // MARK: - UI Testing

    #if DEBUG
    /// Allows XCUITests to bypass real auth by injecting a placeholder token.
    /// Only active in DEBUG builds when the launch argument is present.
    private func injectUITestingState() {
        guard CommandLine.arguments.contains("UI_TESTING_BYPASS_AUTH") else { return }
        APIClient.shared.setTokens(
            access: "ui-test-access-token",
            refresh: "ui-test-refresh-token"
        )
    }
    #endif
}
