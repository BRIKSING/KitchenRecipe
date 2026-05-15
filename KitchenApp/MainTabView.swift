import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            RecipeListView()
                .tabItem { Label("Рецепты", systemImage: "fork.knife") }

            CategoryView()
                .tabItem { Label("Категории", systemImage: "square.grid.2x2") }

            SettingsView()
                .tabItem { Label("Профиль", systemImage: "person.circle") }
        }
        .tint(.orange)
    }
}
