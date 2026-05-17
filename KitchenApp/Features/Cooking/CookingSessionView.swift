import SwiftUI

struct CookingSessionView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss

    private var sortedSteps: [Step] {
        recipe.steps.sorted { $0.sortOrder < $1.sortOrder }
    }

    @State private var currentStepIndex = 0
    @State private var showCompletion = false
    @StateObject private var timer = TimerService()

    // Per-step timer state: [stepIndex: (remaining, isFinished)]
    @State private var timerStates: [Int: (remaining: Int, isFinished: Bool)] = [:]

    // Hands-free stub (full implementation in Этап 10)
    @State private var handsFreeEnabled = false

    // Photo viewer
    @State private var photoPage = 0
    @State private var photoScale: CGFloat = 1.0
    @State private var lastPhotoScale: CGFloat = 1.0

    private var currentStep: Step { sortedSteps[currentStepIndex] }
    private var totalSteps: Int { sortedSteps.count }
    private var stepProgress: Double { Double(currentStepIndex + 1) / Double(max(1, totalSteps)) }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                headerBar
                photoSlider
                Divider()
                stepScrollContent
                Divider()
                bottomNavBar
            }

            if showCompletion {
                CompletionView { dismiss() }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            configureTimerForStep(0)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            timer.stop()
        }
        .onChange(of: currentStepIndex) { oldIndex, newIndex in
            saveTimerState(for: oldIndex)
            photoPage = 0
            withAnimation(.spring(response: 0.3)) {
                photoScale = 1.0
                lastPhotoScale = 1.0
            }
            configureTimerForStep(newIndex)
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color(.systemGray5)
                Color.orange
                    .frame(width: geo.size.width * stepProgress)
                    .animation(.easeInOut(duration: 0.35), value: currentStepIndex)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(9)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Circle())
            }
            .foregroundStyle(.primary)

            Spacer()

            Text("Шаг \(currentStepIndex + 1) из \(totalSteps)")
                .font(.subheadline.bold())

            Spacer()

            Button {
                handsFreeEnabled.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                    Text(handsFreeEnabled ? "ON" : "OFF")
                }
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(handsFreeEnabled ? Color.orange : Color(.tertiarySystemBackground))
                .foregroundStyle(handsFreeEnabled ? .white : .primary)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Photo slider

    private var photoSlider: some View {
        let photos = currentStep.photos.sorted { $0.sortOrder < $1.sortOrder }

        return ZStack(alignment: .bottom) {
            Color.black

            if photos.isEmpty {
                Image(systemName: "photo")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $photoPage) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        CachedAsyncImage(url: photo.url) { image in
                            image
                                .resizable()
                                .scaledToFit()
                                .scaleEffect(photoScale)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        } placeholder: {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    photoScale = max(1.0, min(4.0, lastPhotoScale * value))
                                }
                                .onEnded { _ in
                                    lastPhotoScale = photoScale
                                    if photoScale < 1.05 {
                                        withAnimation(.spring(response: 0.3)) {
                                            photoScale = 1.0
                                            lastPhotoScale = 1.0
                                        }
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                if photoScale > 1.0 {
                                    photoScale = 1.0
                                    lastPhotoScale = 1.0
                                } else {
                                    photoScale = 2.5
                                    lastPhotoScale = 2.5
                                }
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if photos.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<photos.count, id: \.self) { i in
                            Circle()
                                .fill(i == photoPage ? Color.white : Color.white.opacity(0.45))
                                .frame(width: i == photoPage ? 8 : 6, height: i == photoPage ? 8 : 6)
                                .animation(.easeInOut(duration: 0.2), value: photoPage)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(height: 260)
        .clipped()
    }

    // MARK: - Step content

    private var stepScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(currentStep.title)
                    .font(.title3.bold())

                Text(currentStep.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let timerSec = currentStep.timerSec, timerSec > 0 {
                    timerControl
                }

                Color.clear.frame(height: 4)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Timer control

    private var timerControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(timer.formattedTime)
                    .font(.system(.title3, design: .monospaced).bold())
                    .foregroundStyle(timer.isFinished ? .green : .primary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: timer.remaining)

                if timer.isFinished {
                    Text("Время вышло!")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            if timer.isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
            }

            Button {
                timer.toggle()
            } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(timer.isFinished ? Color(.systemGray3) : Color.orange)
                    .clipShape(Circle())
            }
            .disabled(timer.isFinished)

            Button {
                if let timerSec = currentStep.timerSec {
                    timer.configure(seconds: timerSec)
                    timerStates[currentStepIndex] = nil
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Circle())
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Bottom navigation

    private var bottomNavBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    navigatePrev()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Назад")
                            .font(.subheadline.bold())
                    }
                    .foregroundStyle(currentStepIndex > 0 ? Color.orange : Color(.systemGray3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(currentStepIndex == 0)

                stepDots
                    .frame(maxWidth: .infinity)

                Button {
                    navigateNext()
                } label: {
                    HStack(spacing: 5) {
                        Text(currentStepIndex == totalSteps - 1 ? "Готово" : "Вперёд")
                            .font(.subheadline.bold())
                        Image(systemName: currentStepIndex == totalSteps - 1 ? "checkmark.circle.fill" : "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color.orange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .gesture(
                DragGesture(minimumDistance: 40, coordinateSpace: .local)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > abs(dy) * 1.2 else { return }
                        if dx < -40 { navigateNext() }
                        else if dx > 40 { navigatePrev() }
                    }
            )

            // Hands-free row
            Button {
                handsFreeEnabled.toggle()
            } label: {
                Label(
                    handsFreeEnabled ? "Hands-free: включён" : "Hands-free: выключен",
                    systemImage: "eye"
                )
                .font(.caption.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(handsFreeEnabled ? Color.orange.opacity(0.15) : Color(.tertiarySystemBackground))
                .foregroundStyle(handsFreeEnabled ? .orange : .secondary)
                .clipShape(Capsule())
            }
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var stepDots: some View {
        let maxVisible = 9
        let half = maxVisible / 2
        let start = max(0, min(currentStepIndex - half, totalSteps - maxVisible))
        let end = min(start + maxVisible, totalSteps)

        HStack(spacing: 5) {
            ForEach(start..<end, id: \.self) { i in
                Circle()
                    .fill(i == currentStepIndex ? Color.orange : Color(.systemGray4))
                    .frame(
                        width: i == currentStepIndex ? 10 : 7,
                        height: i == currentStepIndex ? 10 : 7
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStepIndex)
            }
        }
    }

    // MARK: - Navigation

    private func navigateNext() {
        if currentStepIndex == totalSteps - 1 {
            withAnimation(.easeIn(duration: 0.3)) { showCompletion = true }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { currentStepIndex += 1 }
        }
    }

    private func navigatePrev() {
        guard currentStepIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) { currentStepIndex -= 1 }
    }

    // MARK: - Timer state management

    private func configureTimerForStep(_ index: Int) {
        guard index < sortedSteps.count else { return }
        let step = sortedSteps[index]
        guard let timerSec = step.timerSec, timerSec > 0 else { return }

        if let saved = timerStates[index] {
            timer.restore(remaining: saved.remaining, total: timerSec, isFinished: saved.isFinished)
        } else {
            timer.configure(seconds: timerSec)
        }
    }

    private func saveTimerState(for index: Int) {
        guard index < sortedSteps.count, sortedSteps[index].timerSec != nil else { return }
        timerStates[index] = (timer.remaining, timer.isFinished)
        timer.pause()
    }
}

// MARK: - Completion screen

private struct CompletionView: View {
    let onClose: () -> Void

    @State private var iconScale: CGFloat = 0.3
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.08))
                        .frame(width: 210, height: 210)
                    Circle()
                        .fill(Color.orange.opacity(0.14))
                        .frame(width: 160, height: 160)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 90))
                        .foregroundStyle(Color.orange)
                }
                .scaleEffect(iconScale)

                Spacer().frame(height: 32)

                VStack(spacing: 8) {
                    Text("Готово!")
                        .font(.largeTitle.bold())
                    Text("Приятного аппетита!")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .opacity(contentOpacity)

                Spacer()

                VStack(spacing: 14) {
                    Button {
                        // Оценка рецепта — будет реализована в следующих этапах
                    } label: {
                        Label("Оценить рецепт", systemImage: "star.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button("Закрыть", action: onClose)
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 40)
                .opacity(contentOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.65).delay(0.05)) {
                iconScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                contentOpacity = 1.0
            }
        }
    }
}
