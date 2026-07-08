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

## Этап 7 — iOS: аутентификация

Полный клиентский флоу авторизации: экраны входа и регистрации, вью-модель с
операциями login/register/logout, безопасное хранение токенов в Keychain,
прозрачное обновление access-токена (interceptor) и защищённый роутинг —
переключение на главный экран после успешной авторизации.

### Состав этапа

| Подзадача | Где реализовано |
|---|---|
| `LoginView` + `RegisterView` | `KitchenApp/Features/Auth/LoginView.swift`, `KitchenApp/Features/Auth/RegisterView.swift` |
| `AuthViewModel` — login/register/logout | `KitchenApp/Features/Auth/AuthViewModel.swift` |
| Хранение токенов в Keychain | `KitchenApp/Core/Network/KeychainService.swift` |
| Автообновление access-токена (interceptor) | `KitchenApp/Core/Network/APIClient.swift` |
| Защищённый роутинг (переход на главную) | `KitchenApp/KitchenRecipeApp.swift` |

### Вью-модель: `AuthViewModel`

`AuthViewModel` (`@MainActor`, `ObservableObject`) — единый источник состояния
авторизации. Создаётся один раз в корне приложения как `@StateObject` и
прокидывается в дерево через `environmentObject`.

**Публикуемое состояние:**

- `isAuthenticated: Bool` — главный флаг роутинга; при инициализации берётся из
  `APIClient.isAuthenticated` (т. е. из наличия токена в Keychain), поэтому при
  повторном запуске пользователь остаётся авторизованным;
- `isLoading: Bool` — индикатор выполнения запроса (блокирует кнопки, показывает
  `ProgressView`);
- `userEmail` / `userUsername` — неконфиденциальные данные профиля для экрана
  настроек.

**Операции:**

- `login(email:password:)` — `POST /auth/login`, при успехе сохраняет пару
  токенов через `APIClient.setTokens(...)` и поднимает `isAuthenticated`;
- `register(email:username:password:)` — `POST /auth/register`; бэкенд выдаёт
  токены сразу вместе с ответом, поэтому после регистрации пользователь сразу
  авторизован (отдельный логин не требуется);
- `logout()` — вызывает `APIClient.logout()` (ревокация refresh-токена на
  сервере), очищает Keychain и локальный профиль, опускает `isAuthenticated`.

Сетевые ошибки наружу не пробрасываются — они показываются глобальным баннером
`ErrorBannerState.shared.show(error)`. Конфиденциальные данные (токены) лежат
**только** в Keychain; в `UserDefaults` хранятся лишь email и username.

### Экраны входа и регистрации

**`LoginView`** — стартовый экран неавторизованного пользователя: поля
email/пароль, кнопка «Войти» (с `ProgressView` и блокировкой при пустых полях),
переход на `RegisterView` через `navigationDestination`.

**`RegisterView`** — форма регистрации (email, имя пользователя, пароль +
подтверждение). Ключевая деталь — **локальная валидация `isValid` повторяет
правила Zod-схемы бэкенда**, чтобы не отправлять заведомо отклоняемый запрос:

- email содержит `@`;
- username — 3–50 символов из латиницы, цифр и `_`;
- password — 8–100 символов;
- password совпадает с подтверждением.

Иначе бэкенд вернул бы `400 VALIDATION_ERROR`. Кнопка «Создать аккаунт»
заблокирована, пока форма невалидна.

Оба экрана не вызывают сеть напрямую — только методы `AuthViewModel`. После
успеха переключение экранов делает корневой `App` по `isAuthenticated`, а не сам
экран.

### Хранение токенов: `KeychainService`

`KeychainService` — stateless-`enum` (только статические члены) поверх
Security-фреймворка. Хранит access- и refresh-токены как
`kSecClassGenericPassword`.

- **Доступность `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`:** токены
  читаются только на разблокированном устройстве и **не** мигрируют в iCloud
  Keychain или зашифрованные бэкапы — это требование безопасности из `SPEC.md`
  (§4: «Шифрование», и финальный security-review).
- **Типобезопасные аксессоры** `accessToken` / `refreshToken` — get/set,
  присваивание `nil` удаляет запись; `clearAll()` стирает обе записи при выходе.
- Низкоуровневые `SecItemAdd/CopyMatching/Delete` скрыты в приватных
  примитивах `save/load/delete`; `save` сначала делает `SecItemDelete`, чтобы
  перезапись токена была идемпотентной.

### Interceptor: автообновление access-токена

Логика «прозрачного» refresh реализована в `APIClient` (документирована в
рамках Этапа 6, здесь — со стороны auth-флоу):

1. Любой запрос подставляет `Authorization: Bearer <access>` из Keychain.
2. При ответе `401` (`NetworkError.unauthorized`) клиент **один раз** дёргает
   `POST /auth/refresh`, передавая **refresh-токен в заголовке**
   `Authorization: Bearer` (а не в теле), сохраняет новый access-токен в
   Keychain и повторяет исходный запрос с обновлённым заголовком.
3. Если refresh не удался — пробрасывается `unauthorized`; UI (корневой `App`)
   по сбросу авторизации возвращает пользователя на `LoginView`.

`logout()` тоже использует refresh-токен в заголовке — бэкенд ревокирует именно
его; ответ `204 No Content`, поэтому тело не декодируется, а сетевые ошибки
игнорируются (локальные токены всё равно чистит `AuthViewModel`).

### Защищённый роутинг

Корневой `KitchenRecipeApp` держит `AuthViewModel` как `@StateObject` и по
`isAuthenticated` выбирает корневой экран:

```swift
Group {
    if authViewModel.isAuthenticated {
        MainTabView()
    } else {
        LoginView()
    }
}
.environmentObject(authViewModel)
.errorBanner()
```

Это единственная точка ветвления — экраны входа/регистрации не выполняют навигацию
сами, а лишь меняют состояние во вью-модели. В `DEBUG`-сборках для XCUITests
предусмотрен обход авторизации (`UI_TESTING_BYPASS_AUTH` инжектит плейсхолдер-токены).

---

## Этап 8 — iOS: список и детали рецепта

Витрина рецептов: адаптивная сетка карточек с поиском, фильтрацией, пагинацией
и pull-to-refresh, экран детальной карточки рецепта (hero-фото с параллаксом,
мета-блок, ингредиенты с масштабированием порций, превью шагов) и двухуровневый
кэш изображений (память + диск).

### Состав этапа

| Подзадача | Где реализовано |
|---|---|
| `RecipeListView` — сетка карточек (LazyVGrid, 2/3/4 колонки) | `KitchenApp/Features/Recipes/RecipeListView.swift` |
| `RecipeCardView` — карточка (обложка, название, мета) | `KitchenApp/Features/Recipes/RecipeListView.swift` |
| Поиск (`searchable` + debounce) | `KitchenApp/Features/Recipes/RecipeListView.swift` |
| Фильтр-шторка (категория, сложность, время) | `FilterSheetView` в `RecipeListView.swift` |
| Чипы активных фильтров | `FilterChip` / `filterChips` в `RecipeListView.swift` |
| Пагинация (infinity scroll) | `RecipeListView.swift` + `RecipeViewModel.swift` |
| Pull-to-refresh | `RecipeListView.swift` (`refreshable`) |
| `RecipeDetailView` — hero, мета, ингредиенты, превью шагов | `KitchenApp/Features/Recipes/RecipeDetailView.swift` |
| Масштабирование порций (×0.5/×1/×2/×3) | `RecipeDetailView.swift` |
| Кэширование изображений (NSCache + disk) | `KitchenApp/Core/Cache/ImageCache.swift`, `KitchenApp/Shared/Components/CachedAsyncImage.swift` |

Общий слой данных обоих экранов — `RecipeViewModel`
(`KitchenApp/Features/Recipes/RecipeViewModel.swift`).

### Вью-модель: `RecipeViewModel`

`RecipeViewModel` (`@MainActor`, `ObservableObject`) обслуживает и список, и
деталь рецепта. Публикуемое состояние: `recipes`, `isLoading`, `error`,
`hasMore`, а также справочники `categories` и `tags` для фильтр-шторки.

**Пагинация (`loadRecipes(query:reset:)`).** Ключевой метод загрузки списка:

- хранит приватный `currentPage` (начиная с 1) и инкрементирует его после
  каждой успешной страницы;
- `reset: true` (первая загрузка, новый поиск/фильтр, pull-to-refresh)
  обнуляет страницу, очищает `recipes` и поднимает `hasMore`;
- защита от гонок: `guard !isLoading` отбрасывает параллельные вызовы (важно,
  потому что триггер пагинации в списке срабатывает на `.task` последней
  карточки), а `guard hasMore` прекращает дозагрузку на последней странице;
- новые элементы **аппендятся** (`recipes += response.items`), а флаг
  `hasMore` берётся из `PaginatedResponse.hasMore` (`page < pages` —
  вычисляется на клиенте, см. Этап 6);
- сетевые ошибки сохраняются в `error` (для экрана с кнопкой retry) **и**
  показываются глобальным баннером `ErrorBannerState.shared.show(error)`.

**Деталь и справочники.** `loadDetail(id:)` пробрасывает `GET /recipes/:id`
наверх (ошибки обрабатывает сам экран — ему нужен офлайн-fallback).
`loadCategories()` и `loadTags(q:)` грузят справочники для фильтра; их ошибки
**не** фатальны (молча игнорируются) — фильтр остаётся работоспособным и без них.

### Экран списка: `RecipeListView`

`NavigationStack` с переключением состояний по данным вью-модели:

- **загрузка первой страницы** (`isLoading && recipes.isEmpty`) → `skeletonGrid`
  (плейсхолдеры `SkeletonCardView` с shimmer-анимацией);
- **ошибка без данных** (`error != nil && recipes.isEmpty`) → `errorState` с
  кнопкой «Повторить»;
- **пустой результат** → системный `ContentUnavailableView`;
- **данные** → `recipeGrid`.

**Адаптивная сетка.** `LazyVGrid` с `GridItem(.adaptive(...))`. Диапазон ширины
колонки зависит от `horizontalSizeClass`: на iPhone (`.compact`) — 155–240 pt
(≈2 колонки), на iPad (`.regular`) — 200–280 pt (3–4 колонки). Это покрывает
требование «2 колонки на iPhone, 3–4 на iPad» без жёсткого задания их числа.

**Пагинация (infinity scroll).** У каждой карточки есть `.task`, который при
появлении **последнего** элемента (`recipe.id == viewModel.recipes.last?.id`)
вызывает `loadRecipes(query:)` без `reset` — подгружается следующая страница.
Внизу сетки во время дозагрузки показывается `ProgressView`.

**Pull-to-refresh.** `.refreshable` на `ScrollView` перезагружает первую
страницу с `reset: true`.

**Поиск с debounce.** `searchable` связан с `searchText`; `onChange` вызывает
`scheduleSearch(_:)`, который отменяет предыдущую `Task` и ждёт **300 мс**
(`Task.sleep`) перед запросом — реализует debounce из `SPEC.md` §2.4 без
лишних обращений к сети при наборе. Пустая строка сбрасывает параметр `q` в
`nil`.

**Фильтры и чипы.** Кнопка в тулбаре открывает `FilterSheetView` (категория —
`Picker`, сложность — сегментированный контрол, максимальное время — `Stepper`
с шагом 5 мин, теги — мультиселект с поиском при количестве > 6). Шторка
работает на локальных `@State` и применяет их в `query` только по кнопке
«Применить», после чего перезагружает список. `hasActiveFilters` подсвечивает
иконку фильтра, а `filterChips` рисует горизонтальную ленту чипов активных
фильтров; нажатие на крестик чипа снимает отдельный фильтр, кнопка «Сбросить
всё» — очищает все. Любое изменение фильтра запускает `loadRecipes(reset: true)`.

**Навигация.** Карточка обёрнута в `NavigationLink(value: recipe.id)`, а
`navigationDestination(for: UUID.self)` открывает `RecipeDetailView(recipeId:)`.
Кнопка `+` в тулбаре открывает `RecipeEditorView` (Этап 11) как `sheet`.

### Компонент карточки: `RecipeCardView`

Карточка рецепта из `RecipeListItem` (облегчённая модель списка): обложка через
`CachedAsyncImage` (фиксированная высота 120 pt, `scaledToFill` + `clipped`),
название (до 2 строк), мета-строка (время + сложность через `Label`) и
горизонтальная лента до 3 тегов-капсул. Вся карточка — единый
accessibility-элемент (`children: .combine`) с локализованным
`accessibilityLabel` (`accessibility.recipe_card`).

Рядом определены вспомогательные `FilterChip` (чип фильтра с кнопкой удаления)
и `SkeletonCardView` (skeleton-плейсхолдер с бесконечной shimmer-анимацией).

### Экран детали: `RecipeDetailView`

Принимает `recipeId: UUID`, грузит рецепт в `.task` и до загрузки показывает
`ProgressView`. Контент — вертикальный `ScrollView` из секций, поверх которого
закреплена кнопка «Начать приготовление».

**Секции (по `SPEC.md` §2.5):**

1. **Hero с параллаксом** — `heroSection` через `GeometryReader` в именованном
   координатном пространстве `"scroll"`. При оттягивании вниз (`minY > 0`)
   обложка растягивается (высота `280 + extraOffset`) и смещается с
   коэффициентом 0.4 — классический stretch/parallax. Поверх — градиент и
   название с категорией.
2. **Мета-блок** — иконки время / порции / сложность с разделителями; каждый
   `metaItem` — отдельный accessibility-элемент.
3. **Теги** — горизонтальная лента капсул.
4. **Описание** — expandable: `lineLimit(isDescriptionExpanded ? nil : 3)` с
   кнопкой «Читать далее / Свернуть» и анимацией.
5. **Ингредиенты** — список с масштабированием порций (см. ниже).
6. **Шаги** — превью-список: кружок с номером, заголовок, опциональный таймер
   (`formattedTimer`) и миниатюра первого фото (минимальный `sortOrder`).
   Шаги и ингредиенты сортируются по `sortOrder` перед отрисовкой.
7. **Закреплённая кнопка** — `startCookingButton` поверх `ScrollView` в `ZStack`
   с фоном `.ultraThinMaterial`; открывает `CookingSessionView` (Этап 9) как
   `fullScreenCover`.

> Примечание: секции оценок и отзывов (`ratingSummarySection`,
> `commentsPreviewSection`) относятся к пост-MVP фичам и здесь не описываются.

**Масштабирование порций.** `servingsMultiplier` (1.0 по умолчанию)
переключается кнопками ×½ / ×1 / ×2 / ×3. `scaledServings` пересчитывает число
порций в мета-блоке (минимум 1), `scaledAmount` — количество каждого
ингредиента: целые значения показываются без дробной части, иначе — с одним
знаком после запятой; единица измерения берётся из `ingredient.unit`. Смена
множителя анимируется через `contentTransition(.numericText())`.

**Поделиться.** В тулбаре — `ShareLink` с текстом рецепта и deeplink
`kitchenrecipe://recipe/<id>` (Share Sheet).

**Офлайн-fallback.** `loadRecipe()` при успехе кэширует рецепт в SwiftData
(`CachedRecipeDetail`), а при `NetworkError.noConnection` подставляет ранее
закэшированную версию и показывает офлайн-баннер. (Детальнее офлайн-режим
документируется в Этапе 12 — здесь это лишь точка интеграции.)

### Кэш изображений: `ImageCache` + `CachedAsyncImage`

