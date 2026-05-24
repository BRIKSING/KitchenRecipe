import Foundation
import SwiftData

// MARK: - FavoriteRecipe
//
// Локальная копия метаданных избранного рецепта (SwiftData).
// Хранит базовую информацию для отображения в FavoritesView без сетевого запроса.
// Обновляется при каждом посещении RecipeDetailView.

@Model
final class FavoriteRecipe {
    var recipeId: String        // UUID в строковом виде
    var title: String
    var coverImageURL: String?
    var difficulty: String
    var cookTimeMin: Int
    var categoryName: String?
    var addedAt: Date
    /// true, когда запись создана по данным из iCloud, но детали ещё не загружены с сервера
    var needsRefresh: Bool

    // MARK: - Designated init (полные данные)

    init(
        recipeId: UUID,
        title: String,
        coverImageURL: URL?,
        difficulty: Difficulty,
        cookTimeMin: Int,
        categoryName: String?
    ) {
        self.recipeId      = recipeId.uuidString
        self.title         = title
        self.coverImageURL = coverImageURL?.absoluteString
        self.difficulty    = difficulty.rawValue
        self.cookTimeMin   = cookTimeMin
        self.categoryName  = categoryName
        self.addedAt       = Date()
        self.needsRefresh  = false
    }

    // MARK: - Placeholder init (только ID, данные придут после загрузки)

    init(placeholder id: UUID) {
        self.recipeId     = id.uuidString
        self.title        = ""
        self.difficulty   = Difficulty.easy.rawValue
        self.cookTimeMin  = 0
        self.addedAt      = Date()
        self.needsRefresh = true
    }

    // MARK: - Computed helpers

    var parsedID: UUID? {
        UUID(uuidString: recipeId)
    }

    var coverURL: URL? {
        coverImageURL.flatMap { URL(string: $0) }
    }

    var difficultyEnum: Difficulty {
        Difficulty(rawValue: difficulty) ?? .easy
    }

    // MARK: - Convenience updaters

    func update(from recipe: Recipe) {
        title         = recipe.title
        coverImageURL = recipe.coverImageURL?.absoluteString
        difficulty    = recipe.difficulty.rawValue
        cookTimeMin   = recipe.cookTimeMin
        categoryName  = recipe.category?.name
        needsRefresh  = false
    }

    func update(from item: RecipeListItem) {
        title         = item.title
        coverImageURL = item.coverImageURL?.absoluteString
        difficulty    = item.difficulty.rawValue
        cookTimeMin   = item.cookTimeMin
        categoryName  = item.category?.name
        needsRefresh  = false
    }
}
