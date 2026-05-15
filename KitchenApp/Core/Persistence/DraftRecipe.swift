import Foundation
import SwiftData

@Model
final class DraftRecipe {
    var id: UUID
    var title: String
    var recipeDescription: String
    var categoryId: UUID?
    var difficulty: String
    var cookTimeMin: Int
    var servings: Int
    var coverImageData: Data?
    var ingredientsJSON: Data?
    var stepsJSON: Data?
    var tagsJSON: Data?
    var updatedAt: Date

    init() {
        id              = UUID()
        title           = ""
        recipeDescription = ""
        difficulty      = Difficulty.easy.rawValue
        cookTimeMin     = 30
        servings        = 2
        updatedAt       = Date()
    }
}
