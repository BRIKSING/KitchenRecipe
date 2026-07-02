# Техническое задание: Кулинарное приложение Kitchen

## 1. Общее описание

Приложение для хранения и пошагового просмотра кулинарных рецептов под iOS/iPadOS с возможностью управления шагами приготовления жестами рук через камеру (hands-free режим).

---

## 2. Клиент (iOS/iPadOS)

### 2.1 Технологии

| Компонент | Выбор |
|---|---|
| Язык | Swift 5.9+ |
| UI Framework | SwiftUI |
| Минимальная версия | iOS 17 / iPadOS 17 |
| Жесты рук | Vision Framework (VNDetectHumanHandPoseRequest) |
| Сетевой слой | URLSession + async/await |
| Кэш изображений | NSCache + файловый кэш |
| Хранилище черновиков | SwiftData |
| Состояние | @Observable (Swift 5.9 Observation) |

### 2.2 Архитектура клиента

Паттерн: **MVVM** с разделением слоёв:

```
App
├── Core
│   ├── Network         — APIClient, Endpoint, NetworkError
│   ├── Cache           — ImageCache, RecipeCache
│   ├── Persistence     — SwiftData (черновики)
│   └── Vision          — HandGestureDetector, GestureType
├── Features
│   ├── Auth            — LoginView, RegisterView, AuthViewModel
│   ├── Recipes         — RecipeListView, RecipeDetailView, RecipeViewModel
│   ├── Cooking         — CookingSessionView, CookingViewModel, TimerService
│   ├── Editor          — RecipeEditorView, StepEditorView, EditorViewModel
│   ├── Categories      — CategoryView, CategoryViewModel
│   └── Settings        — SettingsView, SettingsViewModel
├── Shared
│   ├── Components      — переиспользуемые View-компоненты
│   ├── Extensions      — расширения стандартных типов
│   └── Models          — DTO, доменные модели
└── Resources           — Assets, Localizable.strings
```

### 2.3 Структура экранов

```
TabBar
├── Рецепты (RecipesTab)
│   ├── RecipeListView       — список всех рецептов
│   ├── RecipeDetailView     — карточка рецепта (инфо + список шагов)
│   └── CookingSessionView   — пошаговый режим приготовления
├── Категории (CategoriesTab)
│   └── CategoryView         — рецепты по категории
└── Профиль (ProfileTab)
    └── SettingsView         — настройки (жесты, язык, сервер)
```

### 2.4 Экран RecipeListView

**Лейаут:**
- Сетка карточек: 2 колонки на iPhone, 3–4 на iPad (LazyVGrid с адаптивными колонками)
- Каждая карточка: обложка (aspect ratio 4:3), название, время, сложность, теги

**Поиск и фильтрация:**
- `searchable` — поиск по названию и тегам (debounce 300 мс)
- Фильтр-шторка (sheet): категория, сложность (easy/medium/hard), максимальное время
- Активные фильтры отображаются как чипы под строкой поиска с кнопкой сброса

**Прочее:**
- Pull-to-refresh (`refreshable`)
- Пагинация при достижении конца списка (infinity scroll)
- Кнопка `+` (FAB) → RecipeEditorView
- Состояния: загрузка (skeleton), пустой список, ошибка с кнопкой retry

### 2.5 Экран RecipeDetailView

**Секции (ScrollView):**
1. **Hero-область** — обложка рецепта с параллакс-эффектом, поверх: название + категория
2. **Мета-блок** — иконки с подписями: время, порции, сложность
3. **Теги** — горизонтальная прокрутка чипов
4. **Описание** — expandable текст (показывать первые 3 строки, кнопка «Читать далее»)
5. **Ингредиенты** — список с количеством и единицами; кнопка масштабирования порций (множитель ×0.5, ×1, ×2, ×3)
6. **Шаги** — превью-список: номер + заголовок + миниатюра первого фото
7. **Закреплённая кнопка** — «Начать приготовление» (прилипает к bottom safe area)

