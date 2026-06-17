import Foundation
import Combine

@MainActor
final class RecipeViewModel: ObservableObject {
    @Published var recipes: [RecipeListItem] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var hasMore = true
    @Published var categories: [RecipeCategory] = []
    @Published var tags: [Tag] = []

    private let api = APIClient.shared
    private var currentPage = 1

    func loadRecipes(query: RecipesQuery, reset: Bool = false) async {
        guard !isLoading else { return }
        if reset {
            currentPage = 1
            recipes = []
            hasMore = true
            error = nil
        }
        guard hasMore else { return }

        isLoading = true
        defer { isLoading = false }

        var q = query
        q.page = currentPage

        do {
            let response: PaginatedResponse<RecipeListItem> = try await api.request(.recipes(q))
            recipes += response.items
            hasMore = response.hasMore
            currentPage += 1
        } catch {
            self.error = error
            ErrorBannerState.shared.show(error)
        }
    }

    func loadDetail(id: UUID) async throws -> Recipe {
        try await api.request(.recipe(id))
    }

    func loadCategories() async {
        guard categories.isEmpty else { return }
        do {
            let cats: [RecipeCategory] = try await api.request(.categories)
            categories = cats
        } catch {
            // Non-fatal
        }
    }

    func loadTags(q: String? = nil) async {
        do {
            // GET /tags отдаёт пагинированную обёртку { items, total, ... },
            // а не голый массив — декодируем и берём items.
            let response: PaginatedResponse<Tag> = try await api.request(.tags(q: q))
            tags = response.items
        } catch {
            // Non-fatal
        }
    }
}
