import Foundation

// MARK: - CommentsRatingViewModel

/// Manages comments and ratings for a single recipe.
@MainActor
final class CommentsRatingViewModel: ObservableObject {

    // MARK: Published state

    @Published var comments: [RecipeComment]  = []
    @Published var rating: RecipeRating?
    @Published var isLoadingComments = false
    @Published var isSendingComment  = false
    @Published var hasMoreComments   = true
    @Published var commentText       = ""

    // MARK: Private

    private let api = APIClient.shared
    private var commentsPage = 1

    // MARK: - Comments

    func loadComments(recipeId: UUID, reset: Bool = false) async {
        if reset {
            commentsPage   = 1
            comments       = []
            hasMoreComments = true
        }
        guard !isLoadingComments, hasMoreComments else { return }

        isLoadingComments = true
        defer { isLoadingComments = false }

        do {
            let response: PaginatedResponse<RecipeComment> = try await api.request(
                .recipeComments(recipeId: recipeId, page: commentsPage)
            )
            comments       += response.data
            hasMoreComments = response.hasMore
            commentsPage   += 1
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }

    func sendComment(recipeId: UUID) async {
        let trimmed = commentText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isSendingComment = true
        defer { isSendingComment = false }

        do {
            let body = CreateCommentRequest(text: trimmed)
            let new: RecipeComment = try await api.request(.addComment(recipeId: recipeId), body: body)
            commentText = ""
            comments.insert(new, at: 0)
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }

    func deleteComment(recipeId: UUID, commentId: UUID) async {
        do {
            let _: ActionResult = try await api.request(
                .deleteComment(recipeId: recipeId, commentId: commentId)
            )
            withAnimation { comments.removeAll { $0.id == commentId } }
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }

    // MARK: - Ratings

    func loadRating(recipeId: UUID) async {
        do {
            let r: RecipeRating = try await api.request(.recipeRating(recipeId: recipeId))
            withAnimation { rating = r }
        } catch {
            // Non-fatal — ratings section is optional
        }
    }

    func submitRating(recipeId: UUID, stars: Int) async {
        do {
            let body    = RateRecipeRequest(rating: stars)
            let updated: RecipeRating = try await api.request(.rateRecipe(recipeId: recipeId), body: body)
            withAnimation { rating = updated }
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }
}