**Действия:**
- Редактирование (только для автора) → RecipeEditorView
- Поделиться рецептом (Share Sheet, deeplink)

### 2.6 Экран CookingSessionView (ключевой экран)

**Полноэкранный пошаговый режим:**

```
┌─────────────────────────────────────┐
│  [✕ Выйти]          Шаг 2 из 7     │
│─────────────────────────────────────│
│                                     │
│   [ фото шага — PageView/слайдер ]  │
│         ○ ● ○  (dot indicator)      │
│                                     │
│─────────────────────────────────────│
│  Сварить пасту                      │
│  Отварить спагетти в подсолённой    │
│  воде до состояния аль денте...     │
│                                     │
│  [ Таймер: 08:00  ▶ ]               │
│─────────────────────────────────────│
│  [◀ Назад]  ━━━━●━━━━━━  [Вперёд ▶]│
│                                     │
│  [ 👁 Hands-free: OFF ]             │
└─────────────────────────────────────┘
```

**Детали реализации:**
- Фото шага — `TabView` с `PageTabViewStyle`, поддержка pinch-to-zoom
- Таймер — обратный отсчёт, сохраняет состояние при переключении шагов, звуковой сигнал по окончании
- Навигация свайпом по горизонтали (жест + кнопки)
- Прогресс-бар вверху экрана (заполняется по мере прохождения шагов)
- Блокировка автоблокировки экрана (`UIApplication.shared.isIdleTimerDisabled = true`) на время сессии
- Экран «Готово!» после последнего шага с анимацией и кнопкой «Оценить рецепт»

### 2.7 Hands-Free режим (жестовое управление)

**Цель:** при готовке руки заняты или грязные — пользователь управляет шагами жестами перед камерой.

**Реализация через Vision Framework:**

| Жест | Действие |
|---|---|
| Открытая ладонь → движение вправо | Следующий шаг |
| Открытая ладонь → движение влево | Предыдущий шаг |
| Сжатый кулак (удержание 1 сек) | Пауза/продолжение таймера |
| Два пальца вверх (V) | Подтверждение / голосовая подсказка |

**Технические детали:**
- `AVCaptureSession` + `VNDetectHumanHandPoseRequest` (Vision)
- Анализ позиции ключевых точек пальцев (landmarks: wrist, fingertips)
- Определение направления свайпа по дельте положения запястья между кадрами
- Обработка в фоновом потоке (`DispatchQueue`), UI-обновления на главном
- Прозрачный оверлей с визуальной индикацией распознанного жеста (иконка + название жеста)
- Индикатор уверенности распознавания (confidence bar)
- Настройка чувствительности в Settings (порог дельты, время удержания)
- Автоотключение при сворачивании приложения (`scenePhase`)
- Задержка между срабатываниями — 1.5 сек (защита от случайных жестов)

**Privacy:**
- Запрос разрешения на камеру с пояснением (NSCameraUsageDescription)
- Видеопоток **не** передаётся на сервер, обрабатывается только локально
- В настройках — чёткое пояснение, зачем нужна камера

### 2.8 Экран RecipeEditorView (создание/редактирование)

**Структура формы (многошаговая или единый ScrollView):**

1. **Основная информация**
   - Название (обязательное, макс. 100 символов)
   - Описание (textarea)
   - Обложка (PhotosPicker / Camera, crop до 16:9)
   - Категория (Picker)
   - Теги (мультиселект + создание нового тега)
   - Сложность (сегментированный контрол: Лёгкий / Средний / Сложный)
   - Время приготовления (Stepper, шаг 5 мин)
   - Количество порций (Stepper)

2. **Ингредиенты**
   - Список с полями: название + количество + единица (г, мл, шт, ст.л. …)
   - Swipe-to-delete, drag-to-reorder (EditMode)
   - Кнопка «Добавить ингредиент»

