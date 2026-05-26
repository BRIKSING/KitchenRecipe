import SwiftUI

// MARK: - Recipe Rating Section

struct RecipeRatingSectionView: View {
    let recipeId: UUID
    @ObservedObject var viewModel: CommentsRatingViewModel

    @State private var pendingRating: Int = 0
    @State private var isSubmitting  = false

    // The value currently shown in the star selector
    private var effectiveSelected: Int {
        pendingRating > 0 ? pendingRating : (viewModel.rating?.userRating ?? 0)
    }

    // Whether the user has changed the rating and needs to save
    private var isDirty: Bool {
        pendingRating > 0 && pendingRating != viewModel.rating?.userRating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // MARK: Header
            Text(NSLocalizedString("comments.ratings.title", value: "Оценки", comment: ""))
                .font(.headline)

            if let rating = viewModel.rating {
                averageBlock(rating)
                Divider()
            }

            // MARK: User rating picker
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    viewModel.rating?.userRating != nil
                        ? NSLocalizedString("comments.your_rating", value: "Ваша оценка", comment: "")
                        : NSLocalizedString("comments.rate_this",   value: "Оцените рецепт", comment: "")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                StarRatingView(
                    selected: effectiveSelected,
                    size: 30,
                    onSelect: { star in
                        withAnimation(.easeInOut(duration: 0.12)) { pendingRating = star }
                    }
                )

                if isDirty || (pendingRating > 0 && viewModel.rating?.userRating == nil) {
                    saveButton
                }
            }
        }
        .padding()
        .task { await viewModel.loadRating(recipeId: recipeId) }
    }

    // MARK: - Average block

    private func averageBlock(_ r: RecipeRating) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", r.averageRating))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Text("/ 5")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                StarRatingView(rating: r.averageRating)
                Text(ratingsLabel(r.totalRatings))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Save button

    private var saveButton: some View {
        Button {
            let stars = pendingRating
            Task {
                isSubmitting = true
                await viewModel.submitRating(recipeId: recipeId, stars: stars)
                isSubmitting = false
                withAnimation { pendingRating = 0 }
            }
        } label: {
            HStack(spacing: 6) {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                }
                Text(NSLocalizedString("comments.submit_rating", value: "Сохранить оценку", comment: ""))
            }
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.orange)
            .clipShape(Capsule())
        }
        .disabled(isSubmitting)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    // MARK: - Helpers

    private func ratingsLabel(_ count: Int) -> String {
        let word = ratingsWord(count)
        let fmt  = NSLocalizedString("comments.ratings_format", value: "%d %@", comment: "e.g. '12 оценок'")
        return String(format: fmt, count, word)
    }

    private func ratingsWord(_ count: Int) -> String {
        let mod100 = count % 100
        let mod10  = count % 10
        if mod100 >= 11 && mod100 <= 19 {
            return NSLocalizedString("comments.ratings_many", value: "оценок", comment: "")
        }
        switch mod10 {
        case 1:       return NSLocalizedString("comments.ratings_one",  value: "оценка",  comment: "")
        case 2, 3, 4: return NSLocalizedString("comments.ratings_few",  value: "оценки",  comment: "")
        default:      return NSLocalizedString("comments.ratings_many", value: "оценок",  comment: "")
        }
    }
}
