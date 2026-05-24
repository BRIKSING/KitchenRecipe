import SwiftUI
import SwiftData

// MARK: - FavoritesView

struct FavoritesView: View {
    @EnvironmentObject private var syncService: iCloudSyncService

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteRecipe.addedAt, order: .reverse)
    private var favorites: [FavoriteRecipe]

    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    emptyStateView
                } else {
                    favoriteList
                }
            }
            .navigationTitle(NSLocalizedString("favorites.title", value: "Избранное", comment: ""))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    iCloudStatusButton
                }
            }
            .task {
                reconcileWithCloud()
            }
            .refreshable {
                syncService.syncNow()
                reconcileWithCloud()
            }
        }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(NSLocalizedString("favorites.empty.title", value: "Нет избранных рецептов", comment: ""))
                .font(.title3.bold())

            Text(NSLocalizedString("favorites.empty.subtitle",
                                   value: "Нажмите ♥ на странице рецепта,\nчтобы добавить его в избранное",
                                   comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if case .unavailable = syncService.status {
                iCloudUnavailableBanner
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iCloudUnavailableBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "icloud.slash")
            Text(NSLocalizedString("icloud.unavailable.hint",
                                   value: "Войдите в iCloud для синхронизации между устройствами",
                                   comment: ""))
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }

    // MARK: - Favorites list

    private var favoriteList: some View {
        List {
            if case .unavailable = syncService.status {
                Section {
                    Label(
                        NSLocalizedString("icloud.unavailable.hint",
                                          value: "Войдите в iCloud для синхронизации между устройствами",
                                          comment: ""),
                        systemImage: "icloud.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            ForEach(favorites) { favorite in
                favoriteRow(for: favorite)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteFavorite(favorite)
                        } label: {
                            Label(NSLocalizedString("favorites.remove", value: "Удалить", comment: ""),
                                  systemImage: "heart.slash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .animation(.easeInOut, value: favorites.count)
    }

    @ViewBuilder
    private func favoriteRow(for favorite: FavoriteRecipe) -> some View {
        if let id = favorite.parsedID {
            NavigationLink(destination: RecipeDetailView(recipeId: id)) {
                FavoriteRowView(favorite: favorite)
            }
            .accessibilityLabel(
                favorite.needsRefresh
                    ? NSLocalizedString("favorites.loading", value: "Загружается...", comment: "")
                    : favorite.title
            )
        }
    }

    // MARK: - iCloud status button

    @ViewBuilder
    private var iCloudStatusButton: some View {
        switch syncService.status {
        case .syncing:
            ProgressView()
                .controlSize(.small)
                .tint(.orange)

        case .synced(let date):
            Image(systemName: "icloud.fill")
                .foregroundStyle(.green)
                .accessibilityLabel(String(
                    format: NSLocalizedString("icloud.synced.at",
                                             value: "Синхронизировано: %@",
                                             comment: ""),
                    date.formatted(date: .omitted, time: .shortened)
                ))

        case .unavailable:
            Image(systemName: "icloud.slash")
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    NSLocalizedString("icloud.unavailable", value: "iCloud недоступен", comment: "")
                )

        case .error:
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(.red)
                .onTapGesture { syncService.syncNow() }
                .accessibilityLabel(
                    NSLocalizedString("icloud.error", value: "Ошибка синхронизации. Нажмите для повтора", comment: "")
                )

        case .idle:
            Button {
                syncService.syncNow()
                reconcileWithCloud()
            } label: {
                Image(systemName: "icloud")
                    .foregroundStyle(.orange)
            }
            .accessibilityLabel(
                NSLocalizedString("icloud.sync.now", value: "Синхронизировать с iCloud", comment: "")
            )
        }
    }

    // MARK: - Cloud reconciliation

    /// Сверяет локальные FavoriteRecipe с набором ID из iCloud.
    /// • ID есть в iCloud, нет в SwiftData → создаём placeholder
    /// • ID есть в SwiftData, нет в iCloud → удаляем
    private func reconcileWithCloud() {
        guard syncService.isAvailable else { return }

        let cloudIDs = syncService.favoriteIDs
        let localIDStrings = Set(favorites.map { $0.recipeId })
        let localIDs = Set(favorites.compactMap { UUID(uuidString: $0.recipeId) })

        // Удаляем локальные, которые исчезли из iCloud (удалены на другом устройстве)
        for favorite in favorites {
            guard let id = favorite.parsedID else { continue }
            if !cloudIDs.contains(id) {
                modelContext.delete(favorite)
            }
        }

        // Создаём placeholder-записи для ID, которые пришли из iCloud
        for cloudID in cloudIDs where !localIDs.contains(cloudID) {
            let placeholder = FavoriteRecipe(placeholder: cloudID)
            modelContext.insert(placeholder)
        }

        try? modelContext.save()
    }

    // MARK: - Actions

    private func deleteFavorite(_ favorite: FavoriteRecipe) {
        if let id = favorite.parsedID {
            syncService.removeFavorite(id: id)
        }
        modelContext.delete(favorite)
        try? modelContext.save()
    }
}

// MARK: - FavoriteRowView

struct FavoriteRowView: View {
    let favorite: FavoriteRecipe

    var body: some View {
        HStack(spacing: 14) {
            // Обложка
            CachedAsyncImage(url: favorite.coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle()
                    .foregroundStyle(.secondary.opacity(0.15))
                    .overlay {
                        Image(systemName: favorite.needsRefresh
                              ? "arrow.triangle.2.circlepath"
                              : "photo")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 20))
                    }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .animation(.easeInOut, value: favorite.coverURL)

            // Текстовые данные
            VStack(alignment: .leading, spacing: 5) {
                if favorite.needsRefresh {
                    Text(NSLocalizedString("favorites.loading", value: "Загружается...", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(favorite.title)
                        .font(.subheadline.bold())
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Label(favorite.cookTimeMin.formattedDuration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let cat = favorite.categoryName {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(cat)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    // Сложность
                    Text(favorite.difficultyEnum.localizedName)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(difficultyColor(favorite.difficultyEnum).opacity(0.12))
                        .foregroundStyle(difficultyColor(favorite.difficultyEnum))
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "heart.fill")
                .foregroundStyle(.red.opacity(0.7))
                .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func difficultyColor(_ d: Difficulty) -> Color {
        switch d {
        case .easy:   return .green
        case .medium: return .orange
        case .hard:   return .red
        }
    }
}
