import Foundation
import AudioToolbox

@MainActor
final class TimerService: ObservableObject {
    @Published private(set) var remaining: Int = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isFinished: Bool = false

    private var totalSeconds: Int = 0
    private var runTask: Task<Void, Never>?

    func configure(seconds: Int) {
        stop()
        totalSeconds = seconds
        remaining = seconds
        isFinished = false
    }

    func restore(remaining: Int, total: Int, isFinished: Bool) {
        stop()
        totalSeconds = total
        self.remaining = remaining
        self.isFinished = isFinished
    }

    func toggle() {
        isRunning ? pause() : resume()
    }

    func resume() {
        guard remaining > 0, !isFinished else { return }
        isRunning = true
        runTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.remaining > 0 else { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { break }
                self.remaining -= 1
                if self.remaining == 0 {
                    self.isRunning = false
                    self.isFinished = true
                    AudioServicesPlaySystemSound(1315)
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
        }
    }

    func pause() {
        isRunning = false
        runTask?.cancel()
        runTask = nil
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
    }

    var formattedTime: String {
        remaining.formattedTimer
    }
}
