import Foundation
import Observation

// MARK: - CommentsViewModel

@Observable
final class CommentsViewModel {

    // MARK: State

    var comments: [Comment] = []
    var rating: RecipeRating?
    var isLoadingComments = false
    var isLoadingRating = false
    var isSubmittingComment = false
    var isSubmittingRating = false
    var hasMore = false
    var error: String?

    private var currentPage = 1
    private let perPage = 20
    private var recipeId: UUID?

    private let client = APIClient.shared

    // MARK: - Load

    func loadAll(recipeId: UUID) async {
        self.recipeId = recipeId
        async let commentsTask: () = loadCommentsFirst(recipeId: recipeId)
        async let ratingTask: ()   = loadRating(recipeId: recipeId)
        _ = await (commentsTask, ratingTask)
    }

    private func loadCommentsFirst(recipeId: UUID) async {
        isLoadingComments = true
        currentPage = 1
        defer { isLoadingComments = false }
        do {
            let page: PaginatedResponse<Comment> = try await client.request(
                .comments(recipeId: recipeId, page: 1, perPage: perPage)
            )
            comments = page.data
            hasMore  = page.hasMore
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore(recipeId: UUID) async {
        guard hasMore, !isLoadingComments else { return }
        isLoadingComments = true
        defer { isLoadingComments = false }
        let nextPage = currentPage + 1
        do {
            let page: PaginatedResponse<Comment> = try await client.request(
                .comments(recipeId: recipeId, page: nextPage, perPage: perPage)
            )
            comments.append(contentsOf: page.data)
            hasMore      = page.hasMore
            currentPage  = nextPage
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadRating(recipeId: UUID) async {
        isLoadingRating = true
        defer { isLoadingRating = false }
        do {
            let r: RecipeRating = try await client.request(.recipeRating(recipeId: recipeId))
            rating = r
        } catch {
            // Rating may not exist yet — silently ignore 404
        }
    }

    // MARK: - Post comment

    func postComment(recipeId: UUID, text: String) async throws {
        isSubmittingComment = true
        defer { isSubmittingComment = false }
        let body = CreateCommentRequest(text: text)
        let newComment: Comment = try await client.request(.postComment(recipeId: recipeId), body: body)
        comments.insert(newComment, at: 0)
    }

    // MARK: - Delete comment

    func deleteComment(recipeId: UUID, commentId: UUID) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await client.request(.deleteComment(recipeId: recipeId, commentId: commentId))
        comments.removeAll { $0.id == commentId }
    }

    // MARK: - Rate recipe

    func rate(recipeId: UUID, stars: Int) async throws {
        isSubmittingRating = true
        defer { isSubmittingRating = false }
        let body = RateRecipeRequest(rating: stars)
        let updated: RecipeRating = try await client.request(.rateRecipe(recipeId: recipeId), body: body)
        rating = updated
    }
}
