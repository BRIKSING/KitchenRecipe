import SwiftUI
import AVFoundation
import Speech

struct SettingsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var syncService: iCloudSyncService

    // Server
    @State private var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:3000"
    @State private var serverCheckState: ServerCheckState = .idle

    // Hands-Free
    @State private var handsfreeDefault = UserDefaults.standard.bool(forKey: "handsfree.enabledByDefault")
    @State private var swipeSensitivity = UserDefaults.standard.double(forKey: "handsfree.swipeSensitivity").nonzero(default: 0.04)
    @State private var fistHoldDuration = UserDefaults.standard.double(forKey: "handsfree.fistHoldDuration").nonzero(default: 1.0)
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    // Voice commands
    @State private var voiceDefault = UserDefaults.standard.bool(forKey: "voice.enabledByDefault")
    @State private var speechAuthStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()

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
                iCloudSyncSection
                handsFreeSection
                voiceCommandsSection
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

            if isInsecureURL {
                Label {
                    Text("Незащищённое соединение (HTTP). В продакшене используйте HTTPS — иначе токены и данные передаются в открытом виде.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.open.trianglebadge.exclamationmark.fill")
                }
                .foregroundStyle(.red)
                .accessibilityLabel("Предупреждение: незащищённое HTTP соединение")
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

    /// true when URL is HTTP and not a local development address
    private var isInsecureURL: Bool {
        let url = serverURL.lowercased()
        guard url.hasPrefix("http://") else { return false }
        return !url.hasPrefix("http://localhost") && !url.hasPrefix("http://127.")
    }

    // MARK: - iCloud Sync section

    private var iCloudSyncSection: some View {
        Section {
            // Статус синхронизации
            HStack {
                iCloudStatusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(iCloudStatusTitle)
                        .font(.subheadline)
                    Text(iCloudStatusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if syncService.isAvailable {
                    Button {
                        syncService.syncNow()
                        syncService.pushSettings()
                    } label: {
                        Text(NSLocalizedString("icloud.sync.now", value: "Синхронизировать", comment: ""))
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.orange)
                }
            }
            .padding(.vertical, 2)

            // Количество избранных рецептов
            if syncService.isAvailable {
                LabeledContent(
                    NSLocalizedString("icloud.favorites.count", value: "Избранных рецептов", comment: ""),
                    value: "\(syncService.favoriteIDs.count)"
                )

                // Синхронизация настроек
                Button {
                    syncService.pushSettings()
                } label: {
                    Label(
                        NSLocalizedString("icloud.push.settings", value: "Синхронизировать настройки", comment: ""),
                        systemImage: "arrow.up.icloud"
                    )
                }
                .foregroundStyle(.orange)
            }
        } header: {
            Text(NSLocalizedString("icloud.section.title", value: "iCloud", comment: ""))
        } footer: {
            Text(NSLocalizedString("icloud.section.footer",
                                   value: "Избранные рецепты и настройки автоматически синхронизируются между вашими устройствами через iCloud.",
                                   comment: ""))
        }
    }

    @ViewBuilder
    private var iCloudStatusIcon: some View {
        switch syncService.status {
        case .syncing:
            ProgressView().controlSize(.small)
        case .synced:
            Image(systemName: "checkmark.icloud.fill")
                .foregroundStyle(.green)
                .font(.system(size: 22))
        case .unavailable:
            Image(systemName: "icloud.slash")
                .foregroundStyle(.secondary)
                .font(.system(size: 22))
        case .error:
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundStyle(.red)
                .font(.system(size: 22))
        case .idle:
            Image(systemName: "icloud")
                .foregroundStyle(.orange)
                .font(.system(size: 22))
        }
    }

    private var iCloudStatusTitle: String {
        switch syncService.status {
        case .syncing:
            return NSLocalizedString("icloud.status.syncing", value: "Синхронизация...", comment: "")
        case .synced(let date):
            let timeStr = date.formatted(date: .omitted, time: .shortened)
            return String(format: NSLocalizedString("icloud.status.synced", value: "Синхронизировано в %@", comment: ""), timeStr)
        case .unavailable:
            return NSLocalizedString("icloud.status.unavailable", value: "iCloud недоступен", comment: "")
        case .error(let msg):
            return msg
        case .idle:
            return NSLocalizedString("icloud.status.idle", value: "iCloud включён", comment: "")
        }
    }

    private var iCloudStatusSubtitle: String {
        switch syncService.status {
        case .unavailable:
            return NSLocalizedString("icloud.status.unavailable.hint",
                                     value: "Войдите в iCloud в настройках устройства",
                                     comment: "")
        default:
            return NSLocalizedString("icloud.status.hint",
                                     value: "Избранное и настройки",
                                     comment: "")
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

    // MARK: - Voice commands section

    private var voiceCommandsSection: some View {
        Section {
            speechPermissionRow

            Toggle("Включать по умолчанию", isOn: $voiceDefault)
                .onChange(of: voiceDefault) { _, new in
                    UserDefaults.standard.set(new, forKey: "voice.enabledByDefault")
                }

            NavigationLink("Список команд") {
                VoiceCommandsHelpView()
            }
        } header: {
            Text("Голосовые команды")
        } footer: {
            Text("Голос обрабатывается локально через Apple Speech Recognition. Аудио не передаётся на серверы приложения.")
        }
    }

    private var speechPermissionRow: some View {
        HStack {
            Label("Распознавание речи", systemImage: "mic.fill")
            Spacer()
            switch speechAuthStatus {
            case .authorized:
                Text("Разрешено")
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
                    SFSpeechRecognizer.requestAuthorization { status in
                        DispatchQueue.main.async {
                            speechAuthStatus = status
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
            if let username = authVM.userUsername {
                LabeledContent("Пользователь", value: username)
            }
            if let email = authVM.userEmail {
                LabeledContent("Email", value: email)
            }

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
        case ..<0.03:    return NSLocalizedString("sensitivity.high",   value: "Высокая", comment: "")
        case 0.03..<0.06: return NSLocalizedString("sensitivity.medium", value: "Средняя", comment: "")
        default:          return NSLocalizedString("sensitivity.low",    value: "Низкая",  comment: "")
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

// MARK: - Voice commands help view

private struct VoiceCommandsHelpView: View {
    private let commands: [(phrase: String, action: String)] = [
        ("«Следующий» / «Вперёд»",  "Следующий шаг"),
        ("«Назад» / «Предыдущий»",  "Предыдущий шаг"),
        ("«Пауза» / «Останови»",    "Пауза таймера"),
        ("«Старт» / «Запуск»",      "Запустить таймер"),
        ("«Выйти» / «Закрыть»",     "Завершить приготовление"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(commands, id: \.phrase) { item in
                    HStack {
                        Text(item.phrase)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(item.action)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Доступные команды")
            } footer: {
                Text("Говорите чётко и отчётливо. Между командами выдерживайте паузу ~1.5 сек.")
            }

            Section("Советы") {
                Label("Используйте русский язык — распознавание оптимизировано для него", systemImage: "waveform")
                Label("Команды работают независимо от Hands-Free жестов", systemImage: "hand.raised.and.text.clock")
                Label("Аудио не покидает устройство — только Apple Speech API", systemImage: "lock.shield")
            }
            .font(.subheadline)
        }
        .navigationTitle("Голосовые команды")
        .navigationBarTitleDisplayMode(.inline)
    }
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
