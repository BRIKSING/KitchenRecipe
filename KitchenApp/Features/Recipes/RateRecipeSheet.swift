import SwiftUI

// MARK: - RateRecipeSheet

/// Лист для оценки рецепта: выбор звёзд + опциональный текстовый отзыв.
/// Появляется после завершения CookingSessionView или из RecipeDetailView.
struct RateRecipeSheet: View {
    let recipeId: UUID
    let recipeTitle: String
    var onDismiss: (() -> Void)?

    @StateObject private var vm = CommentsViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRating: Int = 0
    @State private var commentText: String = ""
    @State private var includeComment: Bool = false
    @State private var didSubmit = false

    private var canSubmit: Bool {
        selectedRating > 0 && !vm.isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.orange)

                        Text(NSLocalizedString("comments.rate_title", value: "Оцените рецепт", comment: ""))
                            .font(.title2.bold())

                        Text(recipeTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Stars
                    VStack(spacing: 10) {
                        StarRatingView(
                            rating: Double(selectedRating),
                            starSize: 44,
                            isInteractive: true
                        ) { star in
                            selectedRating = star
                        }

                        if selectedRating > 0 {
                            Text(ratingLabel(for: selectedRating))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: selectedRating)

                    // Toggle comment
                    Toggle(
                        NSLocalizedString("comments.add_comment_toggle", value: "Добавить текстовый отзыв", comment: ""),
                        isOn: $includeComment.animation(.easeInOut(duration: 0.2))
                    )
                    .tint(.orange)
                    .padding(.horizontal)

                    if includeComment {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(NSLocalizedString("comments.your_review", value: "Ваш отзыв", comment: ""))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            TextEditor(text: $commentText)
                                .frame(minHeight: 100)
                                .padding(8)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                                .overlay(alignment: .topLeading) {
                                    if commentText.isEmpty {
                                        Text(NSLocalizedString("comments.placeholder", value: "Расскажите о своём опыте…", comment: ""))
                                            .foregroundStyle(.secondary.opacity(0.6))
                                            .font(.body)
                                            .padding(.top, 16)
                                            .padding(.leading, 24)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Отмена", value: "Отмена", comment: "")) {
                        dismiss()
                        onDismiss?()
                    }
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if vm.isSubmitting {
                            ProgressView().tint(.orange)
                        } else {
                            Text(NSLocalizedString("comments.submit", value: "Отправить", comment: ""))
                                .bold()
                                .foregroundStyle(canSubmit ? Color.orange : Color.secondary)
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .overlay {
                if didSubmit {
                    successOverlay
                }
            }
        }
    }

    // MARK: - Success overlay

    private var successOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundStyle(Color.orange)
            Text(NSLocalizedString("comments.thanks", value: "Спасибо за оценку!", comment: ""))
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .transition(.opacity)
    }

    // MARK: - Logic

    private func submit() async {
        guard selectedRating > 0 else { return }

        let text = includeComment ? commentText.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let success: Bool

        if !text.isEmpty {
            success = await vm.addComment(recipeId: recipeId, text: text, rating: selectedRating)
        } else {
            success = await vm.rateRecipe(recipeId: recipeId, rating: selectedRating)
        }

        if success {
            withAnimation(.easeInOut(duration: 0.3)) { didSubmit = true }
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            dismiss()
            onDismiss?()
        }
    }

    private func ratingLabel(for stars: Int) -> String {
        switch stars {
        case 1: return NSLocalizedString("comments.rating1", value: "Плохо", comment: "")
        case 2: return NSLocalizedString("comments.rating2", value: "Терпимо", comment: "")
        case 3: return NSLocalizedString("comments.rating3", value: "Нормально", comment: "")
        case 4: return NSLocalizedString("comments.rating4", value: "Хорошо", comment: "")
        case 5: return NSLocalizedString("comments.rating5", value: "Отлично!", comment: "")
        default: return ""
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    RateRecipeSheet(recipeId: UUID(), recipeTitle: "Паста карбонара")
}
#endif
