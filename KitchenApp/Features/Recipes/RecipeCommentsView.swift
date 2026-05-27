import SwiftUI

// MARK: - RecipeCommentsView

/// Полный экран комментариев и отзывов для рецепта.
struct RecipeCommentsView: View {
    let recipeId: UUID
    let recipeTitle: String

    @StateObject private var vm = CommentsViewModel()
    @State private var showAddComment = false

    var body: some View {
        Group {
            if vm.isLoading && vm.comments.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.comments.isEmpty {
                emptyState
            } else {
                commentsList
            }
        }
        .navigationTitle(NSLocalizedString("comments.title", value: "Отзывы", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddComment = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.orange)
                }
                .accessibilityLabel(NSLocalizedString("comments.add_btn_a11y", value: "Добавить отзыв", comment: ""))
            }
        }
        .sheet(isPresented: $showAddComment) {
            AddCommentSheet(recipeId: recipeId, recipeTitle: recipeTitle) {
                Task { await vm.loadInitial(recipeId: recipeId) }
            }
        }
        .task { await vm.loadInitial(recipeId: recipeId) }
    }

    // MARK: - Comments list

    private var commentsList: some View {
        List {
            // Rating header
            if let stats = vm.ratingStats, stats.count > 0 {
                ratingHeader(stats)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            ForEach(vm.comments) { comment in
                CommentRowView(comment: comment) {
                    Task { await vm.deleteComment(recipeId: recipeId, commentId: comment.id) }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // Load more
            if vm.hasMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onAppear {
                    Task { await vm.loadMore(recipeId: recipeId) }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await vm.loadInitial(recipeId: recipeId) }
    }

    // MARK: - Rating header

    private func ratingHeader(_ stats: RatingStats) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", stats.average))
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(.orange)
                    Text(NSLocalizedString("comments.out_of_5", value: "из 5", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    StarRatingView(rating: stats.average, starSize: 24)
                    Text(ratingsCountLabel(stats.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("comments.empty_title", value: "Пока нет отзывов", comment: ""))
                .font(.headline)
            Text(NSLocalizedString("comments.empty_subtitle", value: "Станьте первым, кто оставит отзыв!", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showAddComment = true
            } label: {
                Text(NSLocalizedString("comments.write_first", value: "Написать отзыв", comment: ""))
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers

    private func ratingsCountLabel(_ count: Int) -> String {
        let format = NSLocalizedString("comments.ratings_count", value: "%d оценок", comment: "")
        return String(format: format, count)
    }
}

// MARK: - CommentRowView

private struct CommentRowView: View {
    let comment: Comment
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Author + date
            HStack(spacing: 8) {
                Circle()
                    .fill(avatarColor(for: comment.author.username))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(String(comment.author.username.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.author.username)
                        .font(.subheadline.bold())
                    Text(comment.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let rating = comment.rating {
                    StarRatingView(rating: Double(rating), starSize: 14)
                }
            }

            // Comment text
            Text(comment.text)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label(NSLocalizedString("Удалить", value: "Удалить", comment: ""), systemImage: "trash")
            }
        }
        .confirmationDialog(
            NSLocalizedString("comments.delete_confirm_title", value: "Удалить отзыв?", comment: ""),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Удалить", value: "Удалить", comment: ""), role: .destructive, action: onDelete)
        }
    }

    private func avatarColor(for username: String) -> Color {
        let colors: [Color] = [.orange, .blue, .green, .purple, .pink, .teal]
        let index = abs(username.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - AddCommentSheet

/// Лист для добавления текстового комментария с опциональной оценкой.
private struct AddCommentSheet: View {
    let recipeId: UUID
    let recipeTitle: String
    let onSuccess: () -> Void

    @StateObject private var vm = CommentsViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var selectedRating: Int = 0

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StarRatingView(rating: Double(selectedRating), starSize: 36, isInteractive: true) { star in
                        selectedRating = star
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } header: {
                    Text(NSLocalizedString("comments.your_rating", value: "Ваша оценка (необязательно)", comment: ""))
                }

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                } header: {
                    Text(NSLocalizedString("comments.comment_header", value: "Комментарий", comment: ""))
                } footer: {
                    Text(NSLocalizedString("comments.comment_footer", value: "Расскажите, что получилось и что можно улучшить.", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("comments.add_title", value: "Новый отзыв", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Отмена", value: "Отмена", comment: "")) { dismiss() }
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
        }
    }

    private func submit() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let success = await vm.addComment(
            recipeId: recipeId,
            text: trimmed,
            rating: selectedRating > 0 ? selectedRating : nil
        )
        if success {
            onSuccess()
            dismiss()
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        RecipeCommentsView(recipeId: UUID(), recipeTitle: "Паста карбонара")
    }
}
#endif
