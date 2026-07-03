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
