import SwiftUI
import SwiftData

@main
struct KitchenRecipeApp: App {
    @StateObject private var authViewModel = AuthViewModel()

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
        .modelContainer(for: [DraftRecipe.self])
    }
}