3. **Шаги приготовления**
   - Список шагов с drag-to-reorder
   - Каждый шаг раскрывается в StepEditorView:
     - Заголовок и описание шага
     - До 5 фото (PhotosPicker + Camera, превью с удалением)
     - Таймер: toggle + поле ввода (минуты:секунды)
   - Кнопка «Добавить шаг»

**Поведение:**
- Автосохранение черновика в SwiftData каждые 30 сек
- Валидация перед публикацией (название обязательно, минимум 1 шаг)
- Кнопки «Сохранить черновик» и «Опубликовать»
- Предупреждение при выходе с несохранёнными изменениями

### 2.9 Экран SettingsView

- Адрес сервера (текстовое поле, проверка доступности)
- Hands-free: включить/выключить по умолчанию, чувствительность (Slider)
- Язык интерфейса (Picker: системный / RU / EN)
- Уведомления таймера (звук, вибрация)
- Аккаунт: имя, email, выйти, удалить аккаунт
- О приложении: версия, лицензии

### 2.10 Сетевой слой

```swift
// Структура APIClient
APIClient
├── func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
├── func upload(image: Data, to endpoint: Endpoint) async throws -> UploadResponse
└── Interceptor: автоматическое обновление JWT (refresh token flow)

Endpoint — enum с ассоциированными значениями:
  case recipes(RecipesQuery)
  case recipe(UUID)
  case createRecipe(RecipeCreateRequest)
  ...
```

**Обработка ошибок:**
- `NetworkError`: noConnection, unauthorized (→ redirect to login), serverError(code, message), decodingError
- Retry-логика: 3 попытки с exponential backoff для сетевых ошибок
- Показ error banner в UI через глобальный `ErrorBannerModifier`

### 2.11 Кэширование

- Изображения: `NSCache<NSString, UIImage>` (memory) + файловый кэш в `Caches/` (disk), TTL 7 дней
- Список рецептов: кэш последнего ответа в UserDefaults для offline-просмотра
- Детали рецепта: кэш в SwiftData для offline-доступа к просмотренным рецептам

---

## 3. Бэкенд

### 3.1 Технологии

| Компонент | Выбор |
|---|---|
| Язык | TypeScript 5+ / Node.js 22 |
| Framework | Fastify 4 |
| База данных | PostgreSQL 16 |
| ORM | Prisma 5 |
| Миграции | Prisma Migrate |
| Валидация | Zod |
| Хранилище файлов | S3-совместимое (MinIO / AWS S3) |
| S3-клиент | @aws-sdk/client-s3 |
| Обработка изображений | sharp |
| Аутентификация | JWT (access + refresh tokens) |
| Хэширование паролей | bcrypt |
| Логирование | pino (встроен в Fastify) |
| Rate limiting | @fastify/rate-limit |
| Контейнеризация | Docker + docker-compose |

### 3.2 Структура проекта

```
src/
├── app.ts               — инициализация Fastify, регистрация плагинов
├── server.ts            — точка входа, listen
├── config.ts            — конфигурация через Zod (process.env)
├── plugins/
│   ├── prisma.ts        — Prisma client как Fastify-плагин
│   ├── jwt.ts           — @fastify/jwt
│   ├── multipart.ts     — @fastify/multipart
│   └── rateLimit.ts     — @fastify/rate-limit
├── modules/
│   ├── auth/
│   │   ├── auth.routes.ts
│   │   ├── auth.service.ts
│   │   └── auth.schema.ts   — Zod-схемы + JSON Schema для Fastify
│   ├── recipes/
│   │   ├── recipes.routes.ts
│   │   ├── recipes.service.ts
│   │   └── recipes.schema.ts
│   ├── steps/
│   ├── categories/
│   ├── tags/
│   └── upload/
├── middleware/
│   └── authenticate.ts  — preHandler-хук проверки JWT
├── lib/
│   ├── s3.ts            — обёртка над @aws-sdk/client-s3
│   └── image.ts         — обработка изображений через sharp
└── prisma/
    └── schema.prisma
```

