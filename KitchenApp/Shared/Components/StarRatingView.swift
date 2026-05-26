import SwiftUI

// MARK: - Reusable star rating component

/// Displays a 1–5 star rating. Two modes:
///  - Read-only: `StarRatingView(rating: 4.3)` — shows fractional stars
///  - Interactive: `StarRatingView(selected: 3, onSelect: { ... })` — tappable
struct StarRatingView: View {

    // MARK: Stored properties

    private let displayRating: Double
    private let selectedRating: Int
    private let size: CGFloat
    private let interactive: Bool
    private let onSelect: ((Int) -> Void)?

    // MARK: Initialisers

    /// Read-only display mode (supports half-stars)
    init(rating: Double, size: CGFloat = 16) {
        self.displayRating   = rating
        self.selectedRating  = Int(rating.rounded())
        self.size            = size
        self.interactive     = false
        self.onSelect        = nil
    }

    /// Interactive selector mode
    init(selected: Int, size: CGFloat = 32, onSelect: @escaping (Int) -> Void) {
        self.displayRating   = Double(selected)
        self.selectedRating  = selected
        self.size            = size
        self.interactive     = true
        self.onSelect        = onSelect
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: size * 0.18) {
            ForEach(1 ... 5, id: \.self) { star in
                Image(systemName: imageName(for: star))
                    .foregroundStyle(color(for: star))
                    .font(.system(size: size))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard interactive else { return }
                        onSelect?(star)
                    }
                    .accessibilityLabel(
                        "\(star) \(NSLocalizedString("accessibility.stars", value: "звёзд", comment: ""))"
                    )
            }
        }
    }

    // MARK: Helpers

    private func imageName(for star: Int) -> String {
        if interactive {
            return star <= selectedRating ? "star.fill" : "star"
        }
        let filled   = Int(displayRating)
        let fraction = displayRating - Double(filled)
        if star <= filled { return "star.fill" }
        if star == filled + 1 && fraction >= 0.3 { return "star.leadinghalf.filled" }
        return "star"
    }

    private func color(for star: Int) -> Color {
        if interactive {
            return star <= selectedRating ? .orange : Color(.systemGray4)
        }
        let filled   = Int(displayRating)
        let fraction = displayRating - Double(filled)
        if star <= filled                         { return .orange }
        if star == filled + 1 && fraction >= 0.3  { return .orange }
        return Color(.systemGray4)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        StarRatingView(rating: 4.5)
        StarRatingView(rating: 3.0, size: 24)
        StarRatingView(selected: 3, onSelect: { _ in })
    }
    .padding()
}
