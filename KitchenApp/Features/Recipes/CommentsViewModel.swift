import Foundation

// MARK: - CommentsViewModel

@MainActor
final class CommentsViewModel: ObservableObject {

    // MARK: Published state

    @Published var comments: [Comment] = []
    @Published var ratingStats: RatingStats?
    @Published var isLoading = false
    @Published var isSubmitting = false

    // MARK: Private

    private let api = APIClient.shared
    private var currentPage = 1
    private(set) var hasMore = true

    // MARK: - Load

    /// Сбрасывает состояние и загружает первую страницу + статистику рейтинга.
    func loadInitial(recipeId: UUID) async {
        currentPage = 1
        hasMore = true
        comments = []
        async let commentsLoad: () = loadMore(recipeId: recipeId)
        async let statsLoad: () = loadRatingStats(recipeId: recipeId)
        _ = await (commentsLoad, statsLoad)
    }

    /// Загружает следующую страницу комментариев.
    func loadMore(recipeId: UUID) async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let query = CommentsQuery(page: currentPage)
            let response: PaginatedResponse<Comment> = try await api.request(.recipeComments(recipeId, query))
            comments += response.items
            hasMore = response.hasMore
            currentPage += 1
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }

    /// Отдельная загрузка статистики рейтинга (не блокирует список).
    func loadRatingStats(recipeId: UUID) async {
        do {
            ratingStats = try await api.request(.recipeRatingStats(recipeId))
        } catch {
            // Статистика опциональна — ошибку не показываем
        }
    }

    // MARK: - Mutations

    /// Добавляет новый комментарий. Если задан rating — сервер обновляет рейтинг рецепта.
    @discardableResult
    func addComment(recipeId: UUID, text: String, rating: Int?) async -> Bool {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let body = CreateCommentRequest(text: text, rating: rating)
            let comment: Comment = try await api.request(.createComment(recipeId), body: body)
            comments.insert(comment, at: 0)
            if rating != nil {
                await loadRatingStats(recipeId: recipeId)
            }
            return true
        } catch {
            ErrorBannerState.shared.show(error)
            return false
        }
    }

    /// Удаляет комментарий (только автор).
    func deleteComment(recipeId: UUID, commentId: UUID) async {
        do {
            let _: EmptyResponse = try await api.request(.deleteComment(recipeId: recipeId, commentId: commentId))
            comments.removeAll { $0.id == commentId }
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }

    /// Ставит или обновляет оценку рецепта (без текста комментария).
    @discardableResult
    func rateRecipe(recipeId: UUID, rating: Int) async -> Bool {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            ratingStats = try await api.request(.rateRecipe(recipeId), body: CreateRatingRequest(rating: rating))
            return true
        } catch {
            ErrorBannerState.shared.show(error)
            return false
        }
    }
}