Реализует требование `SPEC.md` §2.11 — двухуровневый кэш с TTL 7 дней.

**`ImageCache`** (синглтон `shared`) — два уровня:

- **Память** — `NSCache<NSString, UIImage>`, лимиты `countLimit = 100` и
  `totalCostLimit = 50 MB`; «стоимость» элемента оценивается по числу пикселей
  (`imageCost`), чтобы NSCache корректно вытеснял крупные изображения.
- **Диск** — каталог `Caches/ImageCache/`. Ключ файла — экранированный
  `absoluteString` URL. При чтении проверяется возраст файла по
  `modificationDate`: если он старше **TTL = 7 дней**, запись считается
  протухшей и игнорируется. Прочитанное с диска изображение поднимается обратно
  в память. На диск пишется JPEG (`compressionQuality 0.85`).

`image(for:)` идёт память → диск; `store(_:for:)` пишет в оба уровня;
`prefetch(url:)` — фоновая предзагрузка, если изображения ещё нет в кэше.

**`CachedAsyncImage`** — drop-in замена `AsyncImage` с тем же API
(`url`, `content`, `placeholder`). В `.task(id: url)` сначала спрашивает
`ImageCache`, при промахе грузит по сети через `URLSession`, кладёт результат
в кэш и показывает. Используется и в карточках списка, и в hero/миниатюрах
детали — поэтому повторные показы тех же обложек идут из кэша без сети.

---

## Этап 9 — iOS: режим приготовления

Ключевой экран приложения — полноэкранный пошаговый режим готовки
(`CookingSessionView`, `SPEC.md` §2.6): слайдер фото шага с pinch-to-zoom,
прогресс-бар и навигация кнопками/свайпом, таймер обратного отсчёта с
сохранением состояния между шагами и звуковым сигналом (`TimerService`),
блокировка автоблокировки экрана на время сессии и финальный экран «Готово!»
с анимацией.

### Состав этапа

| Подзадача | Где реализовано |
|---|---|
| `CookingSessionView` — полноэкранный пошаговый режим | `KitchenApp/Features/Cooking/CookingSessionView.swift` |
| Слайдер фотографий шага (`TabView` + `PageTabViewStyle` + pinch-to-zoom) | `photoSlider` в `CookingSessionView.swift` |
| Прогресс-бар и навигация (кнопки + swipe-жест) | `progressBar`, `bottomNavBar`, `navigateNext/navigatePrev` в `CookingSessionView.swift` |
| `TimerService` — обратный отсчёт, пауза, звуковой сигнал | `KitchenApp/Features/Cooking/TimerService.swift` |
| Блокировка автоблокировки экрана | `CookingSessionView.swift` (`isIdleTimerDisabled`) |
| Экран завершения («Готово!» + анимация) | `CompletionView` в `CookingSessionView.swift` |

Экран открывается из `RecipeDetailView` как `fullScreenCover` по кнопке
«Начать приготовление» (Этап 8) и принимает уже загруженный `Recipe`.

### Экран: `CookingSessionView`

`CookingSessionView` — `View`, работающий поверх полной модели рецепта.
Все шаги один раз сортируются по `sortOrder` (`sortedSteps`), а текущий шаг
адресуется индексом `currentStepIndex` (`@State`). Экран собран как
вертикальный стек фиксированной раскладки (`SPEC.md` §2.6):

```
progressBar → headerBar → photoSlider → stepScrollContent → bottomNavBar
```

Поверх этого стека в `ZStack` лежат оверлеи распознавания жестов и голосовых
команд, а также экран завершения. Ключевые вычисляемые свойства: `currentStep`,
`totalSteps` и `stepProgress` (`(currentStepIndex + 1) / totalSteps`).

**Жизненный цикл (`onAppear` / `onDisappear`):**

- при появлении — **отключается автоблокировка экрана**
  (`UIApplication.shared.isIdleTimerDisabled = true`, требование `SPEC.md`
  §2.6), настраивается таймер первого шага и подключаются обработчики жестов и
  голоса;
- при исчезновении — автоблокировка **возвращается**
  (`isIdleTimerDisabled = false`), а таймер, детектор жестов и распознавание
  речи останавливаются. Это гарантирует, что камера/микрофон и фоновый отсчёт
  не живут дольше сессии.

**Реакция на смену шага (`onChange(of: currentStepIndex)`):** сохраняет
состояние таймера уходящего шага, сбрасывает пейджер фото (`photoPage = 0`) и
масштаб зума, затем конфигурирует таймер нового шага (см. ниже).

> Кнопки «Жесты» и «Голос», оверлеи `HandsFreeOverlayView` /
> `VoiceCommandOverlayView` и обработка `scenePhase` относятся к Этапу 10
> (Hands-Free) и пост-MVP голосовым командам — здесь это лишь точки интеграции.

### Слайдер фотографий шага: `photoSlider`

Фото текущего шага (отсортированные по `sortOrder`) показываются в `TabView`
со стилем `.page(indexDisplayMode: .never)` — горизонтальный пейджинг свайпом.
Если фото нет — плейсхолдер `photo`. Изображения грузятся через
`CachedAsyncImage` (двухуровневый кэш из Этапа 8).

**Pinch-to-zoom.** Каждое фото реагирует на `MagnificationGesture`:
`photoScale` ограничен диапазоном **1.0…4.0** (`lastPhotoScale` хранит масштаб
между жестами), а при возврате почти к единице (`< 1.05`) пружиной
доводится до `1.0`. Двойной тап переключает масштаб между `1.0` и `2.5`.
Смена шага сбрасывает зум.

**Индикатор страниц.** При количестве фото > 1 внизу рисуется кастомный
dot-indicator (активная точка крупнее и ярче) с анимацией по `photoPage` —
отдельно от системного индикатора `TabView`, отключённого `indexDisplayMode:
.never`.

### Прогресс и навигация

**Прогресс-бар** (`progressBar`) — тонкая (4 pt) полоса вверху экрана:
оранжевая заливка шириной `geo.size.width * stepProgress` заполняется по мере
прохождения шагов с анимацией по `currentStepIndex`. В `headerBar` дублируется
текстовый прогресс «Шаг N из M» с локализованным accessibility-лейблом.

**Нижняя панель** (`bottomNavBar`) содержит кнопки «Назад» / «Вперёд» и
`stepDots` между ними. Логика переходов:

- `navigateNext()` — на последнем шаге вместо перехода показывает экран
  завершения (`showCompletion = true`); иначе инкрементирует индекс с анимацией.
  На последнем шаге кнопка меняет подпись на «Готово» и иконку на галочку;
- `navigatePrev()` — декремент с защитой `currentStepIndex > 0`; кнопка
  «Назад» задизейблена и приглушена на первом шаге.

**Свайп-жест.** На панель навесен `DragGesture` (минимум 40 pt): срабатывает
только на **преимущественно горизонтальном** движении (`abs(dx) > abs(dy) *
1.2`) — свайп влево ведёт вперёд, вправо — назад. Это дублирует кнопки
жестом, не мешая вертикальному скроллу описания.

**`stepDots`.** Точечный индикатор шагов с «окном»: показывается не более
9 точек, окно центрируется вокруг текущего шага (`start`/`end` считаются от
`currentStepIndex`), поэтому индикатор остаётся компактным даже у длинных
рецептов. Активная точка крупнее и оранжевая, переходы анимируются пружиной.

### Таймер шага: `TimerService` + сохранение состояния

**`TimerService`** (`@MainActor`, `ObservableObject`) — обратный отсчёт одного
шага. Публикует `remaining` (секунды), `isRunning`, `isFinished`.

- `configure(seconds:)` — задаёт новый отсчёт с нуля (сбрасывает `isFinished`);
- `restore(remaining:total:isFinished:)` — восстанавливает ранее сохранённое
  состояние (для возврата на шаг);
- `toggle()` / `resume()` / `pause()` / `stop()` — управление ходом. Отсчёт
  реализован через `Task` с `Task.sleep` (1 секунда), уменьшающий `remaining`;
  `pause`/`stop` отменяют задачу (`runTask?.cancel()`);
- по достижении нуля — `isRunning = false`, `isFinished = true` и **сигнал
  окончания**: системный звук (`AudioServicesPlaySystemSound(1315)`) и/или
  вибрация (`kSystemSoundID_Vibrate`). Оба переключаются флагами `timer.sound`
  и `timer.haptic` в `UserDefaults` (по умолчанию оба включены; их задаёт
  `SettingsView`, Этап 12);
- `formattedTime` форматирует остаток как `MM:SS` (расширение `formattedTimer`
  из `Shared/Extensions`).

**UI таймера** (`timerControl`) рисуется только для шагов с `timerSec > 0`:
монопространственное время (зелёное после окончания, с
`contentTransition(.numericText())`), кнопка play/pause, кнопка сброса
(`arrow.counterclockwise`) и метка «Время вышло!» по завершении.

**Сохранение состояния между шагами** (`SPEC.md` §2.6 — «таймер сохраняет
состояние при переключении шагов»). Так как `TimerService` один на всю
сессию, состояние каждого шага держится в словаре
`timerStates: [Int: (remaining, isFinished)]`:

- `saveTimerState(for:)` при уходе с шага кладёт `(remaining, isFinished)` в
  словарь и ставит таймер на паузу;
- `configureTimerForStep(_:)` при входе на шаг с таймером либо **восстанавливает**
  сохранённое состояние (`restore`), либо задаёт свежий отсчёт (`configure`);
- кнопка сброса очищает `timerStates[currentStepIndex]`, чтобы повторный вход
  начинал отсчёт заново.

Таким образом, отойдя на предыдущий шаг и вернувшись, пользователь видит
таймер там же, где оставил.

### Экран завершения: `CompletionView`

После `navigateNext()` на последнем шаге поверх сессии показывается
`CompletionView` (`transition(.opacity)`, `zIndex(1)`): круги-ореолы с крупной
галочкой, заголовок «Готово!» и подзаголовок «Приятного аппетита!». Анимация
появления двухфазная — пружинное масштабирование иконки (`iconScale` 0.3 → 1.0)
и последующее проявление текста/кнопок (`contentOpacity`).

Кнопка «Оценить рецепт» открывает `RateRecipeSheet` (пост-MVP оценки), кнопка
«Закрыть» вызывает `onClose` → `dismiss()`, закрывая `fullScreenCover` и
возвращая пользователя в `RecipeDetailView`.

---

## Этап 10 — iOS: Hands-Free режим

Управление шагами готовки жестами рук перед фронтальной камерой (`SPEC.md`
§2.7): пользователь с занятыми/грязными руками листает шаги, ставит таймер на
паузу и подтверждает действия, не касаясь экрана. Видеопоток анализируется
**локально** через Vision Framework (`VNDetectHumanHandPoseRequest`) и **не**
передаётся на сервер. Слой полностью клиентский — на бэкенде нет ни одного
gesture/camera/vision-эндпоинта.

### Состав этапа

| Подзадача | Где реализовано |
|---|---|
| Запрос разрешения камеры (Info.plist + runtime prompt) | `HandGestureDetector.start()`, `SettingsView.cameraPermissionRow`, `CookingSessionView.startHandsFree()` |
| `AVCaptureSession` + `VNDetectHumanHandPoseRequest` | `KitchenApp/Core/Vision/HandGestureDetector.swift` |
| Жест «открытая ладонь + свайп» (по дельте запястья) | `detectSwipe(from:)` в `HandGestureDetector.swift` |
| Жест «сжатый кулак» (удержание 1 сек) | `isFist(_:)` + `fistDetectedAt` в `HandGestureDetector.swift` |
| Жест «два пальца V» | `isVictory(_:)` в `HandGestureDetector.swift` |
| Оверлей с индикацией распознанного жеста | `KitchenApp/Features/Cooking/HandsFreeOverlayView.swift` |
| Задержка между срабатываниями 1.5 сек | `cooldown` в `HandGestureDetector.swift` |
| Настройка чувствительности в `SettingsView` | `handsFreeSection` в `KitchenApp/Features/Settings/SettingsView.swift` |
| Автоотключение при сворачивании приложения | `onChange(of: scenePhase)` в `CookingSessionView.swift` |
| Каталог жестов (иконки, названия) | `KitchenApp/Core/Vision/GestureType.swift` |

Точка интеграции всего режима — `CookingSessionView` (Этап 9): она создаёт
детектор, накладывает оверлей, мапит жесты на навигацию и управляет
жизненным циклом камеры.

### Каталог жестов: `GestureType`

`GestureType` — `enum` из четырёх распознаваемых жестов; каждый несёт
локализованное название (`displayName`) и SF-иконку (`iconName`) для оверлея:

| Кейс | Жест | Действие в сессии |
|---|---|---|
| `swipeNext` | открытая ладонь → вправо | следующий шаг (`navigateNext`) |
| `swipePrev` | открытая ладонь → влево | предыдущий шаг (`navigatePrev`) |
| `fistHold` | сжатый кулак, удержание ~1 с | пауза/продолжение таймера (`timer.toggle`) |
| `victory` | два пальца вверх (V) | подтверждение — тактильный отклик |

Маппинг «жест → действие» задаётся в `CookingSessionView.wireGestureDetector()`
и согласован с навигацией Этапа 9.

### Детектор жестов: `HandGestureDetector`

`HandGestureDetector` (`ObservableObject`) инкапсулирует камеру, Vision-запрос и
всю логику распознавания. Публикует три поля для UI:

- `detectedGesture: GestureType?` — последний распознанный жест (для оверлея;
  сам себя гасит через 1.5 с);
- `isRunning: Bool` — активна ли сессия камеры;
- `detectionConfidence: Float` — уверенность распознавания запястья (для
  confidence-бара оверлея).

**Захват видео.** В `start()` через `AVCaptureDevice.requestAccess(for: .video)`
запрашивается доступ к камере; при согласии `setupAndStart()` собирает
`AVCaptureSession` (`sessionPreset = .medium`) с **фронтальной**
`builtInWideAngleCamera` и `AVCaptureVideoDataOutput`. Кадры обрабатываются на
выделенной очереди `processingQueue` (`qos: .userInteractive`),
`alwaysDiscardsLateVideoFrames = true` — старые кадры отбрасываются, чтобы не
копить задержку. Все обновления публикуемых полей уводятся на главный поток
(`DispatchQueue.main.async`) — требование `SPEC.md` §2.7 «обработка в фоне,
UI на главном».

**Vision-запрос.** На каждый кадр в `captureOutput(_:didOutput:from:)` создаётся
`VNDetectHumanHandPoseRequest` (`maximumHandCount = 1`) и выполняется через
`VNImageRequestHandler` с ориентацией `.leftMirrored` (фронтальная камера
зеркалит). Если рука не найдена — состояние сбрасывается, `confidence = 0`.

**Распознавание пальцев.** Базовый примитив `isExtended(tip:mcp:)` считает
палец разогнутым, если кончик (`tip`) выше сустава (`mcp`) в координатах Vision
(ось Y растёт вверх), с запасом 0.03 и порогом уверенности точек 0.3. Поверх
него:

- `isPalmOpen` — разогнуто ≥3 из 4 пальцев (индекс/средний/безымянный/мизинец);
- `isFist` — согнуто ≥3 из 4 пальцев;
- `isVictory` — индекс и средний разогнуты, безымянный и мизинец согнуты.

**Приоритет жестов** (`detectGesture(from:now:)`): сначала кулак, затем V, затем
свайп открытой ладонью — порядок исключает ложные срабатывания (например, кулак
не спутается со свайпом).

