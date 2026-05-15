import Foundation

// MARK: - User

struct User: Decodable, Identifiable {
    let id: UUID
    let email: String
    let username: String
}

// MARK: - Category

struct RecipeCategory: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let slug: String
}

// MARK: - Tag

struct Tag: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String
}

// MARK: - Difficulty

enum Difficulty: String, Decodable, CaseIterable {
    case easy
    case medium
    case hard

    var localizedName: String {
        switch self {
        case .easy:   return "Лёгкий"
        case .medium: return "Средний"
        case .hard:   return "Сложный"
        }
    }
}

// MARK: - StepPhoto

struct StepPhoto: Decodable, Identifiable {
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

struct Step: Decodable, Identifiable {
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

struct Ingredient: Decodable, Identifiable {
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

struct Recipe: Decodable, Identifiable {
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