### 3.3 Prisma-схема (модели данных)

```prisma
// prisma/schema.prisma

generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id           String   @id @default(uuid())
  email        String   @unique
  username     String   @unique
  passwordHash String   @map("password_hash")
  createdAt    DateTime @default(now()) @map("created_at")
  recipes      Recipe[]

  @@map("users")
}

model Category {
  id      String   @id @default(uuid())
  name    String   @unique
  slug    String   @unique
  recipes Recipe[]

  @@map("categories")
}

enum Difficulty {
  easy
  medium
  hard
}

model Recipe {
  id           String      @id @default(uuid())
  author       User        @relation(fields: [authorId], references: [id])
  authorId     String      @map("author_id")
  title        String
  description  String?
  category     Category?   @relation(fields: [categoryId], references: [id])
  categoryId   String?     @map("category_id")
  difficulty   Difficulty
  cookTimeMin  Int         @map("cook_time_min")
  servings     Int
  coverImage   String?     @map("cover_image")
  isPublished  Boolean     @default(false) @map("is_published")
  createdAt    DateTime    @default(now()) @map("created_at")
  updatedAt    DateTime    @updatedAt @map("updated_at")
  tags         RecipeTag[]
  ingredients  Ingredient[]
  steps        Step[]

  @@map("recipes")
}

model Tag {
  id      String      @id @default(uuid())
  name    String      @unique
  recipes RecipeTag[]

  @@map("tags")
}

model RecipeTag {
  recipe   Recipe @relation(fields: [recipeId], references: [id], onDelete: Cascade)
  recipeId String @map("recipe_id")
  tag      Tag    @relation(fields: [tagId], references: [id])
  tagId    String @map("tag_id")

  @@id([recipeId, tagId])
  @@map("recipe_tags")
}

model Ingredient {
  id        String @id @default(uuid())
  recipe    Recipe @relation(fields: [recipeId], references: [id], onDelete: Cascade)
  recipeId  String @map("recipe_id")
  name      String
  amount    Float
  unit      String
  sortOrder Int    @map("sort_order")

  @@map("ingredients")
}

model Step {
  id          String      @id @default(uuid())
  recipe      Recipe      @relation(fields: [recipeId], references: [id], onDelete: Cascade)
  recipeId    String      @map("recipe_id")
  sortOrder   Int         @map("sort_order")
  title       String
  description String
  timerSec    Int?        @map("timer_sec")
  photos      StepPhoto[]

  @@map("steps")
}

model StepPhoto {
  id        String @id @default(uuid())
  step      Step   @relation(fields: [stepId], references: [id], onDelete: Cascade)
  stepId    String @map("step_id")
  s3Key     String @map("s3_key")
  sortOrder Int    @map("sort_order")

  @@map("step_photos")
}
```

### 3.4 API Endpoints

#### Аутентификация
```
POST /auth/register       — регистрация
POST /auth/login          — получение токенов
POST /auth/refresh        — обновление access token
POST /auth/logout         — инвалидация refresh token
```

#### Рецепты
```
GET    /recipes                     — список (пагинация, фильтры, поиск)
POST   /recipes                     — создать рецепт
GET    /recipes/{id}                — получить рецепт со всеми данными
PUT    /recipes/{id}                — обновить рецепт
DELETE /recipes/{id}                — удалить рецепт
POST   /recipes/{id}/publish        — опубликовать рецепт
```

#### Шаги
```
GET    /recipes/{id}/steps               — все шаги рецепта
POST   /recipes/{id}/steps               — добавить шаг
PUT    /recipes/{id}/steps/{step_id}     — обновить шаг
DELETE /recipes/{id}/steps/{step_id}     — удалить шаг
PATCH  /recipes/{id}/steps/reorder       — изменить порядок шагов
```

#### Фотографии шагов
```
POST   /steps/{step_id}/photos            — загрузить фото (multipart)
DELETE /steps/{step_id}/photos/{photo_id} — удалить фото
PATCH  /steps/{step_id}/photos/reorder    — изменить порядок фото
```

