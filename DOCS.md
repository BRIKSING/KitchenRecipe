# Документация фронтенда Kitchen (iOS/iPadOS)

Документация по реализованным и проверенным этапам клиентской части приложения.
Каждый раздел соответствует этапу из `SPEC.md` (§5 «Этапы разработки»).

---

## Этап 6 — iOS: базовая структура

Фундамент iOS-клиента: структура проекта, сетевой слой (`URLSession` +
`async/await`), типобезопасные эндпоинты, доменные модели с декодированием и
глобальный механизм показа ошибок.

### Состав этапа

| Подзадача | Где реализовано |
|---|---|
| Создание Xcode-проекта (SwiftUI, iOS 17+) | `KitchenApp/KitchenRecipeApp.swift`, `KitchenApp/MainTabView.swift` |
| Структура папок (Core / Features / Shared / Resources) | дерево `KitchenApp/` |
| `APIClient` — базовый сетевой слой | `KitchenApp/Core/Network/APIClient.swift` |
| `Endpoint` enum — все эндпоинты | `KitchenApp/Core/Network/Endpoint.swift` |
| Доменные модели + декодирование | `KitchenApp/Shared/Models/Models.swift` |
| Глобальный `ErrorBanner` модификатор | `KitchenApp/Shared/Components/ErrorBannerModifier.swift` |

### Структура проекта

Приложение организовано по слоям согласно `SPEC.md` §2.2:

```
KitchenApp/
├── Core/
│   ├── Network/        — APIClient, Endpoint, NetworkError, KeychainService
│   ├── Cache/          — ImageCache
│   ├── Persistence/    — SwiftData (черновики, офлайн-кэш)
│   └── Vision/         — HandGestureDetector, GestureType
├── Features/           — экраны по фичам (Auth, Recipes, Cooking, Editor, …)
├── Shared/
│   ├── Components/     — переиспользуемые View (ErrorBanner, CachedAsyncImage …)
│   ├── Extensions/     — расширения стандартных типов
│   └── Models/         — DTO и доменные модели
└── Resources/          — Assets, Localizable.strings
```

Стадия 6 закладывает содержимое `Core/Network`, `Shared/Models` и
`Shared/Components/ErrorBannerModifier.swift`.

### Сетевой слой: `APIClient`

`APIClient` — синглтон (`APIClient.shared`), единая точка доступа к REST-API
поверх `URLSession` и `async/await`.

**Зоны ответственности:**

- **Сборка запроса.** Метод `buildRequest(_:body:)` берёт путь, HTTP-метод и
  query-параметры из `Endpoint`, добавляет заголовок
  `Authorization: Bearer <access>` из `KeychainService`, а тело (`Encodable`)
  сериализует в JSON.
- **Декодирование.** Ответ декодируется в произвольный `Decodable`-тип `T`.
  `JSONDecoder` настроен на `dateDecodingStrategy = .iso8601` — даты с сервера
  (`created_at`, `updated_at`) парсятся автоматически.
- **Базовый URL.** Берётся из `UserDefaults` (ключ `serverURL`, по умолчанию
  `http://localhost:3000`) и меняется в рантайме через `updateBaseURL(_:)`
  (используется экраном настроек).
- **Авторизация при `401`.** При `NetworkError.unauthorized` клиент один раз
  пытается обновить access-токен через `POST /auth/refresh` (refresh-токен
  передаётся в заголовке `Authorization: Bearer`, не в теле) и повторяет
  исходный запрос с новым токеном. Если refresh не удался — пробрасывает
  `unauthorized` (UI уводит на экран логина).
- **Retry сети.** При `NetworkError.noConnection` выполняется до 3 попыток с
  экспоненциальной задержкой (`2^n` секунд) — `execute(_:endpoint:retries:)`.
- **Multipart-загрузка.** `upload(imageData:mimeType:to:)` формирует тело
  `multipart/form-data` (поле `file`) и возвращает `UploadResponse`
  (URL + S3-ключ).
- **Logout.** `logout()` дёргает `POST /auth/logout`, передавая
  **refresh-токен** в заголовке (бэкенд ревокирует именно его); ответ 204 без
  тела, сетевые ошибки игнорируются — локальные токены чистит вызывающая
  сторона.

**Публичный API:**

```swift
func request<T: Decodable>(_ endpoint: Endpoint, body: Encodable? = nil) async throws -> T
func upload(imageData: Data, mimeType: String = "image/jpeg", to endpoint: Endpoint) async throws -> UploadResponse
func updateBaseURL(_ url: URL)
func setTokens(access: String, refresh: String)
func clearTokens()
func logout() async
var isAuthenticated: Bool { get }
```