**Свайп по дельте запястья** (`detectSwipe`). Позиция точки `.wrist` (при
`confidence > 0.4`) сравнивается с предыдущим кадром: `deltaX = wrist.x −
prev.x`. Поскольку фронтальная камера зеркалит, движение руки **вправо**
уменьшает `x` в пространстве Vision → `deltaX < -swipeSensitivity` даёт
`swipeNext`, а `deltaX > swipeSensitivity` — `swipePrev`. Позиции запястья
буферизуются (`wristBuffer`, размер 5) для сглаживания.

**Удержание кулака.** При первом обнаружении кулака запоминается `fistDetectedAt`;
`fistHold` возвращается только когда кулак держится дольше `fistHoldDuration`
(по умолчанию 1 с). Разжатие руки сбрасывает таймер удержания.

### Защита от ложных срабатываний: cooldown 1.5 с

Поле `cooldown: TimeInterval = 1.5` и `lastGestureTime` реализуют требование
`SPEC.md` §2.7 «задержка между срабатываниями 1.5 сек». После каждого
распознанного жеста детектор `cooldown` секунд игнорирует новые жесты (но
продолжает отслеживать удержание кулака и обновлять confidence), а буферы
свайпа очищаются. Дополнительно распознанный `detectedGesture` автоматически
гаснет через 1.5 с (`Task.sleep`), убирая карточку из оверлея.

### Оверлей распознавания: `HandsFreeOverlayView`

Прозрачный (`allowsHitTesting(false)`) слой поверх `CookingSessionView`,
показываемый когда `isActive` (hands-free включён). Состоит из двух частей:

- **Статус-бейдж** (`statusBadge`) — капсула «Hands-free активен» с пульсирующей
  точкой и **confidence-баром**: полоска заполняется на `confidence`, а цвет
  (`confidenceColor`) идёт красный → жёлтый → зелёный по порогам 0.3 / 0.6.
- **Карточка жеста** (`gestureCard`) — при `detectedGesture != nil` крупная
  иконка (`gesture.iconName`) и название (`gesture.displayName`) с
  spring-анимацией появления (`scale + opacity`). Гаснет автоматически, когда
  детектор сбрасывает `detectedGesture`.

### Настройки чувствительности: `SettingsView.handsFreeSection`

Секция «Hands-Free (управление жестами)» экрана настроек (Этап 12) даёт
пользователю контроль над режимом; значения хранятся в `UserDefaults` и
читаются детектором при инициализации:

- **`cameraPermissionRow`** — строка статуса доступа к камере
  (`AVCaptureDevice.authorizationStatus`): «Разрешён» / кнопка «Запросить»
  (`notDetermined`) / кнопка «Открыть настройки» (`denied`/`restricted`,
  ведёт в системные настройки через `openSettingsURLString`).
- **«Включать по умолчанию»** (`handsfree.enabledByDefault`) — при входе в
  сессию режим включается автоматически (`wireGestureDetector`).
- **Чувствительность свайпа** (`handsfree.swipeSensitivity`, слайдер
  0.02…0.10, шаг 0.01) — порог дельты запястья; подпись `sensitivityLabel`
  переводит число в «Высокая / Средняя / Низкая» (меньше порог — выше
  чувствительность).
- **Время удержания кулака** (`handsfree.fistHoldDuration`, слайдер
  0.5…2.0 с, шаг 0.1).

Ключи `UserDefaults` и их дефолты (`0.04` / `1.0`) согласованы между
`HandGestureDetector`, `SettingsView` и `CookingSessionView`. Дефолты
подставляет хелпер `Double.nonzero(default:)` (пустой `UserDefaults` возвращает
`0`).

### Интеграция и жизненный цикл в `CookingSessionView`

- **Создание.** `@StateObject private var gestureDetector = HandGestureDetector()`,
  флаг `@State private var handsFreeEnabled`.
- **Тумблер.** Кнопка «👁 Hands-free: ON/OFF» (и компактная кнопка «Жесты» в
  панели навигации) переключает `handsFreeEnabled`; `onChange` запускает
  (`startHandsFree`) или останавливает (`gestureDetector.stop()`) камеру.
- **Runtime-проверка разрешения** (`startHandsFree`): `authorized` → старт;
  `notDetermined` → `start()` сам запросит доступ; `denied`/`restricted` →
  сброс тумблера и алерт «Нет доступа к камере» с переходом в системные
  настройки.
- **Маппинг жестов** (`wireGestureDetector`) — см. каталог выше; `victory`
  даёт тактильный отклик `UIImpactFeedbackGenerator`.
- **Автоотключение при сворачивании** (`onChange(of: scenePhase)`): как только
  сцена перестаёт быть `.active`, камера останавливается и `handsFreeEnabled`
  сбрасывается — требование `SPEC.md` §2.7. Камера также гарантированно
  выключается в `onDisappear` (`gestureDetector.stop()`), поэтому не живёт
  дольше сессии готовки.

### Privacy

Согласно `SPEC.md` §2.7 (Privacy): доступ к камере запрашивается с пояснением
(`NSCameraUsageDescription` в Info.plist — «Камера используется для управления
рецептом жестами рук в режиме Hands-Free»), видеопоток обрабатывается **только
локально** (Vision, без сети) и не покидает устройство. Экран настроек явно
показывает текущий статус доступа и даёт быстрый путь к его изменению.

---

## Этап 11 — iOS: редактор рецептов

Создание и редактирование рецептов (`SPEC.md` §2.8): многосекционная форма
основной информации, выбор обложки с кропом 16:9, редактируемые списки
ингредиентов и шагов (добавление / удаление / перестановка), вложенный редактор
шага с фотографиями (до 5) и таймером, автосохранение черновика в SwiftData
каждые 30 секунд, валидация перед публикацией и предупреждение при выходе с
несохранёнными изменениями.

### Состав этапа

| Подзадача | Где реализовано |
|---|---|
| `RecipeEditorView` — форма основной информации | `KitchenApp/Features/Editor/RecipeEditorView.swift` |
| PhotosPicker: обложка рецепта (crop 16:9) | `coverSection` в `RecipeEditorView.swift`, `UIImage.cropped(toAspect:)` в `Shared/Extensions/Extensions.swift` |
| Список ингредиентов (добавить / удалить / reorder) | `ingredientsSection` в `RecipeEditorView.swift` |
| Список шагов с `StepEditorView` (drag-to-reorder) | `stepsSection` в `RecipeEditorView.swift` |
| `StepEditorView`: заголовок, описание, фото (до 5), таймер | `KitchenApp/Features/Editor/StepEditorView.swift` |
| Автосохранение черновика в SwiftData каждые 30 сек | `EditorViewModel.startAutosave/saveDraft`, `Core/Persistence/DraftRecipe.swift` |
| Валидация и публикация | `EditorViewModel.validationError/publish/performPublish` |
| Предупреждение при выходе с несохранёнными изменениями | `showDiscardAlert` + `interactiveDismissDisabled` в `RecipeEditorView.swift` |

Экран открывается как `sheet` из `RecipeListView` (кнопка `+`, Этап 8). Весь
слой данных и сетевые операции инкапсулированы в `EditorViewModel`
(`KitchenApp/Features/Editor/EditorViewModel.swift`).

### Вью-модель: `EditorViewModel`

`EditorViewModel` (`@MainActor`, `ObservableObject`) держит всё состояние формы
и выполняет автосохранение и публикацию. Форма правит **изменяемые** черновые
модели, отдельные от иммутабельных доменных DTO (см. Этап 6):

- **`DraftIngredient`** — `name`, `amount` (строка — редактируется в текстовом
  поле), `unit` (по умолчанию `«г»`);
- **`DraftStep`** — `title`, `description`, флаг `timerEnabled` + `timerMinutes`
  / `timerSeconds`, массив `photos: [UIImage]` (фото шага держатся в памяти как
  `UIImage`, а загружаются в S3 только при публикации).

Списки инициализируются одним пустым элементом (`[DraftIngredient()]` /
`[DraftStep()]`), чтобы форма сразу показывала первую строку.

**Публикуемое состояние формы:** `title`, `recipeDescription`,
`selectedCategory`, `difficulty`, `cookTimeMin`, `servings`, `coverImage`,
`ingredients`, `steps`, `selectedTagIds`, `availableTags`. **UI-состояние:**
`isLoading`, `isDirty` (были ли изменения — для предупреждения при выходе),
`isPublished` (триггер закрытия экрана), `alertMessage` / `showAlert` (алерт
ошибки валидации).

`existingRecipeId` задаёт режим (создание vs. редактирование) и влияет на
заголовок экрана.

### Форма: `RecipeEditorView`

`NavigationStack` с `Form` из секций и закреплённой снизу (`ZStack`) кнопкой
«Опубликовать» (пустой `Color.clear` высотой 60 pt в конце формы резервирует
место под кнопку).

**Секции формы (`SPEC.md` §2.8):**

1. **Основная информация** (`basicInfoSection`) — название (обрезается до
   **100 символов** в `onChange`, как требует §2.8), описание (`TextEditor` с
   плейсхолдером через `ZStack`), категория (`Picker`, справочник грузится
   `loadCategories()`).
2. **Обложка** (`coverSection`) — `PhotosPicker`; выбранное фото показывается
   превью с кнопкой «Изменить обложку», иначе — кнопка выбора.
3. **Параметры** (`difficultyTimeSection`) — сложность сегментированным
   контролом (`Difficulty.allCases`), время `Stepper` (5…600, **шаг 5 мин**),
   порции `Stepper` (1…100).
4. **Теги** (`tagsSection`) — поиск с загрузкой `loadTags(query:)`, мультиселект
   с галочками; счётчик выбранных в заголовке секции.
5. **Ингредиенты** (`ingredientsSection`) — см. ниже.
6. **Шаги** (`stepsSection`) — см. ниже.

**Тулбар:** «Отмена» (при `isDirty` открывает алерт сброса, иначе `dismiss`) и
«Черновик» (ручное `saveDraft` + сброс `isDirty`).

**Отслеживание изменений.** `onChange` на `title`, `recipeDescription`,
`ingredients.count`, `steps.count` (и на выбор тега/обложки внутри вью-модели)
поднимают `isDirty`. По `isPublished` экран автоматически закрывается.

### Обложка с кропом 16:9

Выбор из `PhotosPicker` связан с `coverImageItem`; его смена запускает
`loadCoverImage()`, который грузит `Data`, создаёт `UIImage` и **кропает до
соотношения 16:9** через `UIImage.cropped(toAspect: 16.0/9.0)`
(`Shared/Extensions/Extensions.swift`). Хелпер вырезает центральный прямоугольник
нужного соотношения (по большей стороне) с учётом `scale` и ориентации —
клиентский кроп из §2.8, без обращения к серверу.

### Списки ингредиентов и шагов (reorder)

Обе секции используют стандартный механизм `Form` + `EditButton`:

- **Ингредиенты** — `ForEach($vm.ingredients)` с `.onDelete`
  (`remove(atOffsets:)`) и `.onMove` (`move(fromOffsets:toOffset:)`);
  каждая строка — имя + количество (`.decimalPad`) + единица (`Picker` из
  фиксированного списка `units`). Кнопка «Добавить ингредиент» аппендит пустой
  `DraftIngredient`.
- **Шаги** — `ForEach` с индексом; каждая строка — `NavigationLink` в
  `StepEditorView` (передаётся `$step` как `Binding`), в подписи `stepRow`:
  кружок с номером, заголовок (или «Шаг N»), значки числа фото и таймера.
  Те же `.onDelete` / `.onMove` дают swipe-to-delete и drag-to-reorder,
  кнопка «Добавить шаг» аппендит пустой `DraftStep`.

`EditButton` в заголовках секций включает `EditMode` для перетаскивания.

### Редактор шага: `StepEditorView`

Вложенный экран правит **один** `DraftStep` через `@Binding` — изменения сразу
отражаются в родительском списке. Три секции:

- **Основное** — заголовок и описание (`TextEditor` с плейсхолдером);
- **Фотографии (до 5 шт.)** — горизонтальная лента превью с кнопкой удаления
  (крестик) на каждом фото; `PhotosPicker` показывается, только пока фото
  меньше 5, а `maxSelectionCount` динамически ограничен остатком
  (`5 - photos.count`). Выбранные элементы грузятся в `UIImage`
  (`loadPhotos(from:)`) и аппендятся к `step.photos`;
- **Таймер** — `Toggle` включает два `wheel`-пикера минут (0…119) и секунд
  (0…55, шаг 5), формируя `timerMinutes:timerSeconds`.

### Автосохранение черновика (SwiftData, 30 сек)

Черновик хранится в SwiftData-модели **`DraftRecipe`**
(`Core/Persistence/DraftRecipe.swift`): скалярные поля рецепта + `coverImageData`
(JPEG) и три `Data?`-поля с JSON (`ingredientsJSON`, `stepsJSON`, `tagsJSON`) —
изменяемые списки сериализуются в компактные вложенные структуры, а не в
отдельные SwiftData-сущности.

- **`startAutosave(context:)`** запускается в `.task` экрана: фоновый `Task` в
  цикле спит **30 секунд** и вызывает `saveDraft`, пока не отменён. `onDisappear`
  вызывает `stopAutosave()` (`autosaveTask?.cancel()`), поэтому цикл не живёт
  дольше экрана.
- **`saveDraft(to:)`** через `fetchOrCreateDraft` находит текущий черновик по
  сохранённому `draftModelId` (или создаёт и вставляет новый), переносит в него
  всё состояние формы, кодирует списки в JSON, ставит `updatedAt = Date()` и
  сохраняет контекст. `«Черновик»` в тулбаре дёргает тот же метод вручную.
- **`loadLatestDraft(context:)`** в `.task` восстанавливает **последний**
  черновик (сортировка по `updatedAt` убыв.): раскодирует JSON-поля обратно в
  `DraftIngredient`/`DraftStep` и множество тегов, запоминает `draftModelId`.
- **`deleteDraft(context:)`** удаляет черновик после успешной публикации.

> Фотографии шагов (`UIImage`) в черновик **не** сохраняются — сериализуются
> только текстовые поля, таймеры, обложка и теги.

### Валидация и публикация

**Валидация** (`validationError`) повторяет минимальные требования §2.8 на
клиенте: непустое название и **хотя бы один шаг с названием**. `publish` при
ошибке показывает её алертом (`alertMessage`/`showAlert`) и не шлёт запрос.

**Публикация** (`performPublish`) — многошаговый сетевой сценарий с явной
подгонкой под контракты бэкенда (нюансы вынесены в комментарии кода):

1. **Загрузка обложки** — `POST /upload/image`; сохраняется **S3-ключ** из
   ответа (`upload.key`), который бэкенд кладёт в поле рецепта `cover_image`.
2. **Создание рецепта** — `POST /recipes` с инлайн-ингредиентами. `amount`
   парсится с заменой запятой на точку; **ноль/пустое/нечисловое значение
   отправляется как `nil`**, потому что Zod-схема бэкенда принимает `amount`
   только положительным (`.positive()`) — иначе `400`.
3. **Создание шагов** — по одному `POST /recipes/:id/steps` для каждого шага с
   непустым заголовком. Две подгонки под `createStepSchema`: включённый таймер на
   `00:00` (итог 0) отправляется как **отсутствие таймера** (`timer_sec = nil`,
   схема требует `.positive()`); пустое описание шага **замещается заголовком**
   (схема требует непустое `description`, а форма валидирует только заголовок).
