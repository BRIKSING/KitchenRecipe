import Foundation

@MainActor
final class CategoryViewModel: ObservableObject {
    @Published var categories: [RecipeCategory] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let api = APIClient.shared

    func loadCategories() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            categories = try await api.request(.categories)
            error = nil
        } catch {
            self.error = error
            ErrorBannerState.shared.show(error)
        }
    }
}
