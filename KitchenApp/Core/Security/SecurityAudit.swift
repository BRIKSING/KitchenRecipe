import Foundation
import AVFoundation

// MARK: - SecurityAudit

/// Runs lightweight security assertions at app launch and documents the security posture.
///
/// Security posture summary:
///   • Auth tokens — Keychain, kSecAttrAccessibleWhenUnlockedThisDeviceOnly
///     (device-only, unreadable when locked, not migrated to iCloud / backups)
///   • Network — HTTPS enforced; HTTP triggers a runtime warning and a UI banner in SettingsView
///   • Camera — AVCaptureSession frames are consumed only by VNDetectHumanHandPoseRequest locally;
///     no raw video bytes are uploaded or persisted
///   • Passwords — sent to the server once during login/register; never cached locally
enum SecurityAudit {

    static func run() {
        checkServerURLScheme()
        checkCameraUsageDescription()
    }

    // MARK: - Checks

    /// Logs a warning when the persisted server URL uses plain HTTP for a non-local host.
    /// The UI counterpart (SettingsView) shows the same warning visually.
    private static func checkServerURLScheme() {
        let raw = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        guard let url = URL(string: raw) else { return }

        let isHTTP = url.scheme?.lowercased() == "http"
        let isLocal = url.host == "localhost" || url.host?.hasPrefix("127.") == true

        if isHTTP && !isLocal {
            // Not a fatal error — the server may be behind a TLS-terminating proxy —
            // but the operator should be aware.
            NSLog("[SecurityAudit] ⚠️ Server URL uses plain HTTP: %@. Switch to HTTPS.", raw)
        }
    }

    /// Asserts NSCameraUsageDescription is present so the OS can show the permission prompt.
    /// A missing key causes a crash on first camera access — better to catch it early.
    private static func checkCameraUsageDescription() {
        let hasKey = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
        assert(hasKey, "[SecurityAudit] NSCameraUsageDescription missing from Info.plist — camera access will crash at runtime.")
    }
}
