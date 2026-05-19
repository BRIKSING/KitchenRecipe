import SwiftUI

// MARK: - CategoryView

struct CategoryView: View {
    @StateObject private var viewModel = CategoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.categories.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.error != nil && viewModel.categories.isEmpty {
                    errorState
                } else if viewModel.categories.isEmpty {
                    ContentUnavailableView(
                        "Нет категорий",
                        systemImage: "square.grid.2x2",
                        description: Text("Категории пока не добавлены")
                    )
                } else {
                    categoryGrid
                }
            }
            .navigationTitle("Категории")
        }
        .task { await viewModel.loadCategories() }
    }

    // MARK: - Grid

    private var categoryGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 16)],
                spacing: 16
            ) {
                ForEach(viewModel.categories) { category in
                    NavigationLink {
                        CategoryRecipesView(category: category)
                    } label: {
                        CategoryCardView(category: category)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .refreshable { await viewModel.loadCategories() }
    }

    // MARK: - Error state

    private var errorState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Не удалось загрузить категории")
                .font(.headline)
            Button("Повторить") {
                Task { await viewModel.loadCategories() }
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - CategoryCardView

struct CategoryCardView: View {
    let category: RecipeCategory

    private var accentColor: Color {
        let palette: [Color] = [.orange, .blue, .green, .purple, .pink, .teal, .red, .indigo, .cyan, .mint]
        return palette[abs(category.slug.hashValue) % palette.count]
    }

    private var icon: String {
        let slug = category.slug.lowercased()
        if slug.contains("pasta") || slug.contains("макар") { return "fork.knife" }
        if slug.contains("soup") || slug.contains("суп") { return "cup.and.saucer.fill" }
        if slug.contains("salad") || slug.contains("салат") { return "leaf.fill" }
        if slug.contains("dessert") || slug.contains("sweet") || slug.contains("десерт") { return "birthday.cake.fill" }
        if slug.contains("meat") || slug.contains("chicken") || slug.contains("мяс") { return "flame.fill" }
        if slug.contains("fish") || slug.contains("seafood") || slug.contains("рыб") { return "fish.fill" }
        if slug.contains("bread") || slug.contains("bak") || slug.contains("хлеб") { return "basket.fill" }
        if slug.contains("drink") || slug.contains("напит") { return "waterbottle.fill" }
        if slug.contains("breakfast") || slug.contains("завтрак") { return "sun.and.horizon.fill" }
        return "fork.knife.circle.fill"
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 60, height: 60)
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(accentColor)
            }
            Text(category.name)
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - CategoryRecipesView

struct CategoryRecipesView: View {
    let category: RecipeCategory

    @StateObject private var viewModel = RecipeViewModel()
    @State private var query = RecipesQuery()

    private let adaptiveColumns = [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)]

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.recipes.isEmpty {
                skeletonGrid
            } else if viewModel.error != nil && viewModel.recipes.isEmpty {
                errorState
            } else if viewModel.recipes.isEmpty {
                ContentUnavailableView(
                    "Нет рецептов",
                    systemImage: "fork.knife",
                    description: Text("В этой категории пока нет рецептов")
                )
            } else {
                recipeGrid
            }
        }
        .navigationTitle(category.name)
        .navigationDestination(for: UUID.self) { id in
            RecipeDetailView(recipeId: id)
        }
        .task {
            query.category = category.id
            await viewModel.loadRecipes(query: query, reset: true)
        }
    }

    private var recipeGrid: some View {
        ScrollView {
            LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                ForEach(viewModel.recipes) { recipe in
                    NavigationLink(value: recipe.id) {
                        RecipeCardView(recipe: recipe)
                    }
                    .buttonStyle(.plain)
                    .task {
                        if recipe.id == viewModel.recipes.last?.id {
                            await viewModel.loadRecipes(query: query)
                        }
                    }
                }
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .padding()
        }
        .refreshable { await viewModel.loadRecipes(query: query, reset: true) }
    }

    private var skeletonGrid: some View {
        ScrollView {
            LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                ForEach(0..<6, id: \.self) { _ in SkeletonCardView() }
            }
            .padding()
        }
    }

    private var errorState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Не удалось загрузить рецепты")
                .font(.headline)
            Button("Повторить") {
                Task { await viewModel.loadRecipes(query: query, reset: true) }
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
