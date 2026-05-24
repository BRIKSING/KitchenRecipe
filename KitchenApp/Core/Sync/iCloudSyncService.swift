import Foundation
import Combine

// MARK: - iCloudSyncService
//
// Синхронизирует список избранных рецептов между устройствами пользователя
// через NSUbiquitousKeyValueStore (iCloud Key-Value Storage).
//
// Требования к проекту (Xcode → Signing & Capabilities → iCloud):
//   • Включить iCloud capability
//   • Включить "Key-value storage"
//   • Info.plist: NSUbiquitousKeyValueStoreUsage с описанием использования

final class iCloudSyncService: ObservableObject {

    // MARK: - Shared instance

    static let shared = iCloudSyncService()

    // MARK: - Sync status

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case synced(Date)
        case error(String)
        case unavailable   // iCloud не настроен / не выполнен вход
    }

    // MARK: - Published state

    @Published private(set) var status: SyncStatus = .idle
    @Published private(set) var favoriteIDs: Set<UUID> = []

    // MARK: - Private

    private let kvStore = NSUbiquitousKeyValueStore.default

    private enum KVKey {
        static let favorites = "kitchen.favorites.v1"
        static let settings  = "kitchen.settings.v1"
    }

    // MARK: - Init

    private init() {
        checkAvailability()
        guard case .unavailable = status else {
            loadFavoritesFromStore()
            kvStore.synchronize()
            startListeningForExternalChanges()
            return
        }
    }

    // MARK: - Availability

    var isAvailable: Bool {
        if case .unavailable = status { return false }
        return true
    }

    private func checkAvailability() {
        if FileManager.default.ubiquityIdentityToken == nil {
            status = .unavailable
        }
    }

    // MARK: - Favorites API

    func isFavorite(id: UUID) -> Bool {
        favoriteIDs.contains(id)
    }

    @discardableResult
    func toggleFavorite(id: UUID) -> Bool {
        if favoriteIDs.contains(id) {
            removeFavorite(id: id)
            return false
        } else {
            addFavorite(id: id)
            return true
        }
    }

    func addFavorite(id: UUID) {
        guard !favoriteIDs.contains(id) else { return }
        favoriteIDs.insert(id)
        pushFavoritesToCloud()
    }

    func removeFavorite(id: UUID) {
        guard favoriteIDs.contains(id) else { return }
        favoriteIDs.remove(id)
        pushFavoritesToCloud()
    }

    // MARK: - Settings sync

    /// Отправляет текущие пользовательские настройки в iCloud KV-хранилище.
    func pushSettings() {
        let ud = UserDefaults.standard
        let settingsKeys: [String] = [
            "handsfree.enabledByDefault",
            "handsfree.swipeSensitivity",
            "handsfree.fistHoldDuration",
            "voice.enabledByDefault",
            "timer.sound",
            "timer.haptic",
            "app.language"
        ]
        var dict: [String: Any] = [:]
        for key in settingsKeys {
            if let val = ud.object(forKey: key) {
                dict[key] = val
            }
        }
        kvStore.set(dict, forKey: KVKey.settings)
        kvStore.synchronize()
    }

    /// Применяет настройки из iCloud на это устройство (только если ключ ещё не задан локально).
    func pullSettings() {
        guard let cloud = kvStore.dictionary(forKey: KVKey.settings) else { return }
        let ud = UserDefaults.standard
        for (key, value) in cloud where ud.object(forKey: key) == nil {
            ud.set(value, forKey: key)
        }
    }

    // MARK: - Manual sync

    /// Запрашивает немедленную синхронизацию с iCloud и обновляет локальное состояние.
    func syncNow() {
        guard isAvailable else { return }
        status = .syncing
        kvStore.synchronize()
        loadFavoritesFromStore()
        status = .synced(Date())
    }

    // MARK: - Private helpers

    private func startListeningForExternalChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore
        )
    }

    @objc private func handleExternalChange(_ notification: Notification) {
        guard
            let reasonRaw = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
        else { return }

        // Обрабатываем только значимые причины изменений
        let relevantReasons = [
            NSUbiquitousKeyValueStoreServerChange,
            NSUbiquitousKeyValueStoreInitialSyncChange,
            NSUbiquitousKeyValueStoreAccountChange
        ]
        guard relevantReasons.contains(reasonRaw) else { return }

        // Уведомление приходит на главном потоке (по документации Apple)
        loadFavoritesFromStore()
        status = .synced(Date())
    }

    private func loadFavoritesFromStore() {
        guard let array = kvStore.array(forKey: KVKey.favorites) as? [String] else { return }
        favoriteIDs = Set(array.compactMap { UUID(uuidString: $0) })
    }

    private func pushFavoritesToCloud() {
        status = .syncing
        let uuidStrings = Array(favoriteIDs).map { $0.uuidString }
        kvStore.set(uuidStrings, forKey: KVKey.favorites)
        let didSync = kvStore.synchronize()
        status = didSync ? .synced(Date()) : .error("Ошибка синхронизации с iCloud")
    }
}