#### Категории и теги
```
GET  /categories       — список категорий
POST /categories       — создать категорию (admin)
GET  /tags             — список тегов (с поиском)
```

#### Медиа
```
POST /upload/image     — прямая загрузка изображения → возвращает URL
```

### 3.5 Параметры фильтрации GET /recipes

| Параметр | Тип | Описание |
|---|---|---|
| `q` | string | Полнотекстовый поиск по названию и описанию |
| `category` | UUID | Фильтр по категории |
| `tags` | UUID[] | Фильтр по тегам (OR) |
| `difficulty` | enum | easy / medium / hard |
| `max_time` | int | Максимальное время приготовления (мин) |
| `page` | int | Номер страницы |
| `per_page` | int | Размер страницы (max 50) |

### 3.6 Формат ответа GET /recipes/{id}

```json
{
  "id": "uuid",
  "title": "Паста карбонара",
  "description": "...",
  "category": { "id": "uuid", "name": "Паста" },
  "tags": [{ "id": "uuid", "name": "итальянская" }],
  "difficulty": "medium",
  "cook_time_min": 25,
  "servings": 2,
  "cover_image_url": "https://...",
  "ingredients": [
    { "id": "uuid", "name": "Спагетти", "amount": 200, "unit": "г", "sort_order": 1 }
  ],
  "steps": [
    {
      "id": "uuid",
      "sort_order": 1,
      "title": "Сварить пасту",
      "description": "Отварить спагетти в подсолённой воде аль денте...",
      "timer_sec": 480,
      "photos": [
        { "id": "uuid", "url": "https://...", "sort_order": 1 }
      ]
    }
  ],
  "created_at": "2026-01-01T12:00:00Z",
  "updated_at": "2026-01-01T12:00:00Z"
}
```

### 3.7 Загрузка изображений

- Клиент отправляет `POST /upload/image` с `multipart/form-data` (`@fastify/multipart`)
- Сервер валидирует через Zod (тип: JPEG/PNG/HEIC, размер: max 10 MB)
- `sharp`: конвертирует в JPEG, создаёт превью 400×400 и полноразмерный вариант
- `@aws-sdk/client-s3` (`PutObjectCommand`): загружает оба варианта в S3/MinIO
- Возвращает `{ "url": "...", "key": "..." }`
- URL привязывается к шагу через `POST /steps/{id}/photos`

### 3.8 Конфигурация окружения

```ts
// config.ts — Zod-валидация process.env при старте
const envSchema = z.object({
  DATABASE_URL:        z.string().url(),          // postgresql://...
  JWT_ACCESS_SECRET:  z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  JWT_ACCESS_TTL:     z.string().default('15m'),
  JWT_REFRESH_TTL:    z.string().default('30d'),
  S3_ENDPOINT:        z.string().url(),
  S3_BUCKET:          z.string(),
  S3_REGION:          z.string().default('us-east-1'),
  S3_ACCESS_KEY:      z.string(),
  S3_SECRET_KEY:      z.string(),
  PORT:               z.coerce.number().default(3000),
  NODE_ENV:           z.enum(['development', 'production', 'test']),
})
```

---

## 4. Нефункциональные требования

| Требование | Значение |
|---|---|
| Время ответа API (p95) | < 200 мс |
| Размер изображения на шаге | max 10 MB (до конвертации) |
| Офлайн-режим клиента | Просмотр кэшированных рецептов без сети |
| Шифрование | HTTPS (TLS 1.3), пароли — bcrypt |
| iPad-ориентация | Landscape + Portrait |

---

## 5. Этапы разработки

### Этап 1 — Бэкенд: фундамент

