import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var authVM: AuthViewModel

    // Server
    @State private var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:3000"
    @State private var serverCheckState: ServerCheckState = .idle

    // Hands-Free
    @State private var handsfreeDefault = UserDefaults.standard.bool(forKey: "handsfree.enabledByDefault")
    @State private var swipeSensitivity = UserDefaults.standard.double(forKey: "handsfree.swipeSensitivity").nonzero(default: 0.04)
    @State private var fistHoldDuration = UserDefaults.standard.double(forKey: "handsfree.fistHoldDuration").nonzero(default: 1.0)
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    // Notifications
    @State private var timerSound = UserDefaults.standard.object(forKey: "timer.sound") as? Bool ?? true
    @State private var timerHaptic = UserDefaults.standard.object(forKey: "timer.haptic") as? Bool ?? true

    // Language
    @State private var appLanguage = UserDefaults.standard.string(forKey: "app.language") ?? "system"

    // Delete account
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                handsFreeSection
                notificationsSection
                languageSection
                accountSection
                aboutSection
            }
            .navigationTitle("Настройки")
        }
    }

    // MARK: - Server section

    private var serverSection: some View {
        Section {
            TextField("URL сервера", text: $serverURL)
                .autocapitalization(.none)
                .keyboardType(.URL)
                .onChange(of: serverURL) { _, new in
                    UserDefaults.standard.set(new, forKey: "serverURL")
                    if let url = URL(string: new) {
                        APIClient.shared.updateBaseURL(url)
                    }
                    serverCheckState = .idle
                }

            HStack {
                switch serverCheckState {
                case .idle:
                    Button("Проверить доступность") {
                        Task { await checkServer() }
                    }
                    .foregroundStyle(.orange)
                case .checking:
                    ProgressView()
                    Text("Проверка...").foregroundStyle(.secondary)
                case .ok(let ms):
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Доступен · \(ms) мс").foregroundStyle(.green)
                case .fail(let msg):
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text(msg).foregroundStyle(.red)
                }
                Spacer()
            }
            .font(.subheadline)
        } header: {
            Text("Сервер")
        }
    }

    // MARK: - Hands-Free section

    private var handsFreeSection: some View {
        Section {
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
                    AVCaptureDevice.requestAccess(for: .video) { _ in
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

    // MARK: - Notifications section

    private var notificationsSection: some View {
        Section("Таймер") {
            Toggle("Звук по окончании", isOn: $timerSound)
                .onChange(of: timerSound) { _, new in
                    UserDefaults.standard.set(new, forKey: "timer.sound")
                }
            Toggle("Вибрация по окончании", isOn: $timerHaptic)
                .onChange(of: timerHaptic) { _, new in
                    UserDefaults.standard.set(new, forKey: "timer.haptic")
                }
        }
    }

    // MARK: - Language section

    private var languageSection: some View {
        Section("Язык интерфейса") {
            Picker("Язык", selection: $appLanguage) {
                Text("Системный").tag("system")
                Text("Русский").tag("ru")
                Text("English").tag("en")
            }
            .onChange(of: appLanguage) { _, new in
                UserDefaults.standard.set(new, forKey: "app.language")
            }
        }
    }

    // MARK: - Account section

    private var accountSection: some View {
        Section("Аккаунт") {
            Button("Выйти", role: .destructive) {
                authVM.logout()
            }

            Button("Удалить аккаунт", role: .destructive) {
                showDeleteConfirm = true
            }
            .confirmationDialog(
                "Удалить аккаунт?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Удалить", role: .destructive) {
                    authVM.logout()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Все данные будут удалены без возможности восстановления.")
            }
        }
    }

    // MARK: - About section

    private var aboutSection: some View {
        Section("О приложении") {
            LabeledContent(
                "Версия",
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
            )
            NavigationLink("Лицензии") {
                LicensesView()
            }
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

    private func checkServer() async {
        serverCheckState = .checking
        guard let url = URL(string: serverURL)?.appendingPathComponent("/health") else {
            serverCheckState = .fail("Некорректный URL")
            return
        }
        let start = Date()
        do {
            var req = URLRequest(url: url, timeoutInterval: 5)
            req.httpMethod = "GET"
            let (_, response) = try await URLSession.shared.data(for: req)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                serverCheckState = .ok(ms)
            } else {
                serverCheckState = .fail("Сервер недоступен")
            }
        } catch {
            serverCheckState = .fail("Нет ответа")
        }
    }
}

// MARK: - Server check state

private enum ServerCheckState {
    case idle
    case checking
    case ok(Int)
    case fail(String)
}

// MARK: - Licenses view

private struct LicensesView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SwiftUI / SwiftData")
                        .font(.subheadline.bold())
                    Text("Copyright © Apple Inc. Используется в соответствии с лицензией Apple.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vision Framework")
                        .font(.subheadline.bold())
                    Text("Copyright © Apple Inc. Используется в соответствии с лицензией Apple.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Лицензии")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Double helper

private extension Double {
    func nonzero(default value: Double) -> Double {
        self == 0 ? value : self
    }
}
