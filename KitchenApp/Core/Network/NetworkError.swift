import Foundation

enum NetworkError: LocalizedError {
    case noConnection
    case unauthorized
    case serverError(Int, String)
    case decodingError(Error)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "Нет подключения к интернету"
        case .unauthorized:
            return "Сессия истекла. Войдите снова"
        case .serverError(let code, let message):
            return "Ошибка сервера (\(code)): \(message)"
        case .decodingError:
            return "Ошибка обработки данных"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