- [ ] Инициализация проекта: `npm init`, TypeScript 5+, tsconfig, ESLint + Prettier
- [ ] Установка зависимостей: `fastify`, `@fastify/jwt`, `@fastify/multipart`, `@fastify/rate-limit`, `prisma`, `zod`, `bcrypt`, `sharp`, `@aws-sdk/client-s3`, `pino`
- [ ] Docker-compose: PostgreSQL 16 + MinIO + app-сервис
- [ ] `prisma/schema.prisma` — все модели (User, Category, Recipe, Tag, Ingredient, Step, StepPhoto)
- [ ] `prisma migrate dev --name init` — первая миграция
- [ ] `config.ts` — Zod-валидация `process.env` при старте
- [ ] `app.ts` — инициализация Fastify, регистрация плагинов (prisma, jwt, multipart, rateLimit)
- [ ] Базовый health-check `GET /health`

### Этап 2 — Бэкенд: аутентификация

- [ ] `POST /auth/register` — валидация Zod + хэш пароля `bcrypt`
- [ ] `POST /auth/login` — выдача access + refresh JWT (`@fastify/jwt`)
- [ ] `POST /auth/refresh` — верификация refresh token, выдача нового access token
- [ ] `POST /auth/logout` — инвалидация refresh token (запись в blacklist или удаление из БД)
- [ ] `authenticate` preHandler-хук — проверка Bearer токена для защищённых роутов
- [ ] Zod-схемы запроса/ответа для всех auth-эндпоинтов

### Этап 3 — Бэкенд: CRUD рецептов

- [ ] `GET /recipes` — список с пагинацией и фильтрами (`q`, `category`, `tags`, `difficulty`, `max_time`)
- [ ] `POST /recipes` — создание рецепта (Zod-валидация body)
- [ ] `GET /recipes/:id` — полные данные рецепта (Prisma `include`: steps, ingredients, tags)
- [ ] `PUT /recipes/:id` — обновление (проверка авторства)
- [ ] `DELETE /recipes/:id` — удаление (проверка авторства)
- [ ] `POST /recipes/:id/publish` — публикация
- [ ] Обработка ошибок: 404, 403 через Fastify error handler

### Этап 4 — Бэкенд: шаги и медиа

- [ ] CRUD шагов (`GET/POST/PUT/DELETE /recipes/:id/steps`)
- [ ] `PATCH /recipes/:id/steps/reorder` — атомарное обновление `sortOrder` через `prisma.$transaction`
- [ ] `lib/s3.ts` — обёртка `PutObjectCommand` / `DeleteObjectCommand` (`@aws-sdk/client-s3`)
- [ ] `lib/image.ts` — `sharp`: валидация mime, ресайз, конвертация в JPEG
- [ ] `POST /upload/image` — приём `multipart/form-data`, обработка `sharp`, загрузка в S3
- [ ] CRUD фотографий шагов (`POST/DELETE /steps/:stepId/photos`)
- [ ] `PATCH /steps/:stepId/photos/reorder`

### Этап 5 — Бэкенд: категории, теги, тесты

- [ ] `GET /categories`, `POST /categories` (admin-guard)
- [ ] `GET /tags` (с поиском по `q`)
- [ ] Настройка Vitest + supertest для интеграционных тестов
- [ ] Тесты: auth flow, CRUD рецептов, загрузка изображений (mock S3)
- [ ] CI: GitHub Actions — `tsc --noEmit` + ESLint + `vitest run` при push

### Этап 6 — iOS: базовая структура

- [d] Создание Xcode-проекта (SwiftUI, iOS 17+)
- [d] Структура папок (Core / Features / Shared / Resources)
- [d] `APIClient` — базовый сетевой слой (URLSession + async/await)
- [d] `Endpoint` enum — все эндпоинты
- [d] Доменные модели (Recipe, Step, Ingredient …) + декодирование
- [d] Глобальный `ErrorBanner` модификатор

### Этап 7 — iOS: аутентификация

- [d] `LoginView` + `RegisterView`
- [d] `AuthViewModel` — login/register/logout
- [d] Хранение токенов в Keychain
- [d] Автоматическое обновление access token (interceptor)
- [d] Защищённый роутинг: переход на главную после логина