4. **Публикация** — `POST /recipes/:id/publish`.

После успеха черновик удаляется, `isPublished = true` (экран закрывается),
`isDirty` сбрасывается. Любая сетевая ошибка показывается глобальным баннером
`ErrorBannerState.shared.show(error)` (Этап 6).

### Предупреждение при несохранённых изменениях

Пока `isDirty == true`:

- **`interactiveDismissDisabled(vm.isDirty)`** блокирует свайп-закрытие `sheet`;
- кнопка **«Отмена»** открывает алерт «Выйти без сохранения?» с деструктивным
  «Выйти» (`dismiss`) и «Отмена»; текст предупреждает, что черновик не будет
  сохранён.

Так пользователь не теряет введённые данные случайным жестом — требование §2.8.

---

## Этап 12 — iOS: настройки, категории, офлайн

Завершающий функциональный этап клиента: экран настроек (`SettingsView`),
вкладка категорий с рецептами по категории (`CategoryView`) и офлайн-режим —
кэш просмотренных рецептов в SwiftData с graceful-обработкой отсутствия сети.

### Состав этапа

| Подзадача | Где реализовано |
|---|---|
| `SettingsView` — адрес сервера, hands-free, аккаунт | `KitchenApp/Features/Settings/SettingsView.swift` |
| `CategoryView` — список рецептов по категории | `KitchenApp/Features/Categories/CategoryView.swift`, `KitchenApp/Features/Categories/CategoryViewModel.swift` |
| Offline: кэш просмотренных рецептов в SwiftData | `KitchenApp/Core/Persistence/CachedRecipeDetail.swift`, `KitchenApp/Features/Recipes/RecipeDetailView.swift` |
| Обработка `noConnection` — показ кэша + banner | `KitchenApp/Features/Recipes/RecipeDetailView.swift`, `KitchenApp/Core/Network/NetworkError.swift` |

### Экран настроек: `SettingsView`

`SettingsView` (`Features/Settings/SettingsView.swift`) — это `Form` внутри
`NavigationStack`, собранный из независимых секций-`computed property`. Такое
разбиение (`serverSection`, `iCloudSyncSection`, `handsFreeSection`,
`voiceCommandsSection`, `notificationsSection`, `languageSection`,
`accountSection`, `aboutSection`) держит `body` компактным и позволяет
править каждую секцию изолированно.

Экран **не имеет отдельной вью-модели**: настройки — это набор простых
булевых/числовых/строковых значений, которые хранятся в `UserDefaults`.
Каждое поле объявлено как `@State` с инициализацией из `UserDefaults` и
записью обратно в `.onChange`:

```swift
@State private var handsfreeDefault = UserDefaults.standard.bool(forKey: "handsfree.enabledByDefault")
// …
Toggle("Включать по умолчанию", isOn: $handsfreeDefault)
    .onChange(of: handsfreeDefault) { _, new in
        UserDefaults.standard.set(new, forKey: "handsfree.enabledByDefault")
    }
```

Ключи `UserDefaults` — общий контракт между экранами: те же ключи читают
`HandGestureDetector`/`CookingSessionView` (Этап 9–10) и `TimerService`
(Этап 9). Для отсутствующих значений применяются дефолты: расширение
`Double.nonzero(default:)` подменяет 0 (значение по умолчанию для не заданного
`double(forKey:)`) на осмысленный дефолт, а `object(forKey:) as? Bool ?? true`
даёт `true` для тумблеров звука/вибрации таймера.

**Секции экрана** (соответствуют `SPEC.md` §2.9):

| Секция | Содержимое |
|---|---|
| Сервер | поле URL, проверка доступности, предупреждение о незащищённом HTTP |
| Синхронизация | тумблер iCloud, статус, дата последней синхронизации (Этап sync) |
| Hands-Free | доступ к камере, тумблер по умолчанию, чувствительность свайпа, удержание кулака |
| Голосовые команды | доступ к речи, тумблер по умолчанию, список команд |
| Таймер | звук и вибрация по окончании |
| Язык интерфейса | системный / RU / EN |
| Аккаунт | имя, email, «Выйти», «Удалить аккаунт» |
| О приложении | версия из `Bundle`, лицензии |

**Секция «Сервер».** Поле привязано к ключу `serverURL`; при изменении оно не
только пишется в `UserDefaults`, но и на лету перенастраивает базовый URL
сетевого слоя через `APIClient.shared.updateBaseURL(_:)` (Этап 6), после чего
статус проверки сбрасывается в `.idle`. Кнопка «Проверить доступность»
запускает `checkServer()` — асинхронный `GET /health` с `timeoutInterval: 5`;
результат моделируется приватным перечислением `ServerCheckState`
(`idle / checking / ok(ms) / fail(msg)`), которое управляет отрисовкой строки
статуса (спиннер, зелёная галочка с задержкой в мс, красный крест). Отдельно
вычисляемое свойство `isInsecureURL` подсвечивает предупреждение, если адрес
использует `http://` и не является локальным (`localhost` / `127.`) —
требование безопасности §4 (HTTPS/TLS).

**Секция «Hands-Free»** (`handsFreeSection`) документирована также в Этапе 10
как точка настройки чувствительности: слайдер `swipeSensitivity` в диапазоне
`0.02…0.10` (порог дельты запястья) и слайдер `fistHoldDuration` `0.5…2.0` с
(время удержания кулака). `cameraPermissionRow` показывает текущий
`AVAuthorizationStatus` и в зависимости от него предлагает «Запросить»
(runtime-промпт `AVCaptureDevice.requestAccess`) или «Открыть настройки»
(`UIApplication.openSettingsURLString`). Футер секции повторяет privacy-гарантию:
видеопоток обрабатывается только на устройстве.

**Секция «Аккаунт».** Имя и email берутся из `AuthViewModel`
(`@EnvironmentObject`, Этап 7). «Выйти» вызывает `authVM.logout()`. «Удалить
аккаунт» открывает `confirmationDialog` с деструктивным подтверждением — защита
от случайного нажатия.

Вложенные вспомогательные экраны реализованы как приватные `View` в том же
файле: `VoiceCommandsHelpView` (справочник голосовых команд) и `LicensesView`
(лицензии), открываемые через `NavigationLink`.

### Вкладка категорий: `CategoryView`

`CategoryView` — третий верхнеуровневый экран (см. `MainTabView`, Этап 6): на
iPhone это вкладка TabBar, на iPad — пункт бокового меню
`NavigationSplitView`. Экран построен на `CategoryViewModel` и делится на два
уровня навигации.

**`CategoryViewModel`** (`ObservableObject`, `@MainActor`) минималистичен:
одно действие `loadCategories()` дергает `APIClient.request(.categories)` и
публикует `categories` / `isLoading` / `error`. Guard `!isLoading`
предотвращает дублирующие запросы (например, одновременный `.task` и
`refreshable`), а ошибки пробрасываются в глобальный `ErrorBannerState.shared`
(Этап 6).

**Первый уровень — сетка категорий.** `CategoryView` в зависимости от
состояния отрисовывает `ProgressView`, состояние ошибки с кнопкой «Повторить»,
`ContentUnavailableView` для пустого списка или адаптивную сетку
`LazyVGrid(.adaptive(minimum: 150))`. Каждая карточка — `CategoryCardView` —
подбирает иконку SF Symbols и цвет акцента по `slug` категории (эвристика по
подстрокам: `pasta`/`макар` → `fork.knife`, `soup`/`суп` →
`cup.and.saucer.fill` и т. д.), что даёт визуальное разнообразие без
серверных ассетов.

**Второй уровень — рецепты категории.** Тап по карточке открывает
`CategoryRecipesView` через `NavigationLink`. Этот экран **переиспользует**
`RecipeViewModel` и `RecipeCardView` из Этапа 8: он формирует `RecipesQuery`
с проставленным `category = category.id` и вызывает
`loadRecipes(query:reset:)`. Поддержаны те же паттерны, что и в основном
списке — скелетоны при первой загрузке, `infinity scroll` (догрузка при
достижении последней карточки), `pull-to-refresh` и состояние ошибки с
retry. Навигация к деталям — `navigationDestination(for: UUID.self)` →
`RecipeDetailView(recipeId:)`.

### Офлайн-кэш деталей рецепта (SwiftData)

Офлайн-просмотр реализован на уровне `RecipeDetailView` и SwiftData-модели
`CachedRecipeDetail`.

**Модель `CachedRecipeDetail`** (`Core/Persistence/CachedRecipeDetail.swift`)
— `@Model`, хранящий рецепт как сериализованный JSON, а не как граф связанных
сущностей. Такой подход проще (одна запись = один рецепт) и переиспользует уже
готовое `Codable`-декодирование доменной модели `Recipe`:

```swift
@Model
final class CachedRecipeDetail {
    var recipeId: String      // UUID в виде строки — ключ поиска
    var recipeData: Data      // JSON рецепта (ISO-8601 даты)
    var title: String
    var cachedAt: Date        // метка времени для потенциального TTL/чистки

    func decode() -> Recipe? { /* JSONDecoder(.iso8601) */ }
}
```

Модель регистрируется в общем контейнере в `KitchenRecipeApp.swift`:
`Schema([DraftRecipe.self, CachedRecipeDetail.self])`, т. е. кэш и черновики
редактора (Этап 11) живут в одном SwiftData-хранилище.

**Запись в кэш.** При каждой успешной загрузке деталей `RecipeDetailView`
вызывает `cacheRecipe(_:)`: кодирует `Recipe` в JSON и делает upsert —
`FetchDescriptor` с `#Predicate { $0.recipeId == idStr }` ищет существующую
запись и обновляет её `recipeData`/`cachedAt`, иначе вставляет новую. Так кэш
всегда содержит последнюю просмотренную версию рецепта.

### Обработка `noConnection`: показ кэша + баннер

Ключевая логика офлайн-режима сосредоточена в `RecipeDetailView.loadRecipe()`
и опирается на типизированную ошибку `NetworkError.noConnection` (Этап 6):

```swift
private func loadRecipe() async {
    do {
        let r = try await viewModel.loadDetail(id: recipeId)
        recipe = r
        isOfflineMode = false
        cacheRecipe(r)                       // онлайн → обновляем кэш
    } catch NetworkError.noConnection {
        if let cached = loadCachedRecipe() { // офлайн → достаём из SwiftData
            recipe = cached
            isOfflineMode = true
            ErrorBannerState.shared.show("Нет соединения — показаны кэшированные данные")
        }
    } catch {
        ErrorBannerState.shared.show(error)
    }
}
```

Разделение по типу ошибки принципиально: `noConnection` — не фатальная
ситуация, а сигнал к фолбэку. `APIClient` перед этим уже выполнил три попытки
с экспоненциальной задержкой (Этап 6), поэтому до `catch` доходят только
действительно недоступные сети. Если кэшированная копия найдена, экран
показывает её и переводит флаг `isOfflineMode = true`.

**Визуальная индикация.** Пока `isOfflineMode == true`, поверх контента через
`safeAreaInset(edge: .top)` закрепляется `offlineBanner` — оранжевая плашка с
иконкой `wifi.slash` и текстом «Офлайн — кэшированные данные». Дополнительно
однократно всплывает глобальный `ErrorBanner` (Этап 6). При следующей успешной
загрузке (сеть вернулась) `isOfflineMode` сбрасывается в `false`, и баннер
исчезает.

Так выполняется требование §4 «Офлайн-режим клиента»: просмотр ранее открытых
рецептов остаётся доступным без сети, а пользователь чётко видит, что данные
могут быть неактуальны.

---

## Этап 13 — Финализация и полировка

Завершающий этап: приложение переводится на два языка, адаптируется под iPad
(landscape + portrait), поддерживает Dark Mode и VoiceOver, получает иконку и
launch screen, покрывается smoke-тестами для TestFlight-сборки и проходит
финальный аудит безопасности (Keychain, HTTPS, приватность камеры).

### Состав этапа

| Подзадача | Где реализовано |
|---|---|
| Локализация RU + EN | `KitchenApp/Resources/ru.lproj/Localizable.strings`, `KitchenApp/Resources/en.lproj/Localizable.strings`, `Shared/Extensions/Extensions.swift` |
| Адаптация лейаутов для iPad | `KitchenApp/MainTabView.swift`, `Features/Recipes/RecipeListView.swift` |
| Dark Mode | `Resources/Assets.xcassets/AccentColor.colorset`, системные цвета во View-слое |
| Accessibility (VoiceOver, Dynamic Type) | секция `accessibility.*` в `Localizable.strings`, `.accessibilityLabel(...)` во View |
| App Icon и Launch Screen | `Resources/Assets.xcassets/AppIcon.appiconset` |
| TestFlight-сборка + smoke-test | `ExportOptions.plist`, `KitchenAppUITests/` |
| Финальный ревью безопасности | `Core/Security/SecurityAudit.swift`, `Core/Network/KeychainService.swift`, `Features/Settings/SettingsView.swift` |

### Локализация: RU + EN

Строки вынесены в два каталога `.lproj` с ключами в формате
`Localizable.strings` (`"ключ" = "перевод";`). Русский — базовый язык, английский
— полный перевод того же набора ключей:

```
Resources/
├── ru.lproj/Localizable.strings   — базовый (RU)
└── en.lproj/Localizable.strings   — перевод (EN)
```

Применяются **две стратегии ключей**, и обе видны в файлах:

1. **Семантические ключи** — `difficulty.easy`, `duration.hour`, `sync.status.synced`,
   `comments.title`, `accessibility.next_step`. Используются для новых экранов и
   всего, что имеет параметры/форматирование.
2. **Русский текст как ключ** — `"Начать приготовление" = "...";`. Исторические
   строки первых этапов остаются читаемыми в коде, а `en.lproj` переопределяет их
   на английский (`"Рецепты" = "Recipes";`).

Обращение к строкам идёт через `NSLocalizedString(_:value:comment:)`, где
`value:` задаёт fallback, если ключ не найден в каталоге — приложение никогда не
покажет «голый» ключ:

```swift
let h = NSLocalizedString("duration.hour", value: "ч", comment: "")
```

**Форматируемые строки** используют позиционные спецификаторы и собираются через
`String(format:)`, что позволяет менять порядок аргументов при переводе:

```swift
// "accessibility.step_progress" = "Шаг %d из %d";  (RU)
// "accessibility.step_progress" = "Step %d of %d";  (EN)
String(format: NSLocalizedString("accessibility.step_progress", …), current, total)
```

Числовые/временные значения форматируются локале-независимой утилитой
`Int.formattedDuration` (`Shared/Extensions/Extensions.swift`), которая сама
подставляет локализованные единицы `duration.hour` / `duration.min`.

**Выбор языка вручную.** В `SettingsView.languageSection` пользователь выбирает
«Системный / Русский / English»; значение сохраняется в `UserDefaults` под
ключом `app.language`:

```swift
Picker("Язык", selection: $appLanguage) {
    Text("Системный").tag("system")
    Text("Русский").tag("ru")
    Text("English").tag("en")
}
.onChange(of: appLanguage) { _, new in
    UserDefaults.standard.set(new, forKey: "app.language")
}
```

### Адаптация лейаутов для iPad (landscape + portrait)

iPad-адаптация построена на классе размера, а не на проверке модели устройства —
это корректно работает и в Split View/Slide Over, и при обеих ориентациях.

