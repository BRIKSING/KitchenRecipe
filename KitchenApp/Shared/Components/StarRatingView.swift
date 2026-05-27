import SwiftUI

// MARK: - StarRatingView

/// Переиспользуемый компонент звёздного рейтинга.
/// Поддерживает display-only и интерактивный режим (tap/drag для выбора оценки).
struct StarRatingView: View {
    /// Текущий рейтинг (0.0 – maxStars).
    var rating: Double
    var maxStars: Int = 5
    var starSize: CGFloat = 22
    var color: Color = .orange
    /// Если true — кнопки кликабельны, вызывает onRatingChanged.
    var isInteractive: Bool = false
    var onRatingChanged: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...maxStars, id: \.self) { star in
                starImage(for: star)
                    .font(.system(size: starSize))
                    .foregroundStyle(color)
                    .scaleEffect(isInteractive && Int(rating) == star ? 1.2 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.55), value: rating)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isInteractive {
                            withAnimation { onRatingChanged?(star) }
                        }
                    }
                    .accessibilityLabel("\(star) \(star == 1 ? "звезда" : star < 5 ? "звезды" : "звёзд")")
                    .accessibilityAddTraits(isInteractive ? .isButton : [])
            }
        }
        .accessibilityElement(children: isInteractive ? .contain : .combine)
        .accessibilityLabel(ratingAccessibilityLabel)
    }

    // MARK: - Private helpers

    private func starImage(for star: Int) -> Image {
        let value = Double(star)
        if value <= rating {
            return Image(systemName: "star.fill")
        } else if value - 0.5 <= rating {
            return Image(systemName: "star.leadinghalf.filled")
        } else {
            return Image(systemName: "star")
        }
    }

    private var ratingAccessibilityLabel: String {
        let rounded = (rating * 10).rounded() / 10
        return "Рейтинг \(rounded) из \(maxStars)"
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 20) {
        StarRatingView(rating: 4.5)
        StarRatingView(rating: 3.0, starSize: 30)
        StarRatingView(rating: 0, isInteractive: true) { _ in }
    }
    .padding()
}
#endif
