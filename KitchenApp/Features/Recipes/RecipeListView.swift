import SwiftUI

struct RecipeListView: View {
    @StateObject private var viewModel = RecipeViewModel()
    @State private var query = RecipesQuery()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.recipes.isEmpty && viewModel.isLoading {
                    ProgressView("Загрузка рецептов…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.recipes.isEmpty {
                    ContentUnavailableView("Рецепты не найдены",
                                           systemImage: "fork.knife",
                                           description: Text("Попробуйте изменить фильтры"))
                } else {
                    recipeGrid
                }
            }
            .navigationTitle("Рецепты")
        }
        .task { await viewModel.loadRecipes(query: query, reset: true) }
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
            }
            .padding()
        }
        .refreshable { await viewModel.loadRecipes(query: query, reset: true) }
    }

    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)]
    }
}

struct RecipeCardView: View {
    let recipe: RecipeListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CachedAsyncImage(url: recipe.coverImageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().foregroundStyle(.secondary.opacity(0.2))
            }
            .frame(height: 120)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(recipe.cookTimeMin.formattedDuration, systemImage: "clock")
                    Label(recipe.difficulty.localizedName, systemImage: "chart.bar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}
