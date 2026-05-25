import Foundation
import Combine

// MARK: - ICloudSyncStatus

/// Describes the current state of iCloud preferences synchronisation.
enum ICloudSyncStatus: Equatable {
    /// The user is not signed into iCloud on this device.
    case unavailable
    /// The user has disabled preferences sync in Settings.
    case disabled
    /// A sync operation is in progress.
    case syncing
    /// Last successful sync completed at the given date.
    case synced(Date)
    /// The last sync attempt failed with the given message.
    case error(String)

    static func == (lhs: ICloudSyncStatus, rhs: ICloudSyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.unavailable, .unavailable),
             (.disabled, .disabled),
             (.syncing, .syncing):
            return true
        case (.synced(let a), .synced(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .unavailable:
            return NSLocalizedString(
                "icloud.status.unavailable",
                value: "iCloud недоступен — войдите в Apple ID в настройках iOS",
                comment: "iCloud not signed in"
            )
        case .disabled:
            return NSLocalizedString(
                "icloud.status.disabled",
                value: "Синхронизация отключена",
                comment: "iCloud sync disabled"
            )
        case .syncing:
            return NSLocalizedString(
                "icloud.status.syncing",
                value: "Синхронизация…",
                comment: "iCloud sync in progress"
            )
        case .synced(let date):
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .short
            return String(
                format: NSLocalizedString(
                    "icloud.status.synced",
                    value: "Синхронизировано %@",
                    comment: "iCloud sync success, %@ = relative time"
                ),
                fmt.localizedString(for: date, relativeTo: Date())
            )
        case .error(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .unavailable:   return "icloud.slash"
        case .disabled:      return "icloud"
        case .syncing:       return "arrow.triangle.2.circlepath.icloud"
        case .synced:        return "checkmark.icloud"
        case .error:         return "exclamationmark.icloud"
        }
    }
}

// MARK: - ICloudSyncService

/// Manages iCloud synchronisation of user preferences via `NSUbiquitousKeyValueStore`.
///
/// Draft recipes are automatically synced across devices via the CloudKit-backed
/// SwiftData `ModelContainer` configured in `KitchenRecipeApp` — no extra work
/// required here for that layer.
///
/// Preferences are mirrored to the user's private iCloud key-value store so that
/// settings like server URL, gesture sensitivity and language carry over to other
/// devices immediately.
@MainActor
final class ICloudSyncService: ObservableObject {

    // MARK: - Singleton

    static let shared = ICloudSyncService()

    // MARK: - Published state

    @Published private(set) var status: ICloudSyncStatus = .disabled

    /// Persisted toggle — when turned on, preferences are pushed/pulled via KVStore.
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: StorageKeys.syncEnabled)
            isEnabled ? startSync() : disableSync()
        }
    }

    // MARK: - Private constants

    private enum StorageKeys {
        static let syncEnabled  = "icloud.sync.enabled"
        static let lastSyncDate = "icloud.sync.lastDate"
    }

    /// The user-facing preference keys that are mirrored to iCloud.
    private let syncedPreferenceKeys: [String] = [
        "serverURL",
        "handsfree.enabledByDefault",
        "handsfree.swipeSensitivity",
        "handsfree.fistHoldDuration",
        "voice.enabledByDefault",
        "timer.sound",
        "timer.haptic",
        "app.language",
    ]

    // MARK: - Private state

    private let kvStore = NSUbiquitousKeyValueStore.default
    private var externalChangeObserver: NSObjectProtocol?

    // MARK: - Init

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: StorageKeys.syncEnabled)
        registerForExternalChanges()
        if isEnabled { startSync() }
    }

    // MARK: - Public interface

    /// `true` when the user is signed into iCloud on this device.
    var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Explicitly pushes local preferences to iCloud right now.
    func syncNow() {
        guard isEnabled else { return }
        guard isICloudAvailable else {
            status = .unavailable
            return
        }
        status = .syncing
        pushPreferences()
        let didSync = kvStore.synchronize()
        if didSync {
            recordSuccessfulSync()
        } else {
            status = .error(
                NSLocalizedString(
                    "icloud.error.failed",
                    value: "Не удалось выполнить синхронизацию",
                    comment: "iCloud sync failed"
                )
            )
        }
    }

    // MARK: - Private: lifecycle

    private func startSync() {
        guard isICloudAvailable else {
            status = .unavailable
            return
        }
        status = .syncing
        pushPreferences()
        kvStore.synchronize()
        recordSuccessfulSync()
    }

    private func disableSync() {
        status = .disabled
    }

    // MARK: - Private: external change handling

    private func registerForExternalChanges() {
        externalChangeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] notification in
            self?.handleExternalChange(notification)
        }
    }

    private func handleExternalChange(_ notification: Notification) {
        guard isEnabled else { return }

        let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int ?? -1
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            pullPreferences()
            recordSuccessfulSync()
            // Notify any view observing UserDefaults so UI refreshes automatically.
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)

        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            status = .error(
                NSLocalizedString(
                    "icloud.error.quota",
                    value: "Превышена квота iCloud",
                    comment: "iCloud KVStore quota exceeded"
                )
            )

        default:
            break
        }
    }

    // MARK: - Private: KVStore I/O

    private func pushPreferences() {
        let ud = UserDefaults.standard
        for key in syncedPreferenceKeys {
            if let value = ud.object(forKey: key) {
                kvStore.set(value, forKey: key)
            }
        }
    }

    private func pullPreferences() {
        let ud = UserDefaults.standard
        for key in syncedPreferenceKeys {
            if let value = kvStore.object(forKey: key) {
                ud.set(value, forKey: key)
            }
        }
    }

    // MARK: - Private: helpers

    private func recordSuccessfulSync() {
        let now = Date()
        UserDefaults.standard.set(now, forKey: StorageKeys.lastSyncDate)
        status = .synced(now)
    }
}
