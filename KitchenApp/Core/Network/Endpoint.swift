import Foundation

// MARK: - Recipes query

struct RecipesQuery {
    var q: String?
    var category: UUID?
    var tags: [UUID] = []
    var difficulty: Difficulty?
    var maxTime: Int?
    var page: Int = 1
    var perPage: Int = 20

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page",     value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        if let q          = q          { items.append(.init(name: "q",          value: q)) }
        // UUID в фильтрах шлём в нижнем регистре: `Foundation.UUID.uuidString`
        // отдаёт строку в ВЕРХНЕМ регистре, а бэкенд хранит id в колонках типа
        // `String`/`text` (Prisma `@default(uuid())` генерирует строчные UUID) и
        // сравнивает их регистрозависимо (`where.category_id = category`,
        // `tag_id: { in: ... }`). Без нормализации фильтр по категории/тегам
        // никогда не совпадает и молча возвращает пустой список.
        if let category   = category   { items.append(.init(name: "category",   value: category.uuidString.lowercased())) }
        if let difficulty = difficulty { items.append(.init(name: "difficulty",  value: difficulty.rawValue)) }
        if let maxTime    = maxTime    { items.append(.init(name: "max_time",    value: String(maxTime))) }
        // Бэкенд (Fastify, парсер querystring по умолчанию) ожидает повторяющийся
        // параметр `tags`, а не `tags[]`: recipeFiltersSchema читает `tags` как
        // union(string | string[]). Скобки в имени ломают фильтрацию по тегам.
        tags.forEach { items.append(.init(name: "tags", value: $0.uuidString.lowercased())) }
        return items
    }
}

// MARK: - Request bodies

struct RegisterRequest: Encodable {
    let email: String
    let username: String
    let password: String
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

/// Ингредиент в теле `POST /recipes`. Бэкенд принимает ингредиенты инлайн
/// (`ingredientInputSchema`): `amount` — число (nullable), `unit` — строка
/// (nullable), `sort_order` — целое (по умолчанию 0).
struct IngredientInput: Encodable {
    let name: String
    let amount: Double?
    let unit: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case name
        case amount
        case unit
        case sortOrder = "sort_order"
    }
}

struct RecipeCreateRequest: Encodable {
    let title: String
    let description: String?
    let categoryId: UUID?
    let difficulty: String
    let cookTimeMin: Int
    let servings: Int
    // Бэкенд `createRecipeSchema` хранит `cover_image` как S3-ключ (не URL),
    // который возвращает `POST /upload/image` в поле `key`.
    let coverImage: String?
    let ingredients: [IngredientInput]?
    let tagIds: [UUID]?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case categoryId  = "category_id"
        case difficulty
        case cookTimeMin = "cook_time_min"
        case servings
        case coverImage  = "cover_image"
        case ingredients
        case tagIds      = "tag_ids"
    }
}

// MARK: - Endpoint

enum Endpoint {
    // Auth
    case register(RegisterRequest)
    case login(LoginRequest)
    case refreshToken(String)
    case logout

    // Recipes
    case recipes(RecipesQuery)
    case recipe(UUID)
    case createRecipe(RecipeCreateRequest)
    case updateRecipe(UUID, RecipeCreateRequest)
    case deleteRecipe(UUID)
    case publishRecipe(UUID)

    // Steps
    case steps(recipeId: UUID)
    case createStep(recipeId: UUID)
    case updateStep(recipeId: UUID, stepId: UUID)
    case deleteStep(recipeId: UUID, stepId: UUID)
    case reorderSteps(recipeId: UUID)

    // Photos
    case uploadStepPhoto(stepId: UUID)
    case deleteStepPhoto(stepId: UUID, photoId: UUID)
    case reorderStepPhotos(stepId: UUID)

    // Categories & Tags
    case categories
    case createCategory
    case tags(q: String?)

    // Upload
    case uploadImage

    // Comments & Ratings
    case recipeComments(UUID, CommentsQuery)
    case createComment(UUID)
    case deleteComment(recipeId: UUID, commentId: UUID)
    case recipeRatingStats(UUID)
    case rateRecipe(UUID)

    var path: String {
        switch self {
        case .register:                         return "/auth/register"
        case .login:                            return "/auth/login"
        case .refreshToken:                     return "/auth/refresh"
        case .logout:                           return "/auth/logout"

        case .recipes:                          return "/recipes"
        case .recipe(let id):                   return "/recipes/\(id)"
        case .createRecipe:                     return "/recipes"
        case .updateRecipe(let id, _):          return "/recipes/\(id)"
        case .deleteRecipe(let id):             return "/recipes/\(id)"
        case .publishRecipe(let id):            return "/recipes/\(id)/publish"

        case .steps(let recipeId):              return "/recipes/\(recipeId)/steps"
        case .createStep(let recipeId):         return "/recipes/\(recipeId)/steps"
        case .updateStep(let rid, let sid):     return "/recipes/\(rid)/steps/\(sid)"
        case .deleteStep(let rid, let sid):     return "/recipes/\(rid)/steps/\(sid)"
        case .reorderSteps(let recipeId):       return "/recipes/\(recipeId)/steps/reorder"

        case .uploadStepPhoto(let stepId):      return "/steps/\(stepId)/photos"
        case .deleteStepPhoto(let sid, let pid):return "/steps/\(sid)/photos/\(pid)"
        case .reorderStepPhotos(let stepId):    return "/steps/\(stepId)/photos/reorder"

        case .categories, .createCategory:           return "/categories"
        case .tags:                                  return "/tags"
        case .uploadImage:                           return "/upload/image"

        case .recipeComments(let id, _):             return "/recipes/\(id)/comments"
        case .createComment(let id):                 return "/recipes/\(id)/comments"
        case .deleteComment(let rid, let cid):       return "/recipes/\(rid)/comments/\(cid)"
        case .recipeRatingStats(let id):             return "/recipes/\(id)/rating"
        case .rateRecipe(let id):                    return "/recipes/\(id)/rating"
        }
    }

    var method: String {
        switch self {
        case .recipes, .recipe, .steps, .categories, .tags,
             .recipeComments, .recipeRatingStats:
            return "GET"
        case .register, .login, .refreshToken, .logout,
             .createRecipe, .createStep, .publishRecipe,
             .uploadStepPhoto, .reorderSteps, .reorderStepPhotos,
             .createCategory, .uploadImage,
             .createComment, .rateRecipe:
            return "POST"
        case .updateRecipe, .updateStep:
            return "PUT"
        case .deleteRecipe, .deleteStep, .deleteStepPhoto,
             .deleteComment:
            return "DELETE"
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .recipes(let query):            return query.queryItems
        case .tags(let q):                   return q.map { [.init(name: "q", value: $0)] }
        case .recipeComments(_, let q):      return q.queryItems
        default:                             return nil
        }
    }
}
