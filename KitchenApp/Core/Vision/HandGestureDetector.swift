import AVFoundation
import Vision
import Foundation

// NSCameraUsageDescription must be set in Info.plist:
// "Камера используется для управления рецептом жестами рук в режиме Hands-Free"

/// Распознавание жестов рук для Hands-Free управления сессией приготовления
/// через Vision (`VNDetectHumanHandPoseRequest`) поверх `AVCaptureSession`
/// (SPEC.md §2.7, §6 «MVP»). Ключевой сценарий MVP — листание шагов «следующий /
/// предыдущий» открытой ладонью; также распознаются кулак (пауза/таймер) и V.
///
/// Работает **локально**: видеопоток обрабатывается на устройстве в фоновой
/// очереди (`processingQueue`) и **не** передаётся на сервер; UI-поля публикуются
/// на главном потоке. Направление свайпа определяется по дельте `x` запястья
/// между кадрами (передняя камера зеркальна: свайп вправо → `wrist.x` убывает).
///
/// Публикуемые поля: `detectedGesture` (для оверлея, гасит себя через 1.5 с),
/// `isRunning`, `detectionConfidence` (уверенность по точке запястья). Внешняя
/// точка выхода — замыкание `onGesture`, которое `CookingSessionView` мапит на
/// навигацию/таймер. Между срабатываниями выдерживается `cooldown = 1.5 с`.
/// Параметры `swipeSensitivity` и `fistHoldDuration` читаются из `UserDefaults`
/// (настраиваются в `SettingsView`). Документация: DOCS.md → «MVP — Hands-free
/// жесты (следующий/предыдущий шаг)».
final class HandGestureDetector: NSObject, ObservableObject {
    @Published private(set) var detectedGesture: GestureType?
    @Published private(set) var isRunning = false
    @Published private(set) var detectionConfidence: Float = 0

    // Configurable via SettingsView (persisted in UserDefaults)
    var swipeSensitivity: Double   // minimum wrist Δx to register swipe (0.02–0.10)
    var fistHoldDuration: Double   // seconds fist must be held (0.5–2.0)

    var onGesture: ((GestureType) -> Void)?

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(
        label: "com.kitchen.handgesture",
        qos: .userInteractive
    )

    private let cooldown: TimeInterval = 1.5
    private var lastGestureTime: Date = .distantPast

    // Swipe: track wrist position across frames
    private var previousWristPosition: CGPoint?
    private var wristBuffer: [CGPoint] = []
    private let bufferSize = 5

    // Fist hold: timestamp when fist first detected
    private var fistDetectedAt: Date?

    // MARK: - Init

    init(
        swipeSensitivity: Double = UserDefaults.standard.double(forKey: "handsfree.swipeSensitivity").nonzero(default: 0.04),
        fistHoldDuration: Double = UserDefaults.standard.double(forKey: "handsfree.fistHoldDuration").nonzero(default: 1.0)
    ) {
        self.swipeSensitivity = swipeSensitivity
        self.fistHoldDuration = fistHoldDuration
        super.init()
    }

    // MARK: - Public API

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            self?.setupAndStart()
        }
    }

    func stop() {
        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            self?.resetState()
        }
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
            self?.detectedGesture = nil
            self?.detectionConfidence = 0
        }
    }

    // MARK: - Setup

    private func setupAndStart() {
        guard !captureSession.isRunning else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .front
            ),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.commitConfiguration()
        captureSession.startRunning()

        DispatchQueue.main.async { [weak self] in
            self?.isRunning = true
        }
    }

    private func resetState() {
        previousWristPosition = nil
        wristBuffer = []
        fistDetectedAt = nil
    }
}

// MARK: - Sample Buffer Delegate

extension HandGestureDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1

        let handler = VNImageRequestHandler(
            cmSampleBuffer: sampleBuffer,
            orientation: .leftMirrored,
            options: [:]
        )
        try? handler.perform([request])

        guard let observation = request.results?.first else {
            fistDetectedAt = nil
            previousWristPosition = nil
            wristBuffer = []
            DispatchQueue.main.async { [weak self] in
                self?.detectionConfidence = 0
            }
            return
        }

        processObservation(observation)
    }
}

// MARK: - Gesture Detection

extension HandGestureDetector {

