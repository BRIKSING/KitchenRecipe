# Документация фронтенда — Kitchen (iOS/iPadOS)

Документация по реализованным этапам клиентской части приложения. Каждый
раздел описывает компоненты этапа, их назначение и точки взаимодействия с
остальной архитектурой.

---

## Этап 6 — iOS: базовая структура

Фундамент iOS-клиента: каркас Xcode-проекта, разбиение на слои, базовый
сетевой слой (`URLSession` + `async/await`), перечисление эндпоинтов,
доменные модели с декодированием и глобальный показ ошибок.

### Стек и требования

| Параметр | Значение |
|---|---|
| Язык | Swift 5.9+ |
| UI | SwiftUI |
| Минимальная версия | iOS 17 / iPadOS 17 |
| Сеть | `URLSession` + `async/await` |
| Состояние | `@Observable` / `ObservableObject` |
| Хранилище | SwiftData (черновики, офлайн-кэш) |

### Структура проекта

Проект организован по принципу разделения слоёв (MVVM):

```
KitchenApp/
├── KitchenRecipeApp.swift   — точка входа (@main), сборка сцены и контейнера
├── MainTabView.swift        — корневой TabBar
├── Core/                    — инфраструктура, не зависящая от фич
│   ├── Network/             — APIClient, Endpoint, NetworkError, KeychainService
│   ├── Cache/               — кэш изображений и рецептов
│   ├── Persistence/         — SwiftData (черновики)
│   ├── Vision/              — распознавание жестов рук
│   ├── Speech/              — голосовые команды
│   ├── Sync/                — синхронизация (CloudKit)
│   └── Security/            — аудит безопасности
├── Features/                — экраны и ViewModel по доменам
│   ├── Auth/  Recipes/  Cooking/  Editor/  Categories/  Settings/
├── Shared/                  — переиспользуемое между фичами
│   ├── Models/              — DTO и доменные модели
│   ├── Components/          — общие View-компоненты (в т.ч. ErrorBanner)
│   └── Extensions/          — расширения стандартных типов
└── Resources/               — Assets, локализация (ru.lproj / en.lproj)
```

### Точка входа

`KitchenRecipeApp.swift` (`@main`) собирает сцену: в зависимости от
`AuthViewModel.isAuthenticated` показывает `MainTabView` либо `LoginView`,
прокидывает зависимости через окружение и подключает глобальный баннер
ошибок модификатором `.errorBanner()`. Здесь же создаётся `ModelContainer`
SwiftData.

### Сетевой слой

#### `APIClient` (`Core/Network/APIClient.swift`)

Синглтон `APIClient.shared` — единая точка доступа к REST API бэкенда.

- **Базовый URL** берётся из `UserDefaults` (ключ `serverURL`, по умолчанию
  `http://localhost:3000`) и может переопределяться через `updateBaseURL(_:)`
  из экрана Настроек.
- **Дженерик-запрос** `request<T: Decodable>(_:body:) async throws -> T` —
  собирает `URLRequest` из `Endpoint`, добавляет `Authorization: Bearer`,
  кодирует тело в JSON и декодирует ответ в указанную модель.
- **Загрузка изображений** `upload(imageData:mimeType:to:)` — формирует
  `multipart/form-data` и возвращает `UploadResponse` (`url` + S3-`key`).
- **Обновление токена** — при ответе `401` один раз вызывает
  `/auth/refresh` (refresh-токен в заголовке `Authorization: Bearer`),
  сохраняет новый access-токен и повторяет исходный запрос.
- **Retry** — для `NetworkError.noConnection` до 3 попыток с экспоненциальной
  задержкой (2/4/8 с).
- Токены хранятся в Keychain через `KeychainService`.

#### `Endpoint` (`Core/Network/Endpoint.swift`)

`enum` со всеми маршрутами API и ассоциированными значениями (идентификаторы,
тела запросов, query-параметры). Вычисляемые свойства дают `APIClient` всё для
сборки запроса:

- `path` — путь относительно базового URL;
- `method` — HTTP-метод (`GET` / `POST` / `PUT` / `DELETE`);
- `queryItems` — параметры строки запроса (поиск, фильтры, пагинация).

Здесь же объявлены тела запросов (`RegisterRequest`, `LoginRequest`,
`RecipeCreateRequest`, `IngredientInput`) и структура `RecipesQuery`,
формирующая `URLQueryItem` для `GET /recipes` (UUID нормализуются в нижний
регистр, теги передаются повторяющимся параметром `tags`).

#### `NetworkError` (`Core/Network/NetworkError.swift`)

Типизированные ошибки (`LocalizedError`) с готовыми локализованными
сообщениями: `noConnection`, `unauthorized`, `serverError(code, message)`,
`decodingError`, `unknown`. На них завязаны retry-логика, обновление токена
и показ баннера.

### Доменные модели

`Shared/Models/Models.swift` — DTO и доменные модели и их декодирование из
JSON бэкенда:

- сущности: `User`, `RecipeCategory`, `Tag`, `Difficulty`, `Ingredient`,
  `Step`, `StepPhoto`, `RecipeListItem` (карточка списка) и `Recipe` (полные
  данные);
- `CodingKeys` приводят snake_case API к camelCase Swift (`cook_time_min` →
  `cookTimeMin`, `cover_image_url` → `coverImageURL`, `sort_order` →
  `sortOrder`);
- даты декодируются стратегией `.iso8601` (настроена в `APIClient`);
- `PaginatedResponse<T: Decodable>` — дженерик-обёртка пагинированного ответа
  (`items/total/page/per_page/pages`) с вычисляемым `hasMore`;
- вспомогательные типы ответов: `AuthTokens`, `UploadResponse`,
  `EmptyResponse`.

### Глобальный баннер ошибок

`Shared/Components/ErrorBannerModifier.swift`:

- `ErrorBannerState.shared` — общий источник сообщения; любой слой вызывает
  `show(_:)` (со строкой или `Error`), баннер появляется поверх экрана и
  скрывается через заданный `duration` (по умолчанию 4 с);
- модификатор `.errorBanner()` подключается один раз в корне сцены
  (`KitchenRecipeApp`) и становится доступен всему приложению;
- визуально — красный баннер сверху с иконкой, текстом и кнопкой закрытия,
  анимированным появлением/скрытием.

### Связь с другими этапами

- **Этап 7 (Auth)** использует `APIClient` и `KeychainService` для
  login/register и refresh-flow.
- **Этап 8 (Список/детали)** строится на `Endpoint.recipes/recipe`,
  моделях `RecipeListItem`/`Recipe` и `PaginatedResponse`.
- Все экраны полагаются на `.errorBanner()` для единообразного показа ошибок.
