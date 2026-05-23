import Foundation
import Speech
import AVFoundation

// Required Info.plist keys:
//   NSSpeechRecognitionUsageDescription —
//     "Голосовые команды позволяют управлять шагами приготовления без рук."
//   NSMicrophoneUsageDescription —
//     "Микрофон используется для голосовых команд и Hands-Free режима."

// MARK: - VoiceCommand

enum VoiceCommand: Equatable {
    case nextStep
    case prevStep
    case toggleTimer
    case stopCooking

    var displayName: String {
        switch self {
        case .nextStep:    return "Следующий шаг"
        case .prevStep:    return "Предыдущий шаг"
        case .toggleTimer: return "Таймер"
        case .stopCooking: return "Выйти"
        }
    }

    var iconName: String {
        switch self {
        case .nextStep:    return "chevron.right.circle.fill"
        case .prevStep:    return "chevron.left.circle.fill"
        case .toggleTimer: return "timer"
        case .stopCooking: return "xmark.circle.fill"
        }
    }
}

// MARK: - VoiceCommandService

@MainActor
final class VoiceCommandService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var lastCommand: VoiceCommand?
    @Published private(set) var speechAuthStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    var onCommand: ((VoiceCommand) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false

    private var shouldRestart = false
    private var restartTask: Task<Void, Never>?
    private var lastCommandTime: Date = .distantPast
    private let commandCooldown: TimeInterval = 1.5

    // Supported command keywords (Russian primary, English fallback)
    private let keywords: [(keywords: [String], command: VoiceCommand)] = [
        (["следующий", "вперёд", "дальше", "следующее", "next"],       .nextStep),
        (["назад", "предыдущий", "обратно", "previous", "back"],       .prevStep),
        (["пауза", "паузу", "останови", "останов", "пустить", "pause", "start timer"], .toggleTimer),
        (["старт", "запустить", "запуск", "поехали", "начать",  "start"], .toggleTimer),
        (["выход", "выйти", "закрыть", "закончить", "стоп", "exit"],   .stopCooking),
    ]

    init() {
        let ruLocale = Locale(identifier: "ru-RU")
        let enLocale = Locale(identifier: "en-US")
        recognizer = SFSpeechRecognizer(locale: ruLocale) ?? SFSpeechRecognizer(locale: enLocale)
        speechAuthStatus = SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Permissions

    func requestPermissions() async {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.speechAuthStatus = status
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Start / Stop

    func start() {
        guard !isListening, speechAuthStatus == .authorized else { return }
        shouldRestart = true
        beginSession()
    }

    func stop() {
        shouldRestart = false
        restartTask?.cancel()
        endSession()
    }

    // MARK: - Session lifecycle

    private func beginSession() {
        endSession()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.duckOthers, .defaultToSpeaker]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            recognitionRequest = request

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString.lowercased()
                        self.matchCommand(in: text)
                    }
                    if error != nil || result?.isFinal == true {
                        self.isListening = false
                        if self.shouldRestart {
                            self.scheduleRestart()
                        }
                    }
                }
            }

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }
            tapInstalled = true

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            endSession()
        }
    }

    private func endSession() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    private func scheduleRestart() {
        restartTask?.cancel()
        restartTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, shouldRestart else { return }
            beginSession()
        }
    }

    // MARK: - Command matching

    private func matchCommand(in text: String) {
        let now = Date()
        guard now.timeIntervalSince(lastCommandTime) >= commandCooldown else { return }

        for entry in keywords {
            if entry.keywords.contains(where: { text.contains($0) }) {
                lastCommandTime = now
                let cmd = entry.command
                lastCommand = cmd
                onCommand?(cmd)
                Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    if lastCommand == cmd { lastCommand = nil }
                }
                return
            }
        }
    }
}
