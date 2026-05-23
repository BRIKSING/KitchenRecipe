import SwiftUI

// Floating overlay shown over CookingSessionView when voice commands are active.
// Positioned near the top so it does not overlap HandsFreeOverlayView at the bottom.
struct VoiceCommandOverlayView: View {
    let command: VoiceCommand?
    let isActive: Bool

    @State private var micPulse = false

    var body: some View {
        VStack {
            if isActive {
                VStack(spacing: 6) {
                    micBadge
                    if let cmd = command {
                        commandCard(cmd)
                            .transition(
                                .scale(scale: 0.8)
                                .combined(with: .opacity)
                            )
                    }
                }
                .padding(.top, 64) // below progress bar + header
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: command)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - Mic badge

    private var micBadge: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.35))
                    .frame(width: 16, height: 16)
                    .scaleEffect(micPulse ? 1.5 : 1.0)
                    .opacity(micPulse ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                        value: micPulse
                    )
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            }
            Text("Голос активен")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .onAppear { micPulse = true }
        .onDisappear { micPulse = false }
    }

    // MARK: - Command card

    private func commandCard(_ cmd: VoiceCommand) -> some View {
        HStack(spacing: 10) {
            Image(systemName: cmd.iconName)
                .font(.system(size: 22))
                .foregroundStyle(.blue)
            Text(cmd.displayName)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }
}
