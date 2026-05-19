import Foundation
import SwiftData

@Model
final class CachedRecipeDetail {
    var recipeId: String
    var recipeData: Data
    var title: String
    var cachedAt: Date

    init(recipeId: UUID, recipeData: Data, title: String) {
        self.recipeId = recipeId.uuidString
        self.recipeData = recipeData
        self.title = title
        self.cachedAt = Date()
    }

    func decode() -> Recipe? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Recipe.self, from: recipeData)
    }
}