**Разная корневая навигация** (`MainTabView.swift`). При `horizontalSizeClass
== .regular` (iPad) вместо нижнего `TabView` показывается
`NavigationSplitView` с боковой панелью (`.listStyle(.sidebar)`); на iPhone
(`.compact`) остаётся привычный таб-бар:

```swift
@Environment(\.horizontalSizeClass) private var horizontalSizeClass

var body: some View {
    if horizontalSizeClass == .regular { iPadLayout }   // sidebar + detail
    else                               { phoneLayout }  // TabView
}
```

**Адаптивная сетка карточек** (`RecipeListView.swift`). `LazyVGrid` использует
`GridItem(.adaptive(...))` — число колонок вычисляется системой из доступной
ширины, поэтому при повороте iPad колонки перекомпоновываются автоматически. На
iPhone получается 2 колонки, на iPad — 3–4:

```swift
private var adaptiveColumns: [GridItem] {
    let minimum: CGFloat = horizontalSizeClass == .regular ? 200 : 155
    let maximum: CGFloat = horizontalSizeClass == .regular ? 280 : 240
    return [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 16)]
}
```

Так выполняется требование §2.4 («2 колонки на iPhone, 3–4 на iPad») и §4
(«iPad-ориентация: Landscape + Portrait»).

### Dark Mode

Тёмная тема не требует ручного переключения — приложение опирается на
динамические цвета системы и asset-каталог с вариантами под тему:

- **Акцентный цвет** (`AccentColor.colorset/Contents.json`) содержит два
  варианта: `universal` (светлый) и `luminosity=dark`. В тёмной теме оранжевый
  делается чуть светлее (green `0.478 → 0.584`) для контраста на тёмном фоне.
  В коде — `Color("AccentColor")` / `Color.kitchenAccent`.
- **Фоновые и текстовые цвета** используют системные семантические цвета вместо
  жёстко заданных: `Color(.systemBackground)`, `Color(.secondarySystemBackground)`,
  `Color(.tertiarySystemBackground)`. Они автоматически инвертируются в Dark Mode.
- **Материалы** (`.ultraThinMaterial`, `.regularMaterial`) для закреплённых
  панелей и оверлеев — тоже адаптивны к теме «из коробки».

Поскольку `preferredColorScheme` нигде не форсируется, приложение следует
системной настройке и корректно выглядит в обоих режимах.

### Accessibility (VoiceOver + Dynamic Type)

**VoiceOver.** Все иконочные кнопки без видимого текста снабжены
`.accessibilityLabel(...)` с локализованными строками из секции `accessibility.*`.
Метки контекстно-зависимы (учитывают текущее состояние):

```swift
// Кнопка hands-free меняет подсказку в зависимости от состояния:
.accessibilityLabel(NSLocalizedString(
    handsFreeEnabled ? "accessibility.handsfree_on"
                     : "accessibility.handsfree_off", comment: ""))

// Кнопка таймера — play/pause:
.accessibilityLabel(NSLocalizedString(
    timer.isRunning ? "accessibility.timer_pause"
                    : "accessibility.timer_play", comment: ""))
```

Карточка рецепта объединяется в один элемент озвучивания через
`.accessibilityElement(children: .combine)` + собранный из полей label
(`accessibility.recipe_card` = `"%@, %@, %@"` — название, время, сложность), а
чисто декоративные иконки скрываются `.accessibilityHidden(true)`, чтобы
VoiceOver не читал их отдельно.

**Dynamic Type.** Текст использует семантические стили шрифта (`.font(.caption)`,
`.headline` и т. п.), которые масштабируются вместе с системным размером шрифта.
Для многострочных подписей применяется `.fixedSize(horizontal: false, vertical:
true)`, чтобы текст не обрезался при крупных шрифтах, а описания рецепта —
`.lineLimit` с возможностью развернуть («Читать далее»).

### App Icon и Launch Screen

- **App Icon** — `AppIcon.appiconset` с единым ассетом `1024×1024`
  (`"idiom": "universal", "platform": "ios"`). Формат single-size —
  современный подход iOS 17+, где система сама генерирует нужные размеры.
- **Launch Screen** — используется SwiftUI-storyboardless launch screen
  (конфигурируется ключом `UILaunchScreen` в Info.plist Xcode-проекта);
  отдельный `.storyboard` не требуется для iOS 17+.

### TestFlight-сборка + smoke-test

**Экспорт для TestFlight** описан в `ExportOptions.plist`: `method = app-store`
(загрузка в App Store Connect / TestFlight), `signingStyle = automatic`,
`teamID = $(DEVELOPMENT_TEAM)`, `stripSwiftSymbols` и `uploadSymbols` для
корректных крэш-репортов. Файл подключается к `xcodebuild -exportArchive
-exportOptionsPlist ExportOptions.plist`.

**Smoke-тесты** (`KitchenAppUITests/`) — XCUITest, проверяющие ключевые сценарии
без реального бэкенда:

- `KitchenAppSmokeTests.swift` — экран логина и его элементы, включение кнопки
  при валидном вводе, переход на регистрацию, появление таб-бара, наличие
  поиска на списке рецептов, открытие фильтр-шторки и редактора.
- `KitchenAppLaunchTests.swift` — `testLaunchPerformance` (метрика времени
  запуска).

Тесты, требующие авторизованного состояния, обходят реальный логин через launch
argument `UI_TESTING_BYPASS_AUTH`. В `KitchenRecipeApp.init()` (только `#if
DEBUG`) этот флаг перехватывается и в `APIClient` инъектируются тестовые токены:

```swift
private func injectUITestingState() {
    guard CommandLine.arguments.contains("UI_TESTING_BYPASS_AUTH") else { return }
    APIClient.shared.setTokens(access: "ui-test-access-token",
                               refresh: "ui-test-refresh-token")
}
```

### Финальный ревью безопасности

Ревью сведён в отдельный тип `SecurityAudit` (`Core/Security/SecurityAudit.swift`),
запускаемый на старте (`SecurityAudit.run()` в `KitchenRecipeApp.init()`), и
закрывает три поверхности из §4:

**1. Keychain (токены).** Access/refresh-токены хранятся как
`kSecClassGenericPassword` с атрибутом доступности
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (`KeychainService.swift`): токены
недоступны при заблокированном устройстве, не мигрируют в iCloud Keychain и не
попадают в резервные копии. Пароли отправляются на сервер только при
login/register и локально не кэшируются.

**2. HTTPS.** `SecurityAudit.checkServerURLScheme()` логирует предупреждение,
если сохранённый адрес сервера использует plain HTTP для не-локального хоста.
UI-дубликат — в `SettingsView`: при вводе небезопасного URL показывается красный
`Label` с иконкой `lock.open.trianglebadge.exclamationmark.fill` и пояснением,
что токены и данные пойдут в открытом виде (с `.accessibilityLabel` для
VoiceOver). Локальные адреса (`localhost`, `127.*`) из проверки исключены.

**3. Приватность камеры.** `checkCameraUsageDescription()` через `assert`
проверяет наличие `NSCameraUsageDescription` в Info.plist (без ключа доступ к
камере крэшит на старте). Кадры `AVCaptureSession` потребляются только локально
`VNDetectHumanHandPoseRequest` (Этап 10) — сырое видео не выгружается и не
сохраняется, о чём пользователю сообщает пояснение в `SettingsView`.

Итоговая сводка о постуре безопасности зафиксирована в doc-комментарии к
`enum SecurityAudit` как эталон для будущих ревью.

---

## MVP — CRUD рецептов со шагами и фотографиями

Сквозная MVP-фича (`SPEC.md` §6 «MVP»): полный жизненный цикл рецепта на клиенте
— чтение (список и детали), создание со шагами и фотографиями, публикация. В
отличие от экранных этапов, это **вертикальный срез** через все слои клиента:
типобезопасные эндпоинты, DTO, сетевой клиент, view-модели чтения и
редактирования. Низкоуровневые детали каждого слоя описаны в соответствующих
этапах (сетевой слой и модели — Этап 6, список/детали — Этап 8, редактор —
Этап 11); этот раздел показывает, **как они складываются в единый CRUD-поток** и
как форматы запросов согласованы с бэкендом (`SPEC.md` §3.3–3.7).

### Состав фичи

| Операция | Frontend-точка входа | Эндпоинт |
|---|---|---|
| Список рецептов (read) | `RecipeViewModel.loadRecipes` | `GET /recipes` |
| Детали рецепта (read) | `RecipeViewModel.loadDetail` | `GET /recipes/:id` |
| Загрузка обложки | `EditorViewModel.performPublish` → `APIClient.upload` | `POST /upload/image` |
| Создание рецепта | `EditorViewModel.performPublish` | `POST /recipes` |
| Создание шагов | `EditorViewModel.performPublish` (цикл по шагам) | `POST /recipes/:id/steps` |
| Публикация | `EditorViewModel.performPublish` | `POST /recipes/:id/publish` |
| DTO запросов/ответов | `RecipeCreateRequest`, `IngredientInput`, `Recipe`, `Step` … | — |

### Модель эндпоинтов: `Endpoint`

Все маршруты CRUD описаны кейсами `enum Endpoint`
(`KitchenApp/Core/Network/Endpoint.swift`) с ассоциированными значениями:
`createRecipe`, `updateRecipe`, `deleteRecipe`, `publishRecipe`, семейство
`steps`/`createStep`/`updateStep`/`deleteStep`/`reorderSteps`, а также
`uploadStepPhoto`/`deleteStepPhoto`/`reorderStepPhotos` и `uploadImage`.
`path`, `method` и `queryItems` детерминированно выводятся из кейса, поэтому
`APIClient` собирает `URLRequest`, не зная деталей конкретного маршрута.
На момент документирования UI-редактор использует подмножество: `uploadImage`
(обложка), `createRecipe`, `createStep`, `publishRecipe`; остальные кейсы
(update/delete, отдельная загрузка фото шага, reorder) объявлены в модели
эндпоинтов и готовы к использованию.

### DTO запросов и ответов

**Тело создания рецепта — `RecipeCreateRequest`** (`Endpoint.swift`). Поля
мапятся в snake_case бэкенда через `CodingKeys` (`category_id`, `cook_time_min`,
`cover_image`, `tag_ids`). Ключевое согласование с сервером:

- `coverImage` (`cover_image`) хранит **S3-ключ**, а не URL: бэкенд
  `createRecipeSchema` кладёт в это поле именно `key` из ответа `POST /upload/image`;
- ингредиенты передаются **инлайн** массивом `IngredientInput`
  (`name`/`amount`/`unit`/`sort_order`), а не отдельными запросами;
- теги — массивом UUID `tag_ids`.

**Ответы чтения** (`KitchenApp/Shared/Models/Models.swift`) разделены на
«лёгкую» и «полную» модели: `RecipeListItem` (карточка списка) и `Recipe`
(полный рецепт с `ingredients` и `steps`). Список приходит в обёртке
`PaginatedResponse<T>` с вычислимым `hasMore` (`page < pages`). Даты
(`created_at`/`updated_at`) декодируются автоматически — у `JSONDecoder` в
`APIClient` выставлен `dateDecodingStrategy = .iso8601`.

### Сетевой слой: чтение и multipart-загрузка

CRUD опирается на два метода `APIClient` (`KitchenApp/Core/Network/APIClient.swift`):

- `request<T: Decodable>(_:body:)` — универсальный JSON-запрос: собирает
  `URLRequest`, подставляет `Authorization: Bearer` из `KeychainService`,
  сериализует `Encodable`-тело, декодирует ответ и обрабатывает `401`
  (однократный refresh + повтор) и `noConnection` (retry с экспоненциальной
  задержкой);
- `upload(imageData:mimeType:to:)` — `multipart/form-data` (поле `file`) для
  `POST /upload/image`, возвращает `UploadResponse { url, key }`.

### Чтение: `RecipeViewModel`

`RecipeViewModel` (`@MainActor`, `ObservableObject`) обслуживает read-часть:

- `loadRecipes(query:reset:)` — постраничная загрузка списка с защитой от гонок
  (`guard !isLoading`), накоплением `recipes += items` и обновлением `hasMore`;
  флаг `reset` сбрасывает пагинацию для pull-to-refresh и смены фильтров;
- `loadDetail(id:)` — полный рецепт для `RecipeDetailView`/сессии готовки;
- `loadCategories()` / `loadTags()` — справочники для фильтров.

Ошибки чтения списка одновременно кладутся в `error` (для inline-состояния
экрана) и прокидываются в глобальный `ErrorBannerState.shared`.

### Создание и публикация: `EditorViewModel.performPublish`

Ядро write-части — `performPublish(context:)`
(`KitchenApp/Features/Editor/EditorViewModel.swift`), последовательный конвейер
из четырёх шагов:

1. **Загрузка обложки.** Если выбрана картинка — сжимается в JPEG и грузится
   через `api.upload(...)`; сохраняется `upload.key` (именно ключ, не URL — см.
   `cover_image` выше).
2. **Создание рецепта.** Ингредиенты фильтруются (пустые имена отбрасываются) и
   мапятся в `IngredientInput`; рецепт создаётся `POST /recipes`, из ответа
   берётся `id`.
3. **Создание шагов.** Цикл по непустым шагам, каждый — `POST /recipes/:id/steps`.
4. **Публикация.** `POST /recipes/:id/publish`, затем удаление черновика
   (`deleteDraft`) и `isPublished = true` (экран закрывается).

**Согласование с Zod-схемами бэкенда** (иначе публикация прерывается на 400):

- `ingredientInputSchema.amount` — только `.positive()`: `0`/пустое/нечисловое
  значение отправляется как `null`;
- `createStepSchema.timer_sec` — только `.positive()`: включённый таймер на
  `00:00` даёт `0` и трактуется как отсутствие таймера (`nil`);
- `createStepSchema.description` — `min 1`: пустое описание шага заменяется его
  заголовком (форма валидирует только заголовок шага).

Любая ошибка конвейера показывается через `ErrorBannerState.shared`.

### UI редактора: авторинг шагов и фотографий

`RecipeEditorView` (`KitchenApp/Features/Editor/RecipeEditorView.swift`) — форма
основной информации, обложки, тегов, а также списков ингредиентов и шагов с
`onDelete`/`onMove` (swipe-to-delete и drag-to-reorder). Каждый шаг раскрывается
в `StepEditorView` (`StepEditorView.swift`): заголовок, описание,
**до 5 фотографий** (`PhotosPicker` с `maxSelectionCount: 5 - photos.count`,
превью с кнопкой удаления) и таймер (`minutes:seconds` через `wheel`-пикеры).
Фотографии шага удерживаются в `DraftStep.photos` (в памяти/черновике SwiftData);
отдельная выгрузка фото шага на сервер (`uploadStepPhoto`) в текущем потоке
публикации не выполняется — при создании шага передаются его текст и таймер.

### Как слои связаны

```
RecipeEditorView / StepEditorView   (ввод: поля, ингредиенты, шаги, фото)
        │  @Published draft-модели
        ▼
EditorViewModel.performPublish       (конвейер: upload → create → steps → publish)
        │  RecipeCreateRequest / IngredientInput / StepBody
        ▼
APIClient.request / .upload          (URLRequest, JWT, retry, refresh, декодирование)
        │  Endpoint (path/method/query)
        ▼
        Бэкенд  ──►  GET /recipes(:id)  ──►  PaginatedResponse<RecipeListItem> / Recipe
        ▲                                             │
        └──────────────  RecipeViewModel  ◄───────────┘   (чтение: список, детали)
```

