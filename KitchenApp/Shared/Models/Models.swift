import Foundation

// MARK: - User

struct User: Decodable, Identifiable {
    let id: UUID
    let email: String
    let username: String
}

// MARK: - Category

struct RecipeCategory: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let slug: String
}

// MARK: - Tag

struct Tag: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
}

// MARK: - Difficulty

enum Difficulty: String, Codable, CaseIterable {
    case easy
    case medium
    case hard

    var localizedName: String {
        switch self {
        case .easy:   return NSLocalizedString("difficulty.easy",   value: "Лёгкий",  comment: "")
        case .medium: return NSLocalizedString("difficulty.medium", value: "Средний", comment: "")
        case .hard:   return NSLocalizedString("difficulty.hard",   value: "Сложный", comment: "")
        }
    }
}

// MARK: - StepPhoto

struct StepPhoto: Codable, Identifiable {
    let id: UUID
    let url: URL
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case sortOrder = "sort_order"
    }
}

// MARK: - Step

struct Step: Codable, Identifiable {
    let id: UUID
    let sortOrder: Int
    let title: String
    let description: String
    let timerSec: Int?
    let photos: [StepPhoto]

    enum CodingKeys: String, CodingKey {
        case id
        case sortOrder  = "sort_order"
        case title
        case description
        case timerSec   = "timer_sec"
        case photos
    }
}

// MARK: - Ingredient

struct Ingredient: Codable, Identifiable {
    let id: UUID
    let name: String
    let amount: Double
    let unit: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case amount
        case unit
        case sortOrder = "sort_order"
    }
}

// MARK: - Recipe (list item)

struct RecipeListItem: Decodable, Identifiable {
    let id: UUID
    let title: String
    let difficulty: Difficulty
    let cookTimeMin: Int
    let servings: Int
    let coverImageURL: URL?
    let category: RecipeCategory?
    let tags: [Tag]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case difficulty
        case cookTimeMin    = "cook_time_min"
        case servings
        case coverImageURL  = "cover_image_url"
        case category
        case tags
    }
}

// MARK: - Recipe (full detail)

struct Recipe: Codable, Identifiable {
    let id: UUID
    let title: String
    let description: String?
    let difficulty: Difficulty
    let cookTimeMin: Int
    let servings: Int
    let coverImageURL: URL?
    let category: RecipeCategory?
    let tags: [Tag]
    let ingredients: [Ingredient]
    let steps: [Step]
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case difficulty
        case cookTimeMin    = "cook_time_min"
        case servings
        case coverImageURL  = "cover_image_url"
        case category
        case tags
        case ingredients
        case steps
        case createdAt      = "created_at"
        case updatedAt      = "updated_at"
    }
}

// MARK: - Paginated response

struct PaginatedResponse<T: Decodable>: Decodable {
    let data: [T]
    let total: Int
    let page: Int
    let perPage: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case data
        case total
        case page
        case perPage  = "per_page"
        case hasMore  = "has_more"
    }
}

// MARK: - Comment Author

struct CommentAuthor: Codable {
    let id: UUID
    let username: String
}

// MARK: - Recipe Comment

struct RecipeComment: Codable, Identifiable {
    let id: UUID
    let author: CommentAuthor
    let text: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, author, text
        case createdAt = "created_at"
    }
}

// MARK: - Recipe Rating

struct RecipeRating: Codable {
    let averageRating: Double
    let totalRatings: Int
    /// Current user's rating (1–5), nil if they haven't rated yet
    let userRating: Int?

    enum CodingKeys: String, CodingKey {
        case averageRating = "average_rating"
        case totalRatings  = "total_ratings"
        case userRating    = "user_rating"
    }
}

// MARK: - Requests for comments & ratings

struct CreateCommentRequest: Encodable {
    let text: String
}

struct RateRecipeRequest: Encodable {
    let rating: Int  // 1–5
}

// MARK: - Flexible action response (DELETE, etc.)

/// Accepts any JSON object — used when the response body isn't meaningful.
struct ActionResult: Decodable {
    let success: Bool?
    let id: UUID?

    private enum CodingKeys: String, CodingKey { case success, id }

    init(from decoder: Decoder) throws {
        let c  = try decoder.container(keyedBy: CodingKeys.self)
        success = try? c.decodeIfPresent(Bool.self, forKey: .success)
        id      = try? c.decodeIfPresent(UUID.self, forKey: .id)
    }
}

// MARK: - Auth responses

struct AuthTokens: Decodable {
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
    }
}

struct UploadResponse: Decodable {
    let url: URL
    let key: String
}
