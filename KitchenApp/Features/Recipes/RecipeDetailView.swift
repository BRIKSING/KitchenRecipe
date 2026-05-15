import SwiftUI

struct RecipeDetailView: View {
    let recipeId: UUID
    @StateObject private var viewModel = RecipeViewModel()
    @State private var recipe: Recipe?

    var body: some View {
        Group {
            if let recipe {
                ScrollView {
                    Text(recipe.title).font(.title.bold()).padding()
                }
                .navigationTitle(recipe.title)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ProgressView()
            }
        }
        .task {
            recipe = try? await viewModel.loadDetail(id: recipeId)
        }
    }
}
