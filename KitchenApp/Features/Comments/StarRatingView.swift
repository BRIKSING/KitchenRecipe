import SwiftUI

// MARK: - StarRatingView

/// Displays a star rating (1–5).
/// When `onRate` is provided, the stars are interactive.
struct StarRatingView: View {

    // MARK: Configuration

    var rating: Double          // Current displayed rating (e.g. 4.3)
    var userRating: Int?        // Selected star (1-5) by the current user
    var maxStars: Int = 5
    var starSize: CGFloat = 22
    var interactive: Bool = false
    var onRate: ((Int) -> Void)?

    // MARK: Body

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...maxStars, id: \.self) { index in
                starImage(for: index)
                    .font(.system(size: starSize))
                    .foregroundStyle(starColor(for: index))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard interactive else { return }
                        onRate?(index)
                    }
                    .animation(.easeInOut(duration: 0.15), value: userRating)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(format: NSLocalizedString("accessibility.rating", value: "Рейтинг: %.1f из %d", comment: ""), rating, maxStars)
        )
        .accessibilityValue(
            userRating.map { String(format: NSLocalizedString("accessibility.your_rating", value: "Ваша оценка: %d", comment: ""), $0) } ?? ""
        )
    }

    // MARK: - Helpers

    private func starImage(for index: Int) -> Image {
        if let user = userRating {
            // Interactive mode: show solid stars up to user's rating
            return index <= user
                ? Image(systemName: "star.fill")
                : Image(systemName: "star")
        } else {
            // Display mode: fractional fill
            let fraction = rating - Double(index - 1)
            if fraction >= 0.75 {
                return Image(systemName: "star.fill")
            } else if fraction >= 0.25 {
                return Image(systemName: "star.leadinghalf.filled")
            } else {
                return Image(systemName: "star")
            }
        }
    }

    private func starColor(for index: Int) -> Color {
        if let user = userRating {
            return index <= user ? .orange : Color(.systemGray4)
        } else {
            let fraction = rating - Double(index - 1)
            return fraction >= 0.25 ? .orange : Color(.systemGray4)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        StarRatingView(rating: 4.3, userRating: nil)
        StarRatingView(rating: 0, userRating: 3, interactive: true) { star in
            print("Selected: \(star)")
        }
    }
    .padding()
}
