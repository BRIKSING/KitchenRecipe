import Foundation

/// Унифицированные ошибки сетевого слоя.
///
/// Все запросы `APIClient` выбрасывают именно `NetworkError`, что позволяет
/// UI единообразно реагировать на разные классы сбоев:
/// - ``noConnection`` — нет сети; запускает retry с экспоненциальной задержкой
///   и переключение на офлайн-кэш;
/// - ``unauthorized`` — 401; триггерит refresh access-токена, а при неудаче —
///   возврат на экран логина;
/// - ``serverError`` — любой ответ 4xx/5xx (кроме 401) с кодом и телом;
/// - ``decodingError`` — ответ не удалось декодировать в ожидаемый тип;
/// - ``unknown`` — прочие непредвиденные ошибки.
///
/// Тип реализует `LocalizedError`, поэтому `errorDescription` отдаёт готовое
/// сообщение на русском для показа через ``ErrorBannerState``.
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
