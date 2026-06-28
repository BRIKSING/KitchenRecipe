import Foundation

// MARK: - Domain models (Этап 6)
//
// Доменные/DTO-модели приложения и их декодирование из JSON бэкенда.
// `CodingKeys` приводят snake_case-поля API к camelCase Swift
// (`cook_time_min` → `cookTimeMin`, `cover_image_url` → `coverImageURL`,
// `sort_order` → `sortOrder` и т.д.). Дата декодируется стратегией `.iso8601`,
// настроенной в `APIClient`. Для списков используется дженерик
// `PaginatedResponse<T>` с вычисляемым `hasMore`.

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
    let items: [T]
    let total: Int
    let page: Int
    let perPage: Int
    let pages: Int

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case page
        case perPage  = "per_page"
        case pages
    }

    /// Бэкенд отдаёт общее число страниц (`pages`), а не флаг `has_more`.
    /// Вычисляем наличие следующей страницы локально.
    var hasMore: Bool { page < pages }
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

// MARK: - Comments query

struct CommentsQuery {
    var page: Int = 1
    var perPage: Int = 20

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "page",     value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
    }
}

// MARK: - Comment author

struct CommentAuthor: Codable {
    let id: UUID
    let username: String
}

// MARK: - Comment

struct Comment: Codable, Identifiable {
    let id: UUID
    let author: CommentAuthor
    let text: String
    let rating: Int?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, author, text, rating
        case createdAt = "created_at"
    }
}

// MARK: - Rating stats

struct RatingStats: Decodable {
    let average: Double
    let count: Int
}

// MARK: - Comment & Rating requests

struct CreateCommentRequest: Encodable {
    let text: String
    let rating: Int?
}

struct CreateRatingRequest: Encodable {
    let rating: Int
}

// MARK: - Utility

struct EmptyResponse: Decodable {}
