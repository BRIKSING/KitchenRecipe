import Foundation

/// Типизированные ошибки сетевого слоя (Этап 6).
///
/// `APIClient` маппит на эти кейсы все сбои запроса, а `LocalizedError`
/// даёт готовые локализованные сообщения для показа через `ErrorBanner`:
/// - `noConnection` — нет сети (триггерит retry с backoff);
/// - `unauthorized` — `401` (триггерит refresh-токен flow / редирект на логин);
/// - `serverError(code, message)` — ответ `4xx/5xx` с телом ошибки;
/// - `decodingError` — ответ не соответствует ожидаемой модели;
/// - `unknown` — прочие непредвиденные ошибки.
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