**Пример вызова:**

```swift
let response: PaginatedResponse<RecipeListItem> =
    try await APIClient.shared.request(.recipes(RecipesQuery(q: "паста")))
```

### Обработка ошибок: `NetworkError`

`NetworkError` — единый тип ошибок сетевого слоя, реализующий `LocalizedError`:

| Кейс | Когда | Реакция UI |
|---|---|---|
| `noConnection` | сеть недоступна | retry + переключение на офлайн-кэш |
| `unauthorized` | HTTP 401 | refresh токена → при неудаче возврат к логину |
| `serverError(Int, String)` | 4xx/5xx (кроме 401) | баннер с кодом и сообщением |
| `decodingError(Error)` | ответ не декодируется | баннер «Ошибка обработки данных» |
| `unknown(Error)` | прочее | баннер с `localizedDescription` |

`errorDescription` отдаёт готовые сообщения на русском — их напрямую показывает
баннер ошибок.

### Эндпоинты: `Endpoint`

`Endpoint` — `enum` с ассоциированными значениями, типобезопасно описывающий
все маршруты API. Из кейса детерминированно выводятся три свойства:

- `path: String` — путь маршрута (с подстановкой id);
- `method: String` — HTTP-метод (`GET` / `POST` / `PUT` / `DELETE`);
- `queryItems: [URLQueryItem]?` — query-параметры (для списков и поиска).

Покрытые группы маршрутов: **Auth** (`register`, `login`, `refreshToken`,
`logout`), **Recipes** (CRUD + `publish`), **Steps** (CRUD + `reorder`),
**Photos** (загрузка/удаление/reorder), **Categories & Tags**, **Upload**, а
также **Comments & Ratings**.

**`RecipesQuery`** инкапсулирует параметры `GET /recipes` (поиск `q`,
`category`, `tags`, `difficulty`, `max_time`, пагинация) и собирает корректные
`URLQueryItem`. Важные нюансы совместимости с бэкендом, заложенные в коде:

- UUID в фильтрах отправляются в **нижнем регистре** (`uuidString.lowercased()`):
  `Foundation.UUID` отдаёт строку в верхнем регистре, а Prisma хранит и
  сравнивает id регистрозависимо — иначе фильтр молча возвращает пустой список;
- теги передаются повторяющимся параметром `tags`, а **не** `tags[]` — этого
  ждёт парсер querystring Fastify.

### Доменные модели и декодирование

`Shared/Models/Models.swift` содержит DTO/доменные модели, повторяющие формат
ответов бэкенда (`SPEC.md` §3.6). Поля `snake_case` сервера мапятся в
`camelCase` Swift через `CodingKeys`.

**Ключевые типы:**

- `User`, `RecipeCategory`, `Tag`, `Difficulty` (`enum` с локализованными
  названиями) — базовые сущности;
- `Ingredient`, `Step`, `StepPhoto` — части рецепта;
- `RecipeListItem` — облегчённая модель карточки для списка (`GET /recipes`);
- `Recipe` — полная модель рецепта с ингредиентами и шагами
  (`GET /recipes/{id}`);
- `PaginatedResponse<T>` — обёртка постраничных ответов; `hasMore` вычисляется
  локально как `page < pages` (бэкенд отдаёт общее число страниц `pages`, а не
  флаг);
- `AuthTokens`, `UploadResponse`, `EmptyResponse` — служебные ответы.

Разделение на «лёгкую» (`RecipeListItem`) и «полную» (`Recipe`) модели
снижает объём трафика и парсинга для экрана списка.

### Глобальный баннер ошибок: `ErrorBanner`

Механизм единообразного показа ошибок поверх любого экрана.

- **`ErrorBannerState`** — `ObservableObject`-синглтон (`shared`) с
  `@Published var message`. Методы `show(_:duration:)` и `show(_:)` (для
  `Error`) выставляют сообщение и автоматически скрывают его по таймеру;
  повторный вызов сбрасывает предыдущий отложенный показ.
- **`ErrorBannerView`** — всплывающий сверху баннер (красный градиент, иконка,
  текст, кнопка закрытия) с анимацией `move + opacity`.
- **`errorBanner()`** — модификатор `View`, накладывающий баннер как `overlay`
  сверху. Подключается один раз к корневому контейнеру.

**Подключение и использование:**

```swift
// корневой контейнер
MainTabView()
    .errorBanner()

// показать ошибку из любого места
ErrorBannerState.shared.show(NetworkError.noConnection)
```

---
