import SwiftUI
import SwiftData

@main
struct KitchenRecipeApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    /// Configured once at launch: uses CloudKit when iCloud sync is enabled,
    /// falls back to local-only storage if CloudKit is unavailable.
    private static let sharedModelContainer: ModelContainer = makeModelContainer()

    init() {
        SecurityAudit.run()
        #if DEBUG
        injectUITestingState()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            // Защищённый роутинг: корневой экран выбирается по флагу
            // AuthViewModel.isAuthenticated. Пока токенов в Keychain нет — показываем
            // LoginView; после успешного login/register (или наличия токена при
            // запуске) SwiftUI пересобирает Group и подменяет его на MainTabView.
            Group {
                if authViewModel.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(authViewModel)
            .environment(CloudKitSyncService.shared)
            .errorBanner()
        }
        .modelContainer(Self.sharedModelContainer)
    }

    // MARK: - SwiftData container (with optional CloudKit)

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([DraftRecipe.self, CachedRecipeDetail.self])

        // Determine whether CloudKit should be active for this launch.
        // configureLaunchSync() also records the decision for the restart-hint logic.
        let useCloudKit = CloudKitSyncService.configureLaunchSync()

        if useCloudKit {
            do {
                // cloudKitDatabase: .automatic — uses the default iCloud container
                // (requires iCloud + CloudKit capabilities in the Xcode project).
                let config = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .automatic
                )
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                // CloudKit unavailable (e.g. no entitlements, Simulator, no iCloud account).
                // Degrade gracefully to local-only so the app remains fully functional.
                print("[Sync] CloudKit container init failed — falling back to local storage. Error: \(error)")
            }
        }

        // Local-only storage
        do {
            let config = ModelConfiguration(schema: schema)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("[KitchenRecipeApp] Failed to create local ModelContainer: \(error)")
        }
    }

    // MARK: - UI-Testing helpers

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