---

## MVP — Авторизация

Сквозная MVP-фича (`SPEC.md` §6 «MVP»): вход, регистрация и выход, а также
прозрачное поддержание сессии на клиенте. Как и CRUD, это **вертикальный срез**
через все слои: экраны входа/регистрации, единая вью-модель состояния,
безопасное хранилище токенов, автоматическое обновление access-токена в сетевом
клиенте и защищённый роутинг корневого `App`. Низкоуровневые детали слоёв
описаны в Этапе 7; этот раздел показывает, **как они складываются в единый
поток авторизации** и как формат запросов/заголовков согласован с бэкендом
(`SPEC.md` §2.10, §3.4 «Аутентификация»).

### Состав фичи

| Операция | Frontend-точка входа | Эндпоинт |
|---|---|---|
| Вход | `AuthViewModel.login(email:password:)` | `POST /auth/login` |
| Регистрация | `AuthViewModel.register(email:username:password:)` | `POST /auth/register` |
| Выход | `AuthViewModel.logout()` → `APIClient.logout()` | `POST /auth/logout` |
| Обновление access-токена | `APIClient.refreshAccessToken()` (авто, при `401`) | `POST /auth/refresh` |
| Хранение токенов | `KeychainService.accessToken` / `refreshToken` | — |
| Защищённый роутинг | `KitchenRecipeApp.body` (`if authViewModel.isAuthenticated`) | — |
| DTO запросов/ответов | `LoginRequest`, `RegisterRequest`, `AuthTokens` | — |

### Вью-модель: `AuthViewModel`

`AuthViewModel` (`@MainActor`, `ObservableObject`,
`KitchenApp/Features/Auth/AuthViewModel.swift`) — единый источник состояния
авторизации. Создаётся один раз в корне как `@StateObject` и прокидывается через
`environmentObject`, поэтому любой экран может прочитать `isAuthenticated`,
`isLoading`, `userEmail`, `userUsername`.

- `login` / `register` — собирают `LoginRequest` / `RegisterRequest`, вызывают
  `APIClient.request`, при успехе сохраняют пару токенов (`api.setTokens`) и
  поднимают `isAuthenticated = true`. Флаг `isLoading` (через `defer`) блокирует
  кнопки и показывает `ProgressView`;
- `logout` — асинхронно вызывает `api.logout()` (ревокация refresh-токена на
  сервере), очищает Keychain (`clearTokens`) и локальные данные профиля, опускает
  `isAuthenticated`.

**Разделение секретов и профиля.** Токены живут **только** в Keychain;
неконфиденциальные email/username кэшируются в `UserDefaults` (ключи
`user.email` / `user.username`) для показа в `SettingsView` без сетевого запроса.
Ошибки login/register наружу не пробрасываются, а показываются глобальным
`ErrorBannerState.shared` (Этап 6).

### Экраны входа и регистрации

`LoginView` (`KitchenApp/Features/Auth/LoginView.swift`) — стартовый экран
неавторизованного пользователя: поля email/пароль, кнопка «Войти» с индикатором
загрузки и блокировкой при пустых полях, переход на `RegisterView` через
`navigationDestination`.

`RegisterView` (`KitchenApp/Features/Auth/RegisterView.swift`) — форма email /
имя пользователя / пароль + подтверждение. Локальная валидация `isValid`
**повторяет Zod-схему бэкенда** (`registerBodySchema`), чтобы не слать заведомо
отклоняемый запрос: `username` — 3–50 символов из латиницы/цифр/`_`, `password` —
8–100 символов, и `password == confirm`. Оба экрана читают `AuthViewModel` из
окружения и вызывают его методы — сами по себе состояния авторизации не держат.

### Хранение токенов: `KeychainService`

`KeychainService` (`KitchenApp/Core/Network/KeychainService.swift`) — stateless
`enum` поверх системного Keychain. Access- и refresh-токены сохраняются как
`kSecClassGenericPassword` с атрибутом
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: недоступны на заблокированном
устройстве и **не** мигрируют в iCloud Keychain или зашифрованные бэкапы.
Типобезопасные аксессоры `accessToken` / `refreshToken` (get/set, `nil` →
удаление записи) скрывают низкоуровневые `SecItem*`-вызовы; `clearAll()` стирает
обе записи при выходе. `APIClient.isAuthenticated` вычисляется как «в Keychain
есть access-токен», и именно это значение читает `AuthViewModel` при старте
(`init`) — сессия восстанавливается между запусками без повторного логина.

### Interceptor: автообновление access-токена

Refresh-flow встроен в `APIClient.execute(_:endpoint:retries:)`
(`KitchenApp/Core/Network/APIClient.swift`) и прозрачен для вызывающего кода:

1. запрос выполняется с `Authorization: Bearer <access>` из Keychain;
2. при `NetworkError.unauthorized` (`401`) **один раз** вызывается
   `refreshAccessToken()`;
3. `refreshAccessToken()` шлёт `POST /auth/refresh`, передавая **refresh-токен в
   заголовке** `Authorization: Bearer` (не в теле — так ожидает бэкенд),
   декодирует `{ access_token }`, сохраняет новый access-токен в Keychain и
   возвращает его;
4. исходный запрос повторяется с обновлённым заголовком. Если refresh не удался
   (нет refresh-токена или сервер вернул `401`) — пробрасывается
   `NetworkError.unauthorized`.

`logout()` реализован отдельно, потому что ревокирует именно **refresh**-токен и
ожидает его в `Authorization: Bearer` (а не access-токен, который подставляет
общий `request`); ответ — `204 No Content`, поэтому тело не декодируется, а
сетевые ошибки игнорируются (локальные токены всё равно очищаются вызывающей
стороной).

### Защищённый роутинг

Корневой `KitchenRecipeApp.body` (`KitchenApp/KitchenRecipeApp.swift`) выбирает
стартовый экран по `authViewModel.isAuthenticated`: пока токенов нет — `LoginView`,
иначе — `MainTabView`. Поскольку `isAuthenticated` — `@Published`, любое его
изменение (успешный login/register или logout) заставляет SwiftUI пересобрать
`Group` и переключить экран без ручной навигации. В DEBUG-сборках XCUITests
обходят реальный логин через launch-аргумент `UI_TESTING_BYPASS_AUTH`, который
кладёт в Keychain плейсхолдер-токены (`injectUITestingState`).

### Как слои связаны

```
LoginView / RegisterView            (ввод: email, username, пароль)
        │  вызывает методы из окружения
        ▼
AuthViewModel.login / register / logout   (@Published isAuthenticated / isLoading)
        │  LoginRequest / RegisterRequest / AuthTokens
        ▼
APIClient.request / .logout         (URLRequest, JWT, 401→refresh, retry)
        │  setTokens / clearTokens          ▲
        ▼                                    │ Authorization: Bearer
KeychainService  (access + refresh, device-only)
        ▲
        │ isAuthenticated читает App.body → LoginView ↔ MainTabView
```

---

## После MVP — Голосовые команды (Speech framework)

Голосовое управление сессией приготовления через Apple **Speech Framework**
(`SPEC.md` §6 «После MVP»). Расширяет Hands-Free режим (Этап 10): пользователь
листает шаги, ставит таймер на паузу и завершает готовку короткими голосовыми
командами, не касаясь экрана и не показывая руки камере. Как и жесты, слой
полностью **клиентский** — аудио обрабатывается локально через Apple Speech
Recognition и **не** передаётся на серверы приложения; бэкенд-эндпоинтов для
голоса нет.

### Состав этапа

| Подзадача | Где реализовано |
|---|---|
| Каталог команд (иконки, названия) | `enum VoiceCommand` в `KitchenApp/Core/Speech/VoiceCommandService.swift` |
| Распознавание речи и матчинг команд | `VoiceCommandService` там же |
| Запрос разрешения на распознавание речи | `VoiceCommandService.requestPermissions()`, `SettingsView.speechPermissionRow`, `CookingSessionView.startVoiceCommands()` |
| Оверлей активного микрофона и команды | `KitchenApp/Features/Cooking/VoiceCommandOverlayView.swift` |
| Задержка между командами 1.5 сек | `commandCooldown` в `VoiceCommandService.swift` |
| Тумблер «включать по умолчанию» + справочник команд | `voiceCommandsSection` / `VoiceCommandsHelpView` в `KitchenApp/Features/Settings/SettingsView.swift` |
| Автоотключение при сворачивании приложения | `onChange(of: scenePhase)` в `CookingSessionView.swift` |
| Требуемые ключи Info.plist | `NSSpeechRecognitionUsageDescription`, `NSMicrophoneUsageDescription` (комментарий в `VoiceCommandService.swift`) |

Точка интеграции — `CookingSessionView` (Этап 9): она создаёт сервис,
накладывает оверлей, мапит команды на навигацию/таймер и управляет жизненным
циклом распознавания параллельно с Hands-Free жестами.

### Каталог команд: `VoiceCommand`

`VoiceCommand` — `enum` из четырёх действий; каждое несёт локализованное
название (`displayName`) и SF-иконку (`iconName`) для карточки оверлея:

| Кейс | Действие в сессии | Иконка |
|---|---|---|
| `nextStep` | следующий шаг (`navigateNext`) | `chevron.right.circle.fill` |
| `prevStep` | предыдущий шаг (`navigatePrev`) | `chevron.left.circle.fill` |
| `toggleTimer` | пауза/запуск таймера (`timer.toggle`) | `timer` |
| `stopCooking` | завершить приготовление (`dismiss`) | `xmark.circle.fill` |

Маппинг «команда → действие» задаётся в `CookingSessionView.wireVoiceCommands()`
и согласован с навигацией Этапа 9 и жестами Этапа 10 (те же операции).

### Сервис распознавания: `VoiceCommandService`

`VoiceCommandService` (`@MainActor`, `ObservableObject`) инкапсулирует
`SFSpeechRecognizer`, `AVAudioEngine` и логику матчинга команд. Публикует три
поля для UI:

- `isListening: Bool` — активен ли аудио-движок;
- `lastCommand: VoiceCommand?` — последняя распознанная команда (для оверлея;
  сам себя гасит через ~1.8 с);
- `speechAuthStatus: SFSpeechRecognizerAuthorizationStatus` — статус разрешения
  на распознавание речи.

Внешняя точка выхода — замыкание `onCommand: ((VoiceCommand) -> Void)?`, которое
`CookingSessionView` привязывает к навигации и таймеру.

**Локаль.** В `init` распознаватель создаётся для `ru-RU`, а если русская модель
недоступна — fallback на `en-US`. Соответственно основной словарь команд —
русский, с английскими дублями.

**Разрешения.** `requestPermissions()` оборачивает
`SFSpeechRecognizer.requestAuthorization` в `withCheckedContinuation` (async/await)
и публикует итоговый `speechAuthStatus` на главном потоке. Для работы также
требуются ключи Info.plist `NSSpeechRecognitionUsageDescription` и
`NSMicrophoneUsageDescription` (перечислены в шапке файла).

**Жизненный цикл сессии.** `start()` (только при `.authorized`) поднимает флаг
`shouldRestart` и вызывает `beginSession()`; `stop()` сбрасывает флаг, отменяет
задачу перезапуска и `endSession()`. В `beginSession()`:

- настраивается `AVAudioSession` в режиме `.playAndRecord` / `.measurement` с
  опциями `.duckOthers` (приглушить фоновый звук) и `.defaultToSpeaker`;
- создаётся `SFSpeechAudioBufferRecognitionRequest`
  (`shouldReportPartialResults = true`, `taskHint = .dictation`) — команды
  ловятся по частичным результатам, не дожидаясь финала фразы;
- на `inputNode` ставится tap (`installTap`, buffer 1024), буферы дописываются в
  запрос; флаг `tapInstalled` гарантирует корректное снятие tap в `endSession()`.

Речь непрерывна, поэтому после `isFinal`/ошибки при живом `shouldRestart`
вызывается `scheduleRestart()` — перезапуск сессии через 400 мс (с проверкой
`Task.isCancelled`), чтобы прослушивание не «умирало» после первой фразы.
`endSession()` идемпотентно останавливает движок, снимает tap и обнуляет
запрос/задачу распознавания.

**Матчинг команд.** Ключевые слова хранятся в таблице `keywords`
(`[(keywords:, command:)]`). В `matchCommand(in:)` транскрипт приводится к
нижнему регистру, и при `text.contains` любого из ключевых слов вызывается
соответствующая команда. Дребезг подавляется `commandCooldown = 1.5 с` (те же
1.5 с, что у жестов Этапа 10): срабатывания чаще игнорируются. При совпадении
обновляется `lastCommand` (для оверлея) и вызывается `onCommand`; через ~1.8 с
`lastCommand` очищается, если новая команда не пришла.

### Оверлей: `VoiceCommandOverlayView`

`VoiceCommandOverlayView` — прозрачный оверлей поверх `CookingSessionView`,
размещённый **сверху** (`padding(.top, 64)` — ниже прогресс-бара и хедера),
чтобы не перекрывать нижний `HandsFreeOverlayView`. Полностью пассивен
(`allowsHitTesting(false)`) — не перехватывает свайпы сессии. Состоит из двух
частей:

- **`micBadge`** — капсула «Голос активен» с пульсирующим кругом (анимация
  `micPulse`, `repeatForever`), показывается пока `isActive == true`;
- **`commandCard`** — карточка с иконкой и названием последней команды, появляется
  через `.scale + .opacity`-переход и `spring`-анимацию при смене `command`.

### Интеграция в `CookingSessionView`

`CookingSessionView` владеет `@StateObject voiceService` и локальным состоянием
`voiceEnabled` / `showVoicePermissionAlert`:

- в `onAppear` вызывается `wireVoiceCommands()`; если в настройках включён
  `voice.enabledByDefault` (`UserDefaults`) — сразу `startVoiceCommands()`;
- тумблер в тулбаре («Голос» / «Голос: вкл», иконки `mic` / `mic.fill`)
  переключает `voiceEnabled`; `onChange(of: voiceEnabled)` стартует/останавливает
  сервис;
- `startVoiceCommands()` при `.notDetermined` запрашивает разрешение, затем: при
  `.authorized` — `start()`; при `.denied/.restricted` — показывает алерт «Нет
  доступа к микрофону» с кнопкой перехода в системные настройки;
- `onChange(of: scenePhase)` при уходе приложения из `.active` останавливает
  распознавание и сбрасывает `voiceEnabled` (симметрично Hands-Free).

Голосовые команды работают **независимо** от жестов — можно включить оба режима
одновременно; оба вызывают одни и те же операции навигации/таймера.

### Настройки: секция голосовых команд

В `SettingsView` секция `voiceCommandsSection` содержит:

- **`speechPermissionRow`** — статус распознавания речи: «Разрешено», кнопка
  «Открыть настройки» (при отказе) или «Запросить» (при `.notDetermined`,
  вызывает `SFSpeechRecognizer.requestAuthorization`);
- **тумблер «Включать по умолчанию»** — пишет флаг `voice.enabledByDefault` в
  `UserDefaults` (его читает `CookingSessionView` при старте сессии);
- **`VoiceCommandsHelpView`** — справочник фраз (напр. «Следующий» / «Вперёд»,
  «Пауза» / «Останови», «Выйти») с описанием действий и советами;
- **footer** — пояснение приватности: голос обрабатывается локально, аудио не
  уходит на серверы приложения.

## MVP — Hands-free жесты (следующий/предыдущий шаг)