    private func processObservation(_ observation: VNHumanHandPoseObservation) {
        let now = Date()

        // Update detection confidence from wrist point
        let confidence = (try? observation.recognizedPoint(.wrist))?.confidence ?? 0
        DispatchQueue.main.async { [weak self] in
            self?.detectionConfidence = confidence
        }

        guard now.timeIntervalSince(lastGestureTime) >= cooldown else {
            // During cooldown still track fist hold start
            if !isFist(observation) { fistDetectedAt = nil }
            return
        }

        if let gesture = detectGesture(from: observation, now: now) {
            lastGestureTime = now
            fistDetectedAt = nil
            wristBuffer = []
            previousWristPosition = nil

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.detectedGesture = gesture
                self.onGesture?(gesture)

                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if self?.detectedGesture == gesture {
                        self?.detectedGesture = nil
                    }
                }
            }
        }
    }

    private func detectGesture(from observation: VNHumanHandPoseObservation, now: Date) -> GestureType? {
        // 1. Fist hold
        if isFist(observation) {
            if let start = fistDetectedAt {
                if now.timeIntervalSince(start) >= fistHoldDuration {
                    return .fistHold
                }
            } else {
                fistDetectedAt = now
            }
            return nil
        } else {
            fistDetectedAt = nil
        }

        // 2. Victory (V gesture)
        if isVictory(observation) {
            return .victory
        }

        // 3. Swipe (open palm + wrist delta)
        if isPalmOpen(observation) {
            return detectSwipe(from: observation)
        }

        return nil
    }

    // MARK: - Finger state helpers

    // Vision coords: y increases upward (0=bottom, 1=top).
    // Extended finger: tip.y > mcp.y by a margin.
    private func isExtended(tip: VNRecognizedPoint, mcp: VNRecognizedPoint) -> Bool {
        guard tip.confidence > 0.3, mcp.confidence > 0.3 else { return false }
        return tip.location.y > mcp.location.y + 0.03
    }

    private func fingerPoints(
        _ observation: VNHumanHandPoseObservation,
        tip: VNHumanHandPoseObservation.JointName,
        mcp: VNHumanHandPoseObservation.JointName
    ) -> (VNRecognizedPoint, VNRecognizedPoint)? {
        guard
            let t = try? observation.recognizedPoint(tip),
            let m = try? observation.recognizedPoint(mcp)
        else { return nil }
        return (t, m)
    }

    private func isPalmOpen(_ obs: VNHumanHandPoseObservation) -> Bool {
        let pairs: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            (.indexTip,  .indexMCP),
            (.middleTip, .middleMCP),
            (.ringTip,   .ringMCP),
            (.littleTip, .littleMCP)
        ]
        let extendedCount = pairs.compactMap { fingerPoints(obs, tip: $0.0, mcp: $0.1) }
                                 .filter { isExtended(tip: $0.0, mcp: $0.1) }
                                 .count
        return extendedCount >= 3
    }

    private func isFist(_ obs: VNHumanHandPoseObservation) -> Bool {
        let pairs: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            (.indexTip,  .indexMCP),
            (.middleTip, .middleMCP),
            (.ringTip,   .ringMCP),
            (.littleTip, .littleMCP)
        ]
        let curledCount = pairs.compactMap { fingerPoints(obs, tip: $0.0, mcp: $0.1) }
                               .filter { !isExtended(tip: $0.0, mcp: $0.1) }
                               .count
        return curledCount >= 3
    }

    private func isVictory(_ obs: VNHumanHandPoseObservation) -> Bool {
        guard
            let (indexTip, indexMCP)   = fingerPoints(obs, tip: .indexTip,  mcp: .indexMCP),
            let (middleTip, middleMCP) = fingerPoints(obs, tip: .middleTip, mcp: .middleMCP),
            let (ringTip, ringMCP)     = fingerPoints(obs, tip: .ringTip,   mcp: .ringMCP),
            let (pinkyTip, pinkyMCP)   = fingerPoints(obs, tip: .littleTip, mcp: .littleMCP)
        else { return false }

        return isExtended(tip: indexTip,  mcp: indexMCP)
            && isExtended(tip: middleTip, mcp: middleMCP)
            && !isExtended(tip: ringTip,  mcp: ringMCP)
            && !isExtended(tip: pinkyTip, mcp: pinkyMCP)
    }

    // MARK: - Swipe detection

    private func detectSwipe(from obs: VNHumanHandPoseObservation) -> GestureType? {
        guard
            let wristPt = try? obs.recognizedPoint(.wrist),
            wristPt.confidence > 0.4
        else { return nil }

        let wristPos = wristPt.location

        defer {
            wristBuffer.append(wristPos)
            if wristBuffer.count > bufferSize { wristBuffer.removeFirst() }
            previousWristPosition = wristPos
        }

        guard let prev = previousWristPosition else { return nil }

        let deltaX = wristPos.x - prev.x

        // Front camera is mirrored: user swipes right → wrist.x decreases in Vision space
        if deltaX < -swipeSensitivity {
            return .swipeNext
        } else if deltaX > swipeSensitivity {
            return .swipePrev
        }

        return nil
    }
}

// MARK: - Double helper

private extension Double {
    func nonzero(default value: Double) -> Double {
        self == 0 ? value : self
    }
}
