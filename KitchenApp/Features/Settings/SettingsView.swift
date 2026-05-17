import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:3000"

    // Hands-Free settings
    @State private var handsfreeDefault = UserDefaults.standard.bool(forKey: "handsfree.enabledByDefault")
    @State private var swipeSensitivity = UserDefaults.standard.double(forKey: "handsfree.swipeSensitivity").nonzero(default: 0.04)
    @State private var fistHoldDuration = UserDefaults.standard.double(forKey: "handsfree.fistHoldDuration").nonzero(default: 1.0)
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                handsFreeSection
                accountSection
                aboutSection
            }
            .navigationTitle("Настройки")
        }
    }

    // MARK: - Sections

    private var serverSection: some View {
        Section("Сервер") {
            TextField("URL сервера", text: $serverURL)
                .autocapitalization(.none)
                .keyboardType(.URL)
                .onChange(of: serverURL) { _, new in
                    UserDefaults.standard.set(new, forKey: "serverURL")
                    if let url = URL(string: new) {
                        APIClient.shared.updateBaseURL(url)
                    }
                }
        }
    }

    private var handsFreeSection: some View {
        Section {
            // Camera permission status
            cameraPermissionRow

            Toggle("Включать по умолчанию", isOn: $handsfreeDefault)
                .onChange(of: handsfreeDefault) { _, new in
                    UserDefaults.standard.set(new, forKey: "handsfree.enabledByDefault")
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Чувствительность свайпа")
                    Spacer()
                    Text(sensitivityLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $swipeSensitivity, in: 0.02...0.10, step: 0.01)
                    .tint(.orange)
                    .onChange(of: swipeSensitivity) { _, new in
                        UserDefaults.standard.set(new, forKey: "handsfree.swipeSensitivity")
                    }
                Text("Меньше = реагирует на небольшое движение")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Удержание кулака")
                    Spacer()
                    Text(String(format: "%.1f с", fistHoldDuration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $fistHoldDuration, in: 0.5...2.0, step: 0.1)
                    .tint(.orange)
                    .onChange(of: fistHoldDuration) { _, new in
                        UserDefaults.standard.set(new, forKey: "handsfree.fistHoldDuration")
                    }
            }
        } header: {
            Text("Hands-Free (управление жестами)")
        } footer: {
            Text("Видеопоток обрабатывается только на устройстве и никогда не передаётся на сервер.")
        }
    }

    private var cameraPermissionRow: some View {
        HStack {
            Label("Доступ к камере", systemImage: "camera.fill")
            Spacer()
            switch cameraStatus {
            case .authorized:
                Text("Разрешён")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            case .denied, .restricted:
                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.orange)
            case .notDetermined:
                Button("Запросить") {
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        DispatchQueue.main.async {
                            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.orange)
            @unknown default:
                EmptyView()
            }
        }
    }

    private var accountSection: some View {
        Section("Аккаунт") {
            Button("Выйти", role: .destructive) {
                authVM.logout()
            }
        }
    }

    private var aboutSection: some View {
        Section("О приложении") {
            LabeledContent(
                "Версия",
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
            )
        }
    }

    // MARK: - Helpers

    private var sensitivityLabel: String {
        switch swipeSensitivity {
        case ..<0.03: return "Высокая"
        case 0.03..<0.06: return "Средняя"
        default: return "Низкая"
        }
    }
}

private extension Double {
    func nonzero(default value: Double) -> Double {
        self == 0 ? value : self
    }
}
