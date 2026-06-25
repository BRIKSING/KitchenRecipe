import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    let recipeId: UUID

    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = RecipeViewModel()
    @State private var recipe: Recipe?
    @State private var isDescriptionExpanded = false
    @State private var servingsMultiplier: Double = 1.0
    @State private var startCooking = false
    @State private var isOfflineMode = false
    @State private var showRateSheet = false

    @StateObject private var commentsVM = CommentsViewModel()

    private let multipliers: [(label: String, value: Double)] = [
        ("×½", 0.5), ("×1", 1.0), ("×2", 2.0), ("×3", 3.0)
    ]

    var body: some View {
        Group {
            if let recipe {
                recipeContent(recipe)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRecipe() }
        .sheet(isPresented: $showRateSheet) {
            if let recipe {
                RateRecipeSheet(recipeId: recipe.id, recipeTitle: recipe.title) {
                    Task { await commentsVM.loadInitial(recipeId: recipe.id) }
                }
            }
        }
        .fullScreenCover(isPresented: $startCooking) {
            if let recipe {
                CookingSessionView(recipe: recipe)
            }
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private func recipeContent(_ recipe: Recipe) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    heroSection(recipe)
                    metaSection(recipe)
                    if !recipe.tags.isEmpty { tagsSection(recipe) }
                    if let desc = recipe.description, !desc.isEmpty {
                        descriptionSection(desc)
                    }
                    ingredientsSection(recipe)
                    stepsSection(recipe)
                    ratingSummarySection(recipe)
                    commentsPreviewSection(recipe)
                    Spacer().frame(height: 90)
                }
            }
            .coordinateSpace(name: "scroll")
            .ignoresSafeArea(edges: .top)

            startCookingButton
        }
        .navigationTitle(recipe.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: shareText(for: recipe),
                    subject: Text(recipe.title),
                    message: Text(recipe.description ?? "")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .tint(.orange)
            }
        }
        .safeAreaInset(edge: .top) {
            if isOfflineMode {
                offlineBanner
            }
        }
    }

    private func shareText(for recipe: Recipe) -> String {
        var parts: [String] = [recipe.title]
        if let desc = recipe.description, !desc.isEmpty {
            parts.append(desc)
        }
        parts.append("kitchenrecipe://recipe/\(recipe.id.uuidString)")
        return parts.joined(separator: "\n\n")
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Офлайн — кэшированные данные")
                .font(.caption.bold())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.orange.gradient)
    }

    // MARK: - Hero with parallax

    private func heroSection(_ recipe: Recipe) -> some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named("scroll")).minY
            let heroHeight: CGFloat = 280
            let extraOffset = max(0, minY)

            CachedAsyncImage(url: recipe.coverImageURL) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .offset(y: minY > 0 ? -minY * 0.4 : 0)
            } placeholder: {
                Rectangle()
                    .foregroundStyle(.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: geo.size.width, height: heroHeight + extraOffset)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    if let cat = recipe.category {
                        Text(cat.name.uppercased())
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Text(recipe.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .frame(height: 280)
    }

    // MARK: - Meta block

    private func metaSection(_ recipe: Recipe) -> some View {
        HStack(spacing: 0) {
            metaItem(
                icon: "clock",
                value: recipe.cookTimeMin.formattedDuration,
                label: "Время"
            )
            Divider().frame(height: 36)
            metaItem(
                icon: "person.2",
                value: "\(scaledServings(recipe.servings))",
                label: "Порции"
            )
            Divider().frame(height: 36)
            metaItem(
                icon: "chart.bar",
                value: recipe.difficulty.localizedName,
                label: "Сложность"
            )
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
    }

    private func metaItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .font(.system(size: 18))
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Tags

    private func tagsSection(_ recipe: Recipe) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recipe.tags) { tag in
                    Text("#\(tag.name)")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Description (expandable)

    private func descriptionSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(isDescriptionExpanded ? nil : 3)
                .animation(.easeInOut(duration: 0.2), value: isDescriptionExpanded)

            Button(isDescriptionExpanded ? "Свернуть" : "Читать далее") {
                isDescriptionExpanded.toggle()
            }
            .font(.subheadline.bold())
            .foregroundStyle(.orange)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Ingredients with portion scaling

    private func ingredientsSection(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Ингредиенты")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(multipliers, id: \.label) { item in
                        Button(item.label) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                servingsMultiplier = item.value
                            }
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            servingsMultiplier == item.value
                            ? Color.orange
                            : Color(.tertiarySystemBackground)
                        )
                        .foregroundStyle(servingsMultiplier == item.value ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .animation(.easeInOut(duration: 0.15), value: servingsMultiplier)
                    }
                }
            }

            Divider()

            ForEach(recipe.ingredients.sorted(by: { $0.sortOrder < $1.sortOrder })) { ingredient in
                VStack(spacing: 0) {
                    HStack {
                        Text(ingredient.name)
                            .font(.subheadline)
                        Spacer()
                        Text(scaledAmount(ingredient))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.2), value: servingsMultiplier)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
        .padding()
    }

    // MARK: - Steps preview

    private func stepsSection(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Шаги приготовления")
                .font(.headline)

            ForEach(recipe.steps.sorted(by: { $0.sortOrder < $1.sortOrder })) { step in
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 34, height: 34)
                            Text("\(step.sortOrder)")
                                .font(.subheadline.bold())
                                .foregroundStyle(.orange)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.subheadline.bold())
                                .lineLimit(2)
                            if let timerSec = step.timerSec {
                                Label(timerSec.formattedTimer, systemImage: "timer")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let firstPhoto = step.photos.min(by: { $0.sortOrder < $1.sortOrder }) {
                            CachedAsyncImage(url: firstPhoto.url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().foregroundStyle(.secondary.opacity(0.2))
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
        .padding()
    }

    // MARK: - Rating summary

    private func ratingSummarySection(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(NSLocalizedString("comments.ratings_header", value: "Оценки", comment: ""))
                    .font(.headline)
                Spacer()
                Button {
                    showRateSheet = true
                } label: {
                    Label(
                        NSLocalizedString("comments.rate_btn", value: "Оценить", comment: ""),
                        systemImage: "star"
                    )
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                }
            }

            Divider()

            if let stats = commentsVM.ratingStats, stats.count > 0 {
                HStack(spacing: 14) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", stats.average))
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.orange)
                        Text(NSLocalizedString("comments.out_of_5", value: "из 5", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        StarRatingView(rating: stats.average, starSize: 20)
                        Text(String(format: NSLocalizedString("comments.ratings_count", value: "%d оценок", comment: ""), stats.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else {
                Text(NSLocalizedString("comments.no_ratings_yet", value: "Оценок пока нет. Попробуйте первым!", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .task { await commentsVM.loadRatingStats(recipeId: recipe.id) }
    }

    // MARK: - Comments preview

    private func commentsPreviewSection(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(NSLocalizedString("comments.title", value: "Отзывы", comment: ""))
                    .font(.headline)
                if !commentsVM.comments.isEmpty {
                    Text("(\(commentsVM.comments.count))")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink {
                    RecipeCommentsView(recipeId: recipe.id, recipeTitle: recipe.title)
                } label: {
                    Text(NSLocalizedString("comments.show_all", value: "Все", comment: ""))
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            if commentsVM.comments.isEmpty {
                Text(NSLocalizedString("comments.empty_title", value: "Пока нет отзывов", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Показываем не более 2-х последних комментариев
                ForEach(commentsVM.comments.prefix(2)) { comment in
                    commentPreviewRow(comment)
                }
            }
        }
        .padding()
        .task { await commentsVM.loadInitial(recipeId: recipe.id) }
    }

    private func commentPreviewRow(_ comment: Comment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Avatar
                Circle()
                    .fill(avatarColor(for: comment.author.username))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(String(comment.author.username.prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(comment.author.username)
                        .font(.subheadline.bold())
                    Text(comment.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let rating = comment.rating {
                    StarRatingView(rating: Double(rating), starSize: 13)
                }
            }
            Text(comment.text)
                .font(.subheadline)
                .lineLimit(3)
                .foregroundStyle(.primary)
            Divider()
        }
    }

    private func avatarColor(for username: String) -> Color {
        let colors: [Color] = [.orange, .blue, .green, .purple, .pink, .teal]
        let index = abs(username.hashValue) % colors.count
        return colors[index]
    }

    // MARK: - Sticky "Start cooking" button

    private var startCookingButton: some View {
        Button {
            startCooking = true
        } label: {
            Text("Начать приготовление")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
        .accessibilityHint("Открывает пошаговый режим приготовления")
    }

    // MARK: - Offline cache

    private func loadRecipe() async {
        do {
            let r = try await viewModel.loadDetail(id: recipeId)
            recipe = r
            isOfflineMode = false
            cacheRecipe(r)
        } catch NetworkError.noConnection {
            if let cached = loadCachedRecipe() {
                recipe = cached
                isOfflineMode = true
                ErrorBannerState.shared.show("Нет соединения — показаны кэшированные данные")
            }
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }

    private func cacheRecipe(_ r: Recipe) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(r) else { return }
        let idStr = r.id.uuidString
        let descriptor = FetchDescriptor<CachedRecipeDetail>(
            predicate: #Predicate { $0.recipeId == idStr }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.recipeData = data
            existing.cachedAt = Date()
        } else {
            modelContext.insert(CachedRecipeDetail(recipeId: r.id, recipeData: data, title: r.title))
        }
    }

    private func loadCachedRecipe() -> Recipe? {
        let idStr = recipeId.uuidString
        let descriptor = FetchDescriptor<CachedRecipeDetail>(
            predicate: #Predicate { $0.recipeId == idStr }
        )
        return try? modelContext.fetch(descriptor).first?.decode()
    }

    // MARK: - Helpers

    private func scaledServings(_ base: Int) -> Int {
        max(1, Int((Double(base) * servingsMultiplier).rounded()))
    }

    private func scaledAmount(_ ingredient: Ingredient) -> String {
        // amount/unit опциональны (бэкенд отдаёт их nullable).
        let unit = ingredient.unit.map { " \($0)" } ?? ""
        guard let amount = ingredient.amount else {
            return unit.trimmingCharacters(in: .whitespaces)
        }
        let scaled = amount * servingsMultiplier
        let display = scaled.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(scaled))
            : String(format: "%.1f", scaled)
        return "\(display)\(unit)"
    }
}
