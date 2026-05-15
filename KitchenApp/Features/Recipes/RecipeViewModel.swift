import Foundation
import Combine

@MainActor
final class RecipeViewModel: ObservableObject {
    @Published var recipes: [RecipeListItem] = []
    @Published var isLoading = false
    @Published var hasMore = true

    private let api = APIClient.shared
    private var currentPage = 1

    func loadRecipes(query: RecipesQuery, reset: Bool = false) async {
        guard !isLoading else { return }
        if reset {
            currentPage = 1
            recipes = []
            hasMore = true
        }
        guard hasMore else { return }

        isLoading = true
        defer { isLoading = false }

        var q = query
        q.page = currentPage

        do {
            let response: PaginatedResponse<RecipeListItem> = try await api.request(.recipes(q))
            recipes += response.data
            hasMore = response.hasMore
            currentPage += 1
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }

    func loadDetail(id: UUID) async throws -> Recipe {
        try await api.request(.recipe(id))
    }
}
