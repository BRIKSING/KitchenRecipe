import Foundation
import CloudKit
import Observation

// MARK: - SyncStatus

enum SyncStatus: Equatable {
    case unknown
    case syncing
    case synced
    case error(String)
    case disabled
    case accountNotAvailable

    var systemImageName: String {
        switch self {
        case .unknown:             return "icloud"
        case .syncing:             return "arrow.triangle.2.circlepath.icloud"
        case .synced:              return "checkmark.icloud.fill"
        case .error:               return "exclamationmark.icloud.fill"
        case .disabled:            return "icloud.slash"
        case .accountNotAvailable: return "person.icloud"
        }
    }

    var localizedDescription: String {
        switch self {
        case .unknown:
            return NSLocalizedString("sync.status.unknown",     value: "Проверка...",            comment: "")
        case .syncing:
            return NSLocalizedString("sync.status.syncing",     value: "Синхронизация...",       comment: "")
        case .synced:
            return NSLocalizedString("sync.status.synced",      value: "Синхронизировано",       comment: "")
        case .error(let msg):
            let fmt = NSLocalizedString("sync.status.error",    value: "Ошибка: %@",             comment: "")
            return String(format: fmt, msg)
        case .disabled:
            return NSLocalizedString("sync.status.disabled",    value: "Отключено",              comment: "")
        case .accountNotAvailable:
            return NSLocalizedString("sync.status.no_account",  value: "Войдите в iCloud",       comment: "")
        }
    }
}

// MARK: - CloudKitSyncService

/// Manages iCloud sync state and preferences.
///
/// SwiftData CloudKit integration is configured at app launch based on
/// `isSyncEnabled`. Toggling the setting while the app is running shows
/// a "restart required" hint and takes effect on next cold launch.
@Observable
final class CloudKitSyncService {

    // MARK: - Singleton

    static let shared = CloudKitSyncService()

    // MARK: - Public state (read-only outside this class)

    private(set) var status: SyncStatus = .disabled
    private(set) var lastSyncDate: Date?

    /// Whether iCloud sync is currently turned ON in the user's preferences.
    private(set) var isSyncEnabled: Bool

    /// True when the toggle was changed after launch and a restart is needed
    /// for the new setting to take effect on the SwiftData container.
    private(set) var requiresRestartToBecomeActive: Bool = false

    // MARK: - Keys

    private static let enabledKey           = "sync.iCloudEnabled"
    private static let lastSyncKey          = "sync.lastDate"
    private static let launchEnabledKey     = "sync.wasEnabledAtLaunch"

    // MARK: - CloudKit container

    private let ckContainer = CKContainer.default()

    // MARK: - Init

    private init() {
        self.isSyncEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        self.lastSyncDate  = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date

        // Compare current preference vs what was active when the app launched
        let launchEnabled = UserDefaults.standard.bool(forKey: Self.launchEnabledKey)
        self.requiresRestartToBecomeActive = isSyncEnabled != launchEnabled

        if isSyncEnabled {
            Task { await checkAccountStatus() }
        } else {
            status = .disabled
        }
    }

    // MARK: - Public API

    /// Toggle iCloud sync on or off.
    /// The model container cannot be hot-swapped; a restart is required.
    func setEnabled(_ enabled: Bool) {
        isSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)

        let launchEnabled = UserDefaults.standard.bool(forKey: Self.launchEnabledKey)
        requiresRestartToBecomeActive = enabled != launchEnabled

        if enabled {
            Task { await checkAccountStatus() }
        } else {
            status = .disabled
        }
    }

    /// Refresh iCloud account status from CloudKit.
    @MainActor
    func checkAccountStatus() async {
        guard isSyncEnabled else {
            status = .disabled
            return
        }
        status = .syncing
        do {
            let accountStatus = try await ckContainer.accountStatus()
            switch accountStatus {
            case .available:
                status        = .synced
                lastSyncDate  = Date()
                UserDefaults.standard.set(lastSyncDate, forKey: Self.lastSyncKey)

            case .noAccount:
                status = .accountNotAvailable

            case .restricted:
                status = .error(
                    NSLocalizedString("sync.error.restricted",  value: "iCloud ограничен на устройстве", comment: ""))

            case .couldNotDetermine:
                status = .error(
                    NSLocalizedString("sync.error.indeterminate", value: "Не удалось определить статус", comment: ""))

            case .temporarilyUnavailable:
                status = .error(
                    NSLocalizedString("sync.error.unavailable", value: "Временно недоступен", comment: ""))

            @unknown default:
                status = .error(
                    NSLocalizedString("sync.error.unknown",     value: "Неизвестная ошибка", comment: ""))
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - App-launch helper

    /// Call **once** at app startup (before creating the SwiftData container).
    /// Records the current preference as the "launch state" so the restart
    /// indicator stays accurate, and returns whether CloudKit should be used.
    @discardableResult
    static func configureLaunchSync() -> Bool {
        let enabled = UserDefaults.standard.bool(forKey: enabledKey)
        UserDefaults.standard.set(enabled, forKey: launchEnabledKey)
        return enabled
    }
}
