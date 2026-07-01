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