### Этап 8 — iOS: список и детали рецепта

- [d] `RecipeListView` — сетка карточек (LazyVGrid, 2/3/4 колонки)
- [d] `RecipeCardView` — компонент карточки с обложкой, названием, мета
- [d] Поиск (searchable + debounce)
- [d] Фильтр-шторка (категория, сложность, время)
- [d] Чипы активных фильтров
- [d] Пагинация (infinity scroll)
- [d] Pull-to-refresh
- [d] `RecipeDetailView` — hero-фото, мета, ингредиенты, превью шагов
- [d] Масштабирование порций (×0.5/×1/×2/×3)
- [d] Кэширование изображений (NSCache + disk)

### Этап 9 — iOS: режим приготовления

- [d] `CookingSessionView` — полноэкранный пошаговый режим
- [d] Слайдер фотографий шага (TabView + PageTabViewStyle + pinch-to-zoom)
- [d] Прогресс-бар и навигация (кнопки + swipe-жест)
- [d] `TimerService` — обратный отсчёт, пауза, звуковой сигнал
- [d] Блокировка автоблокировки экрана
- [d] Экран завершения («Готово!» + анимация)

### Этап 10 — iOS: Hands-Free режим

- [d] Запрос разрешения камеры (Info.plist + runtime prompt)
- [d] `AVCaptureSession` + `VNDetectHumanHandPoseRequest`
- [d] Определение жеста «открытая ладонь + свайп» (по дельте запястья)
- [d] Жест «сжатый кулак» (удержание 1 сек)
- [d] Жест «два пальца V»
- [d] Оверлей с индикацией распознанного жеста
- [d] Задержка между срабатываниями 1.5 сек
- [d] Настройка чувствительности в SettingsView
- [d] Автоотключение при сворачивании приложения

### Этап 11 — iOS: редактор рецептов

- [d] `RecipeEditorView` — форма основной информации
- [d] PhotosPicker: обложка рецепта (crop 16:9)
- [d] Список ингредиентов (добавить / удалить / reorder)
- [d] Список шагов с `StepEditorView` (drag-to-reorder)
- [d] `StepEditorView`: заголовок, описание, фото (до 5 шт), таймер
- [d] Автосохранение черновика в SwiftData каждые 30 сек
- [d] Валидация и публикация
- [d] Предупреждение при выходе с несохранёнными изменениями

### Этап 12 — iOS: настройки, категории, офлайн

- [y] `SettingsView` — адрес сервера, руки-free настройки, аккаунт
- [y] `CategoryView` — список рецептов по категории
- [y] Offline-режим: кэш просмотренных рецептов в SwiftData
- [y] Обработка `noConnection` — показ кэша + banner

### Этап 13 — Финализация и полировка

- [y] Локализация: RU + EN (Localizable.strings)
- [y] Адаптация лейаутов для iPad (landscape + portrait)
- [y] Dark Mode поддержка
- [y] Accessibility (VoiceOver labels, Dynamic Type)
- [y] App Icon и Launch Screen
- [y] Тестфлайт-сборка + smoke-test на реальном устройстве
- [y] Финальный ревью безопасности (Keychain, HTTPS, camera privacy)

---

## 6. MVP vs. будущие фичи

### MVP (этапы 1–13)
- [y] CRUD рецептов со шагами и фотографиями
- [y] Авторизация
- [y] Hands-free жесты (следующий/предыдущий шаг)
- [y] Поиск и фильтрация
- [y] Таймер на шаге

### После MVP
- [y] Голосовые команды (Speech framework)
- [x] Синхронизация между устройствами (iCloud / server sync)
- [x] Комментарии и оценки рецептов
- [ ] Планировщик меню на неделю
- [ ] Импорт рецептов с веб-сайтов
- [ ] Масштабирование ингредиентов под количество порций
- [ ] Шеринг рецептов (deeplink)
