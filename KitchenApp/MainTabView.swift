import SwiftUI

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var sidebarSelection: SidebarTab? = .recipes

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadLayout
        } else {
            phoneLayout
        }
    }

    // MARK: - Phone layout

    private var phoneLayout: some View {
        TabView {
            RecipeListView()
                .tabItem { Label("Рецепты", systemImage: "fork.knife") }

            CategoryView()
                .tabItem { Label("Категории", systemImage: "square.grid.2x2") }

            FavoritesView()
                .tabItem {
                    Label(
                        NSLocalizedString("favorites.tab", value: "Избранное", comment: ""),
                        systemImage: "heart.fill"
                    )
                }

            SettingsView()
                .tabItem { Label("Профиль", systemImage: "person.circle") }
        }
        .tint(.orange)
    }

    // MARK: - iPad layout (NavigationSplitView with sidebar)

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SidebarTab.allCases, id: \.self, selection: $sidebarSelection) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle(NSLocalizedString("sidebar.title", value: "Kitchen", comment: ""))
            .listStyle(.sidebar)
            .tint(.orange)
        } detail: {
            switch sidebarSelection ?? .recipes {
            case .recipes:    RecipeListView()
            case .categories: CategoryView()
            case .favorites:  FavoritesView()
            case .settings:   SettingsView()
            }
        }
        .tint(.orange)
    }
}

// MARK: - Sidebar tab model

private enum SidebarTab: CaseIterable, Hashable {
    case recipes, categories, favorites, settings

    var title: String {
        switch self {
        case .recipes:    return NSLocalizedString("Рецепты",   value: "Рецепты",   comment: "")
        case .categories: return NSLocalizedString("Категории", value: "Категории", comment: "")
        case .favorites:  return NSLocalizedString("favorites.tab", value: "Избранное", comment: "")
        case .settings:   return NSLocalizedString("Профиль",   value: "Профиль",   comment: "")
        }
    }

    var icon: String {
        switch self {
        case .recipes:    return "fork.knife"
        case .categories: return "square.grid.2x2"
        case .favorites:  return "heart.fill"
        case .settings:   return "person.circle"
        }
    }
}