Управление сессией приготовления жестами рук перед камерой (SPEC.md §2.7, §6
«MVP»). Ключевой пользовательский сценарий MVP: во время готовки руки заняты или
грязные — пользователь листает шаги **открытой ладонью** (свайп вправо/влево), не
касаясь экрана. Слой полностью **клиентский**: видеопоток анализируется на
устройстве через Vision Framework и **не** передаётся на сервер (в бэкенде нет
gesture/camera/vision-эндпоинтов). Стек тот же, что у Этапа 10, но здесь фича
описана со стороны своей главной функции — навигации по шагам.

### Состав фичи

| Подзадача | Где реализовано |
|---|---|
| Каталог жестов (иконки, названия) | `enum GestureType` в `KitchenApp/Core/Vision/GestureType.swift` |
| Захват камеры и распознавание позы руки | `HandGestureDetector` в `KitchenApp/Core/Vision/HandGestureDetector.swift` |
| Определение свайпа «следующий/предыдущий шаг» | `detectSwipe(from:)` в `HandGestureDetector.swift` |
| Маппинг «жест → навигация/таймер» | `CookingSessionView.wireGestureDetector()` |
| Запрос разрешения камеры + тумблер режима | `CookingSessionView.startHandsFree()`, тулбар/нижний тумблер |
| Оверлей распознанного жеста + confidence | `KitchenApp/Features/Cooking/HandsFreeOverlayView.swift` |
| Задержка между срабатываниями 1.5 сек | `cooldown` в `HandGestureDetector.swift` |
| Автоотключение при сворачивании приложения | `onChange(of: scenePhase)` в `CookingSessionView.swift` |
| Чувствительность свайпа и удержание кулака | `handsFreeSection` в `KitchenApp/Features/Settings/SettingsView.swift` |
| Требуемый ключ Info.plist | `NSCameraUsageDescription` (комментарий в `HandGestureDetector.swift`) |

Точка интеграции — `CookingSessionView` (Этап 9): она владеет детектором,
накладывает оверлей, мапит жесты на навигацию/таймер и управляет жизненным
циклом камеры параллельно с голосовыми командами.

### Каталог жестов: `GestureType`

`GestureType` — `enum` из четырёх жестов; каждый несёт локализованное название
(`displayName`) и SF-иконку (`iconName`) для карточки оверлея:

| Кейс | Жест | Действие в сессии | Иконка |
|---|---|---|---|
| `swipeNext` | открытая ладонь вправо | следующий шаг (`navigateNext`) | `hand.point.right.fill` |
| `swipePrev` | открытая ладонь влево | предыдущий шаг (`navigatePrev`) | `hand.point.left.fill` |
| `fistHold` | сжатый кулак (удержание) | пауза/запуск таймера (`timer.toggle`) | `hand.raised.fill` |
| `victory` | два пальца V | подтверждение (тактильный отклик) | `hand.raised.fingers.spread.fill` |

Маппинг «жест → действие» задаётся в `CookingSessionView.wireGestureDetector()`
и согласован с навигацией Этапа 9 (те же операции `navigateNext`/`navigatePrev`).

### Детектор: `HandGestureDetector`

`HandGestureDetector` (`NSObject`, `ObservableObject`) инкапсулирует
`AVCaptureSession`, `VNDetectHumanHandPoseRequest` и логику распознавания.
Публикует три поля для UI:

- `detectedGesture: GestureType?` — последний распознанный жест (для оверлея;
  сам себя гасит через 1.5 с);
- `isRunning: Bool` — активна ли камера;
- `detectionConfidence: Float` — уверенность распознавания по точке запястья
  (питает полосу уверенности в оверлее).

Внешняя точка выхода — замыкание `onGesture: ((GestureType) -> Void)?`, которое
`CookingSessionView` привязывает к навигации и таймеру.

**Захват кадров.** `start()` запрашивает доступ к камере
(`AVCaptureDevice.requestAccess`) и при согласии в `setupAndStart()` поднимает
`AVCaptureSession` с фронтальной камерой (`.builtInWideAngleCamera`, `.front`,
пресет `.medium`). Кадры уходят в `AVCaptureVideoDataOutput`, делегат которого
работает на приватной очереди `processingQueue` (`qos: .userInteractive`,
`alwaysDiscardsLateVideoFrames = true`) — вся тяжёлая обработка **вне** главного
потока, UI-поля публикуются через `DispatchQueue.main.async`. `stop()` гасит
сессию и обнуляет состояние.

**Распознавание позы.** Для каждого кадра создаётся `VNDetectHumanHandPoseRequest`
(`maximumHandCount = 1`) и выполняется `VNImageRequestHandler`
(`orientation: .leftMirrored` — компенсация фронтальной камеры). Если руки в кадре
нет — состояние свайпа/кулака сбрасывается и `detectionConfidence` обнуляется.

**Порядок проверки жестов** (`detectGesture`): сначала кулак (с накоплением
удержания через `fistDetectedAt` и порогом `fistHoldDuration`), затем V, затем —
если ладонь открыта — свайп. Открытая ладонь/кулак определяются по числу
выпрямленных пальцев: `isExtended` сравнивает `y` кончика (`…Tip`) и сустава
(`…MCP`) с запасом, при `confidence > 0.3`; ладонь — ≥3 выпрямленных, кулак — ≥3
согнутых; V — указательный+средний выпрямлены, безымянный+мизинец согнуты.

**Определение свайпа.** `detectSwipe(from:)` берёт точку запястья (`.wrist`,
`confidence > 0.4`) и считает дельту `x` относительно предыдущего кадра
(история в `wristBuffer`, `previousWristPosition`). Так как фронтальная камера
зеркальна, свайп вправо уменьшает `wrist.x`: `deltaX < -swipeSensitivity` →
`swipeNext`, `deltaX > swipeSensitivity` → `swipePrev`.

**Защита от дребезга.** Между жестами выдерживается `cooldown = 1.5 с` (те же
1.5 с, что у голосовых команд): срабатывания чаще игнорируются, при этом старт
удержания кулака продолжает отслеживаться. При распознавании обновляется
`detectedGesture`, вызывается `onGesture`, и через 1.5 с жест снимается с оверлея,
если новый не пришёл.

**Параметры.** `swipeSensitivity` (мин. дельта запястья, 0.02–0.10) и
`fistHoldDuration` (время удержания кулака, 0.5–2.0 с) читаются из `UserDefaults`
(ключи `handsfree.swipeSensitivity` / `handsfree.fistHoldDuration`, дефолты
0.04 / 1.0 через хелпер `Double.nonzero(default:)`) и настраиваются в
`SettingsView`.

### Оверлей: `HandsFreeOverlayView`

`HandsFreeOverlayView` — прозрачный оверлей поверх `CookingSessionView`,
размещённый **снизу** (`padding(.bottom, 100)`), чтобы не перекрывать верхний
`VoiceCommandOverlayView`. Полностью пассивен (`allowsHitTesting(false)`) — не
перехватывает свайпы сессии. Состоит из двух частей:

- **`statusBadge`** — капсула «Hands-free активен» с пульсирующим индикатором и
  **полосой уверенности** (`confidence`): цвет меняется красный → жёлтый →
  зелёный (`confidenceColor`), показывается пока `isActive == true`;
- **`gestureCard`** — карточка с иконкой и названием последнего жеста, появляется
  через `.scale + .opacity`-переход и `spring`-анимацию при смене `gesture`.

### Интеграция в `CookingSessionView`

`CookingSessionView` владеет `@StateObject gestureDetector` и локальным
состоянием `handsFreeEnabled` / `showCameraPermissionAlert`:

- в `onAppear` вызывается `wireGestureDetector()`; если в настройках включён
  `handsfree.enabledByDefault` (`UserDefaults`) — `handsFreeEnabled` сразу
  поднимается;
- тумблеры («OFF/ON» в хедере и «Жесты» внизу экрана) переключают
  `handsFreeEnabled`; `onChange(of: handsFreeEnabled)` стартует/останавливает
  детектор;
- `startHandsFree()` смотрит `AVCaptureDevice.authorizationStatus`: при
  `.authorized` / `.notDetermined` — `start()` (сам запросит разрешение); при
  `.denied` / `.restricted` — сбрасывает тумблер и показывает алерт о доступе к
  камере;
- `onChange(of: scenePhase)` при уходе приложения из `.active` останавливает
  детектор и сбрасывает `handsFreeEnabled` (симметрично голосовым командам).

Жесты работают **независимо** от голосовых команд — можно включить оба режима
одновременно; оба вызывают одни и те же операции навигации/таймера.

### Настройки: секция Hands-Free

В `SettingsView` секция `handsFreeSection` содержит:

- **`cameraPermissionRow`** — статус доступа к камере;
- **тумблер «Включать по умолчанию»** — пишет флаг `handsfree.enabledByDefault`
  в `UserDefaults` (его читает `CookingSessionView` при старте сессии);
- **слайдер «Чувствительность свайпа»** (0.02…0.10, шаг 0.01) — пишет
  `handsfree.swipeSensitivity`; текстовый ярлык `sensitivityLabel` показывает
  «Высокая / Средняя / Низкая» (меньше значение = реагирует на меньшее движение);
- **слайдер «Удержание кулака»** (0.5…2.0 с, шаг 0.1) — пишет
  `handsfree.fistHoldDuration`;
- **footer** — пояснение приватности: видеопоток обрабатывается только на
  устройстве и никогда не передаётся на сервер.

Ключи `UserDefaults` (`handsfree.swipeSensitivity` / `handsfree.fistHoldDuration`
/ `handsfree.enabledByDefault`) и дефолты (0.04 / 1.0) согласованы между
`SettingsView` ↔ `HandGestureDetector` ↔ `CookingSessionView`.

---

## MVP — Поиск и фильтрация

Поиск и фильтрация рецептов на витрине (SPEC.md §2.4, §6 «MVP»). Пользователь
находит рецепт тремя способами: **полнотекстовым поиском** по строке (с debounce),
**фильтр-шторкой** (категория / сложность / максимальное время / теги) и
**чипами активных фильтров** для быстрого снятия отдельного условия. Раздел
описывает **только клиентскую часть**: сборку параметров запроса, UI-элементы и
их связь с загрузкой списка. Серверная фильтрация (`GET /recipes`) документируется
в бэкенд-этапах и здесь не рассматривается.

В отличие от Этапа 8 (где поиск/фильтр показаны как часть экрана списка целиком),
здесь фича описана как сквозной MVP-сценарий: как из ввода пользователя рождается
`RecipesQuery`, как он сериализуется в `URLQueryItem` и как переиспользуется на
экране категорий.

### Состав фичи

| Подзадача | Где реализовано |
|---|---|
| Модель параметров поиска/фильтра | `struct RecipesQuery` в `KitchenApp/Core/Network/Endpoint.swift` |
| Сериализация в query-параметры | `RecipesQuery.queryItems` в `Endpoint.swift` |
| Строка поиска + debounce 300 мс | `.searchable` / `scheduleSearch(_:)` в `KitchenApp/Features/Recipes/RecipeListView.swift` |
| Фильтр-шторка (категория/сложность/время/теги) | `FilterSheetView` в `RecipeListView.swift` |
| Чипы активных фильтров | `filterChips` / `FilterChip` / `hasActiveFilters` в `RecipeListView.swift` |
| Загрузка результата с учётом фильтров | `RecipeViewModel.loadRecipes(query:reset:)`, `loadCategories()`, `loadTags(q:)` |
| Переиспользование на экране категорий | `KitchenApp/Features/Categories/CategoryView.swift` |

### Модель запроса: `RecipesQuery`

`RecipesQuery` (`Endpoint.swift`) — единая value-модель поиска, фильтров и
пагинации. Поля соответствуют параметрам `GET /recipes` из SPEC.md §3.5:

| Поле | Тип | Параметр URL | Назначение |
|---|---|---|---|
| `q` | `String?` | `q` | полнотекстовый поиск по названию/описанию |
| `category` | `UUID?` | `category` | фильтр по категории |
| `tags` | `[UUID]` | повторяющийся `tags` | фильтр по тегам (OR) |
| `difficulty` | `Difficulty?` | `difficulty` | easy / medium / hard |
| `maxTime` | `Int?` | `max_time` | максимальное время приготовления, мин |
| `page` | `Int` (1) | `page` | номер страницы (пагинация) |
| `perPage` | `Int` (20) | `per_page` | размер страницы |

Вычисляемое свойство `queryItems: [URLQueryItem]` детерминированно собирает
параметры и передаётся в `APIClient` через `Endpoint.recipes(_:)` (см. Этап 6).
Опциональные фильтры добавляются только когда заданы (`if let …`), поэтому пустой
`RecipesQuery` шлёт лишь `page` и `per_page`. Два нюанса сериализации, критичных
для совпадения фильтра на сервере, зафиксированы прямо в коде:

- **UUID в нижнем регистре.** `category` и каждый `tags`-элемент отправляются как
  `uuidString.lowercased()`: `Foundation.UUID.uuidString` даёт строку в ВЕРХНЕМ
  регистре, а бэкенд хранит id как строчные UUID и сравнивает регистрозависимо —
  без нормализации фильтр молча возвращал бы пустой список.
- **Повторяющийся `tags`, а не `tags[]`.** Массив тегов кодируется как несколько
  одноимённых параметров `tags=<id>`, потому что парсер querystring Fastify
  ожидает `tags` (union `string | string[]`); скобки в имени сломали бы фильтр.

### Строка поиска с debounce

Поле поиска подключается модификатором `.searchable(text: $searchText, prompt:)`.
Изменение `searchText` обрабатывает `onChange` → `scheduleSearch(_:)`, который
реализует **debounce 300 мс** (SPEC.md §2.4):

- отменяет предыдущую задачу (`searchDebounceTask?.cancel()`);
- запускает новую `Task`, ждёт `Task.sleep(for: .milliseconds(300))` и при
  `Task.isCancelled` выходит — за время набора успевает выполниться только
  последний запрос, лишних обращений к сети нет;
- пишет результат в `query.q` (пустая строка → `nil`, чтобы не слать пустой `q`)
  и перезагружает список с `reset: true`.

`searchDebounceTask` хранится в `@State`, поэтому одна и та же задача переживает
перерисовки и корректно отменяется при следующем нажатии.

### Фильтр-шторка: `FilterSheetView`

Кнопка фильтра в тулбаре (`showFilterSheet`) открывает `FilterSheetView` как
`sheet`. Шторка получает `@Binding var query`, справочники `categories`/`tags`
и замыкание `onApply`. Ключевой приём — **локальный черновик состояния**:

- поля `selectedCategory` / `selectedDifficulty` / `maxTime` / `selectedTagIds`
  — это `@State`, инициализируемые из `query` в `.onAppear`;
- пользователь меняет их внутри `Form` (категория — `Picker(.menu)`, сложность —
  сегментированный `Picker(.segmented)` по `Difficulty.allCases`, время —
  `Stepper` в диапазоне 5…300 с шагом 5 мин, теги — мультиселект `Set<UUID>` с
  чекмарками);
- при большом числе тегов (`tags.count > 6`) появляется поле «Поиск тегов»
  (`tagSearchText`), фильтрующее список через `localizedCaseInsensitiveContains`;
- изменения **не применяются на лету** — только по кнопке «Применить» черновик
  переносится в `query` и вызывается `onApply()`, который закрывает шторку и
  запускает `loadRecipes(query:reset:)`. Кнопка «Отмена» вызывает `onApply()` без
  переноса — выбор отбрасывается.

