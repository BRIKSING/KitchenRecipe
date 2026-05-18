import SwiftUI

// MARK: - RecipeListView

struct RecipeListView: View {
    @StateObject private var viewModel = RecipeViewModel()
    @State private var query = RecipesQuery()
    @State private var searchText = ""
    @State private var showFilterSheet = false
    @State private var showEditor = false
    @State private var searchDebounceTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.recipes.isEmpty {
                    skeletonGrid
                } else if viewModel.error != nil && viewModel.recipes.isEmpty {
                    errorState
                } else if viewModel.recipes.isEmpty {
                    ContentUnavailableView(
                        "Рецепты не найдены",
                        systemImage: "fork.knife",
                        description: Text("Попробуйте изменить фильтры или поисковый запрос")
                    )
                } else {
                    recipeGrid
                }
            }
            .navigationTitle("Рецепты")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                            .bold()
                    }
                    .tint(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilterSheet = true
                    } label: {
                        Image(systemName: hasActiveFilters
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                        .foregroundStyle(hasActiveFilters ? .orange : .primary)
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                RecipeEditorView()
            }
            .searchable(text: $searchText, prompt: "Поиск рецептов")
            .onChange(of: searchText) { _, newValue in
                scheduleSearch(newValue)
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheetView(query: $query, categories: viewModel.categories) {
                    showFilterSheet = false
                    Task { await viewModel.loadRecipes(query: query, reset: true) }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                RecipeDetailView(recipeId: id)
            }
        }
        .task {
            await viewModel.loadCategories()
            await viewModel.loadRecipes(query: query, reset: true)
        }
    }

    // MARK: - Active filters

    private var hasActiveFilters: Bool {
        query.category != nil || query.difficulty != nil || query.maxTime != nil
    }

    @ViewBuilder
    private var filterChips: some View {
        if hasActiveFilters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let difficulty = query.difficulty {
                        FilterChip(label: difficulty.localizedName) {
                            query.difficulty = nil
                            Task { await viewModel.loadRecipes(query: query, reset: true) }
                        }
                    }
                    if let maxTime = query.maxTime {
                        FilterChip(label: "До \(maxTime) мин") {
                            query.maxTime = nil
                            Task { await viewModel.loadRecipes(query: query, reset: true) }
                        }
                    }
                    if query.category != nil {
                        let name = viewModel.categories.first(where: { $0.id == query.category })?.name ?? "Категория"
                        FilterChip(label: name) {
                            query.category = nil
                            Task { await viewModel.loadRecipes(query: query, reset: true) }
                        }
                    }
                    Button("Сбросить всё") {
                        query.category = nil
                        query.difficulty = nil
                        query.maxTime = nil
                        Task { await viewModel.loadRecipes(query: query, reset: true) }
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Recipe grid

    private var recipeGrid: some View {
        ScrollView {
            filterChips
            LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                ForEach(viewModel.recipes) { recipe in
                    NavigationLink(value: recipe.id) {
                        RecipeCardView(recipe: recipe)
                    }
                    .buttonStyle(.plain)
                    .task {
                        if recipe.id == viewModel.recipes.last?.id {
                            await viewModel.loadRecipes(query: query)
                        }
                    }
                }
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.loadRecipes(query: query, reset: true)
        }
    }

    // MARK: - Skeleton grid

    private var skeletonGrid: some View {
        ScrollView {
            LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonCardView()
                }
            }
            .padding()
        }
    }

    // MARK: - Error state

    private var errorState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Не удалось загрузить рецепты")
                .font(.headline)
            Button("Повторить") {
                Task { await viewModel.loadRecipes(query: query, reset: true) }
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)]
    }

    private func scheduleSearch(_ text: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            query.q = text.isEmpty ? nil : text
            await viewModel.loadRecipes(query: query, reset: true)
        }
    }
}

// MARK: - RecipeCardView

struct RecipeCardView: View {
    let recipe: RecipeListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CachedAsyncImage(url: recipe.coverImageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle()
                    .foregroundStyle(.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(height: 120)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Label(recipe.cookTimeMin.formattedDuration, systemImage: "clock")
                    Label(recipe.difficulty.localizedName, systemImage: "chart.bar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !recipe.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(recipe.tags.prefix(3)) { tag in
                                Text(tag.name)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.12))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

// MARK: - FilterChip

struct FilterChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.orange.opacity(0.12))
        .foregroundStyle(.orange)
        .clipShape(Capsule())
    }
}

// MARK: - SkeletonCardView

struct SkeletonCardView: View {
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .frame(height: 120)
                .foregroundStyle(.secondary.opacity(shimmer ? 0.12 : 0.25))
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .frame(height: 12)
                    .foregroundStyle(.secondary.opacity(shimmer ? 0.12 : 0.25))
                RoundedRectangle(cornerRadius: 4)
                    .frame(width: 90, height: 10)
                    .foregroundStyle(.secondary.opacity(shimmer ? 0.12 : 0.25))
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }
}

// MARK: - FilterSheetView

struct FilterSheetView: View {
    @Binding var query: RecipesQuery
    let categories: [RecipeCategory]
    let onApply: () -> Void

    @State private var selectedCategory: UUID?
    @State private var selectedDifficulty: Difficulty?
    @State private var maxTime: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section("Категория") {
                    Picker("Категория", selection: $selectedCategory) {
                        Text("Любая").tag(Optional<UUID>.none)
                        ForEach(categories) { cat in
                            Text(cat.name).tag(Optional(cat.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Сложность") {
                    Picker("Сложность", selection: $selectedDifficulty) {
                        Text("Любая").tag(Optional<Difficulty>.none)
                        ForEach(Difficulty.allCases, id: \.self) { d in
                            Text(d.localizedName).tag(Optional(d))
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Максимальное время") {
                    HStack {
                        Text(maxTime.map { "До \($0) мин" } ?? "Не ограничено")
                            .foregroundStyle(maxTime == nil ? .secondary : .primary)
                        Spacer()
                        Stepper(
                            "",
                            value: Binding(get: { maxTime ?? 60 }, set: { maxTime = $0 }),
                            in: 5...300,
                            step: 5
                        )
                        .labelsHidden()
                    }
                    if maxTime != nil {
                        Button("Сбросить") { maxTime = nil }
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { onApply() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Применить") {
                        query.category = selectedCategory
                        query.difficulty = selectedDifficulty
                        query.maxTime = maxTime
                        onApply()
                    }
                    .bold()
                    .tint(.orange)
                }
            }
        }
        .onAppear {
            selectedCategory = query.category
            selectedDifficulty = query.difficulty
            maxTime = query.maxTime
        }
    }
}
