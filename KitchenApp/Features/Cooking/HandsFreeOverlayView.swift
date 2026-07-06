import SwiftUI

// Transparent overlay shown on top of CookingSessionView when hands-free is active.
// Shows detected gesture (icon + name) with auto-dismiss animation.
//
// Документация: DOCS.md → «MVP — Hands-free жесты (следующий/предыдущий шаг)».
// Нижний (bottom) оверлей: пульсирующий бейдж «Hands-free активен» с полосой
// уверенности (confidence) и карточка последнего жеста (gesture) с иконкой и
// названием из GestureType. Пассивен — allowsHitTesting(false), не перехватывает
// свайпы сессии; размещён снизу, чтобы не пересекаться с VoiceCommandOverlayView.
struct HandsFreeOverlayView: View {
    let gesture: GestureType?
    let confidence: Float
    let isActive: Bool

    var body: some View {
        VStack {
            Spacer()

            if isActive {
                VStack(spacing: 0) {
                    statusBadge

                    if let gesture {
                        gestureCard(gesture)
                            .transition(
                                .scale(scale: 0.8)
                                .combined(with: .opacity)
                            )
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, 100)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: gesture)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Status badge

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(confidenceColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(confidenceColor.opacity(0.3), lineWidth: 4)
                        .scaleEffect(confidence > 0.5 ? 1.5 : 1)
                        .animation(
                            confidence > 0.5
                                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                : .default,
                            value: confidence
                        )
                )

            Text("Hands-free активен")
                .font(.caption.bold())
                .foregroundStyle(.white)

            // Confidence bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.3))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(confidenceColor)
                        .frame(width: geo.size.width * CGFloat(confidence))
                        .animation(.easeOut(duration: 0.2), value: confidence)
                }
            }
            .frame(width: 60, height: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Gesture card

    private func gestureCard(_ gesture: GestureType) -> some View {
        VStack(spacing: 10) {
            Image(systemName: gesture.iconName)
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text(gesture.displayName)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 4)
    }

    // MARK: - Helpers

    private var confidenceColor: Color {
        switch confidence {
        case 0..<0.3: return .red
        case 0.3..<0.6: return .yellow
        default: return .green
        }
    }
}