### Чипы активных фильтров

`hasActiveFilters` (true, если задан хоть один из `category` / `difficulty` /
`maxTime` / `tags`) управляет двумя вещами: подсвечивает иконку фильтра в тулбаре
(залитый вариант, оранжевый цвет) и включает ленту `filterChips` над сеткой.

`filterChips` — горизонтальный `ScrollView` из `FilterChip` по каждому активному
условию (сложность, «До N мин», имя категории, `#тег`). Крестик на чипе снимает
**один** фильтр (обнуляет соответствующее поле `query` / удаляет id из `tags`) и
сразу перезагружает список с `reset: true`; отдельная кнопка «Сбросить всё»
обнуляет все фильтры разом. Имена категории и тега резолвятся из справочников
`viewModel.categories` / `viewModel.tags` по id (с фолбэком «Категория» / «Тег»).

### Загрузка результата: `RecipeViewModel`

Любое изменение поиска или фильтра приводит к `loadRecipes(query:reset:)` с
`reset: true` — метод обнуляет пагинацию (`currentPage = 1`), очищает `recipes`,
поднимает `hasMore` и грузит первую страницу нового результата (детали пагинации
— в Этапе 8). Справочники для шторки грузятся один раз в `.task` экрана:
`loadCategories()` (кэширует, пока `categories` пуст) и `loadTags(q:)`
(эндпоинт `.tags(q:)` умеет искать теги по строке); ошибки обоих **не фатальны** —
фильтр остаётся работоспособным даже без справочников.

### Переиспользование на экране категорий

`CategoryView` (`KitchenApp/Features/Categories/CategoryView.swift`) использует ту
же связку: заводит собственный `RecipesQuery`, проставляет `query.category` =
id выбранной категории и вызывает тот же `RecipeViewModel.loadRecipes(query:)` —
поиск/фильтр/пагинация работают идентично витрине без дублирования логики.

---

## MVP — Таймер на шаге

Обратный отсчёт, привязанный к конкретному шагу рецепта (SPEC.md §2.6, §6
«MVP»). Пользовательский сценарий: автор задаёт таймер при авторинге шага
(например, «варить пасту 8:00»), а во время готовки этот таймер доступен прямо
в карточке шага — его можно запустить, поставить на паузу и сбросить, а по
окончании приходит звуковой/тактильный сигнал. Слой полностью **клиентский**:
отсчёт идёт на устройстве, сервер лишь хранит длительность в секундах
(`Step.timerSec`). Фича сквозная — затрагивает модель, редактор, режим
приготовления и настройки; ниже она собрана со стороны своей главной функции —
таймера шага. Техническая механика `TimerService` подробно разобрана в Этапе 9
(«Таймер шага: `TimerService` + сохранение состояния»), здесь — сквозной обзор
всей фичи.

### Состав фичи

| Подзадача | Где реализовано |
|---|---|
| Хранение длительности в модели шага | `Step.timerSec: Int?` в `KitchenApp/Shared/Models/Models.swift` |
| Авторинг таймера (тумблер + минуты:секунды) | `timerSection` в `KitchenApp/Features/Editor/StepEditorView.swift` |
| Сервис обратного отсчёта | `TimerService` в `KitchenApp/Features/Cooking/TimerService.swift` |
| UI таймера в сессии (play/pause/reset) | `timerControl` в `KitchenApp/Features/Cooking/CookingSessionView.swift` |
| Сохранение состояния между шагами | `timerStates` + `saveTimerState`/`configureTimerForStep` в `CookingSessionView.swift` |
| Сигнал окончания (звук/вибрация) | `resume()` в `TimerService.swift` + флаги `timer.sound`/`timer.haptic` |
| Настройки сигнала | `notificationsSection` в `KitchenApp/Features/Settings/SettingsView.swift` |
| Форматирование `MM:SS` | `Int.formattedTimer` в `KitchenApp/Shared/Extensions/Extensions.swift` |
| Управление таймером жестом/голосом | `wireGestureDetector`/`wireVoiceCommands` в `CookingSessionView.swift` |

### Модель: `Step.timerSec`

Длительность таймера хранится в доменной модели шага как опциональное поле
`timerSec: Int?` (секунды), декодируется из ключа `timer_sec` серверного JSON
(`CodingKeys` в `Models.swift`). `nil` или `0` означают «у шага нет таймера» —
это признак, по которому UI решает, показывать ли блок таймера. Значение —
единственное, что персистится; сам ход отсчёта живёт только на клиенте во время
сессии.

### Авторинг: `StepEditorView.timerSection`

В редакторе шага (`StepEditorView`) секция «Таймер» состоит из тумблера
«Использовать таймер» (`step.timerEnabled`) и, когда он включён, двух колёсных
пикеров:

- **Минуты** — `Picker` со значениями `0..<120`;
- **Секунды** — `Picker` с шагом 5 (`stride(from: 0, to: 60, by: 5)`).

Пикеры связаны с `step.timerMinutes`/`step.timerSeconds`; вью-модель редактора
сворачивает их в итоговые `timerSec` при сохранении шага (соответствует
SPEC.md §2.8 — «Таймер: toggle + поле ввода (минуты:секунды)»).

### Отсчёт: `TimerService`

`TimerService` (`@MainActor`, `ObservableObject`) — один экземпляр на всю
сессию приготовления. Публикует `remaining` (секунды), `isRunning`,
`isFinished`; отсчёт реализован через `Task` с `Task.sleep` на 1 секунду,
уменьшающий `remaining`. Методы `configure(seconds:)`, `restore(...)`,
`toggle()`/`resume()`/`pause()`/`stop()` описаны в Этапе 9. Свойство
`formattedTime` отдаёт остаток в виде `MM:SS` через расширение
`Int.formattedTimer` (`String(format: "%02d:%02d", self / 60, self % 60)`).

### UI и сохранение состояния в сессии

Блок таймера (`timerControl` в `CookingSessionView`) рисуется в карточке шага
только при `timerSec > 0`: монопространственное время (после окончания —
зелёное, с `contentTransition(.numericText())`), кнопка play/pause и кнопка
сброса (`arrow.counterclockwise`), а по завершении — метка «Время вышло!» и
галочка.

Поскольку `TimerService` один, состояние каждого шага держится в словаре
`timerStates: [Int: (remaining, isFinished)]`: `saveTimerState(for:)` при уходе
с шага сохраняет остаток и ставит таймер на паузу, а `configureTimerForStep(_:)`
при входе либо восстанавливает сохранённое состояние (`restore`), либо задаёт
свежий отсчёт (`configure`). Кнопка сброса очищает запись в `timerStates`.
Так, вернувшись на предыдущий шаг, пользователь видит таймер там же, где
оставил (SPEC.md §2.6 — «таймер сохраняет состояние при переключении шагов»).

### Сигнал окончания и его настройки

При достижении нуля `TimerService` выставляет `isFinished = true` и подаёт
сигнал окончания: системный звук (`AudioServicesPlaySystemSound(1315)`) и/или
вибрацию (`kSystemSoundID_Vibrate`). Оба канала управляются флагами
`timer.sound` и `timer.haptic` в `UserDefaults` (по умолчанию включены).
Тумблеры «Звук по окончании» и «Вибрация по окончании» задаются в
`SettingsView.notificationsSection` (Этап 12), которая пишет те же ключи —
`TimerService` читает их в момент срабатывания, поэтому изменение настройки
действует сразу без перезапуска сессии.

### Управление таймером без касания

Таймер шага интегрирован с hands-free-слоями: жест «сжатый кулак» и голосовая
команда «таймер» оба мапятся на `timer.toggle()` — в `wireGestureDetector()`
(кейс `.fistHold`) и `wireVoiceCommands()` (кейс `.toggleTimer`) соответственно.
Это позволяет запускать и приостанавливать отсчёт с грязными руками, не
прерывая готовку (см. разделы про Hands-free и голосовые команды).


## После MVP — Синхронизация между устройствами (iCloud sync)

Синхронизация пользовательских данных между устройствами одного Apple ID через
iCloud (SPEC.md §6 «После MVP» — «Синхронизация между устройствами (iCloud /
server sync)»). Реализован **iCloud-вариант** синхронизации: черновики рецептов
и офлайн-кэш просмотренных рецептов, хранящиеся в SwiftData, автоматически
реплицируются в приватную базу CloudKit и подтягиваются на другие устройства
пользователя. Слой **полностью клиентский** — приложение не обращается к
собственному бэкенду для синхронизации, вся репликация идёт через CloudKit
средствами SwiftData; серверных эндпоинтов синхронизации нет. Фича сквозная:
затрагивает конфигурацию SwiftData-контейнера при запуске, отдельный
сервис-статус `CloudKitSyncService` и секцию настроек.

### Состав фичи

| Подзадача | Где реализовано |
|---|---|
| Что синхронизируется (SwiftData-модели) | `DraftRecipe`, `CachedRecipeDetail` в `KitchenApp/Core/Persistence/` |
| Включение CloudKit на контейнере | `makeModelContainer()` в `KitchenApp/KitchenRecipeApp.swift` |
| Фиксация «состояния на старте» | `CloudKitSyncService.configureLaunchSync()` |
| Сервис статуса и предпочтений | `CloudKitSyncService` в `KitchenApp/Core/Sync/CloudKitSyncService.swift` |
| Модель статуса | `enum SyncStatus` там же |
| UI настроек (тумблер, статус, дата) | `iCloudSyncSection` в `KitchenApp/Features/Settings/SettingsView.swift` |
| Внедрение в окружение | `.environment(CloudKitSyncService.shared)` в `KitchenRecipeApp` |
| Локализация статусов | ключи `sync.*` в `KitchenApp/Resources/*.lproj/Localizable.strings` |

### Что синхронизируется

Синхронизации подлежат две локальные SwiftData-модели, входящие в общую
`Schema`:

- **`DraftRecipe`** — черновики рецептов из редактора (Этап 11): название,
  описание, ингредиенты/шаги/теги в виде JSON-полей, обложка, `updatedAt`;
- **`CachedRecipeDetail`** — офлайн-кэш просмотренных рецептов (Этап 12):
  `recipeId`, сериализованный `recipeData`, заголовок и `cachedAt`.

Обе модели используются в приложении как локальное хранилище; когда iCloud
включён, тот же самый стор реплицируется через CloudKit, поэтому черновик,
начатый на iPhone, доступен на iPad, а просмотренные офлайн рецепты
переносятся между устройствами. Серверные (сетевые) данные при этом не
дублируются — источником опубликованных рецептов остаётся API.

### Включение CloudKit на контейнере (`KitchenRecipeApp`)

Контейнер SwiftData создаётся один раз при запуске в статическом
`makeModelContainer()`:

1. Собирается `Schema([DraftRecipe.self, CachedRecipeDetail.self])`.
2. `CloudKitSyncService.configureLaunchSync()` возвращает, включён ли iCloud в
   предпочтениях, **и** запоминает это значение как «состояние на старте»
   (для логики подсказки о перезапуске, см. ниже).
3. Если синхронизация включена — создаётся `ModelConfiguration` с
   `cloudKitDatabase: .automatic` (использует контейнер iCloud по умолчанию;
   требует включённых capability iCloud + CloudKit в проекте Xcode).
4. Если инициализация CloudKit-контейнера падает (нет entitlements, симулятор,
   нет аккаунта iCloud) — приложение **не** аварийно завершается, а мягко
   деградирует до локального стора (`ModelConfiguration(schema:)` без CloudKit),
   оставаясь полностью рабочим. Только сбой создания даже локального контейнера
   считается фатальным.

Контейнер невозможно «горячо» пересобрать во время работы, поэтому решение
CloudKit/локально принимается ровно один раз за запуск.

### Сервис `CloudKitSyncService`

`@Observable`-синглтон (`CloudKitSyncService.shared`), внедряемый в окружение
SwiftUI через `.environment(...)`. Отвечает за **предпочтение** и **статус**
синхронизации, но не за саму репликацию (её выполняет SwiftData+CloudKit):

- **Состояние (read-only снаружи):** `status: SyncStatus`, `lastSyncDate: Date?`,
  `isSyncEnabled: Bool`, `requiresRestartToBecomeActive: Bool`.
- **`setEnabled(_:)`** — переключает предпочтение, пишет его в `UserDefaults`
  (`sync.iCloudEnabled`) и пересчитывает флаг «нужен перезапуск», сравнивая
  новое значение с зафиксированным на старте (`sync.wasEnabledAtLaunch`). Так
  как контейнер уже создан, изменение вступает в силу только на следующем
  холодном запуске — поэтому включение/выключение не трогает активный стор.
- **`checkAccountStatus()`** (`@MainActor`, `async`) — запрашивает
  `CKContainer.default().accountStatus()` и переводит `status` в одно из
  состояний `SyncStatus`; при `.available` фиксирует `lastSyncDate` и пишет его
  в `UserDefaults` (`sync.lastDate`). Вызывается при инициализации, при
  включении тумблера и по кнопке «Обновить».
- **`configureLaunchSync()`** (static) — вызывается один раз при старте до
  создания контейнера; записывает текущее предпочтение как «состояние на
  старте» и возвращает, нужно ли использовать CloudKit.

### Модель статуса `SyncStatus`

`enum SyncStatus` описывает все отображаемые состояния синхронизации:
`unknown`, `syncing`, `synced`, `error(String)`, `disabled`,
`accountNotAvailable`. Каждый кейс несёт `systemImageName` (иконка SF Symbols,
например `checkmark.icloud.fill` для `synced`, `icloud.slash` для `disabled`) и
`localizedDescription` — локализованный текст через `NSLocalizedString`
(ключи `sync.status.*` и `sync.error.*`). Ошибки аккаунта iCloud
(`.restricted`, `.couldNotDetermine`, `.temporarilyUnavailable`) маппятся в
`.error(...)` с понятными сообщениями.

### UI настроек (`SettingsView.iCloudSyncSection`)

Секция «Синхронизация» в `SettingsView` полностью управляется состоянием
сервиса:

- **Тумблер** «Синхронизация iCloud» связан двусторонним `Binding` с
  `isSyncEnabled`/`setEnabled(_:)`.
- **Строка статуса** (только при включённой синхронизации): иконка
  `status.systemImageName` (или `ProgressView` при `.syncing`), локализованный
  текст `status.localizedDescription` и цвет по состоянию (`syncStatusColor`:
  зелёный — synced, синий — syncing, красный — ошибки), плюс кнопка «Обновить»,
  вызывающая `checkAccountStatus()`.
- **Дата последней синхронизации** — `lastSyncDate` в относительном формате
  (`.relative(presentation: .named)`).
- **Подсказка о перезапуске** — показывается при
  `requiresRestartToBecomeActive`, когда тумблер меняли уже после запуска.
- **Приглашение войти в iCloud** — при статусе `.accountNotAvailable` кнопка
  открывает системные «Настройки» (`UIApplication.openSettingsURLString`).
- Футер секции поясняет, что через iCloud синхронизируются черновики и кэш
  рецептов.

### Приватность и деградация

Синхронизируются только локальные данные пользователя (черновики и кэш) в его
**приватной** базе CloudKit — привязанной к Apple ID, а не к бэкенду
приложения. Отсутствие iCloud-аккаунта, entitlements или запуск в симуляторе не
ломают приложение: контейнер прозрачно откатывается к локальному хранилищу, а
секция настроек отражает реальный статус (`disabled` / `accountNotAvailable` /
`error`).
