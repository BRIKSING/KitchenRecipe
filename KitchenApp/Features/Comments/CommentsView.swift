import SwiftUI

// MARK: - CommentsView

struct CommentsView: View {
    let recipeId: UUID

    @State private var viewModel = CommentsViewModel()
    @State private var newCommentText = ""
    @State private var pendingRating: Int? = nil
    @State private var ratingSubmitted = false
    @State private var deleteTarget: Comment?
    @State private var showDeleteAlert = false
    @FocusState private var commentFieldFocused: Bool

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    // Rating section
                    ratingSectionView

                    // Comments list
                    commentsSectionView
                }
                .listStyle(.insetGrouped)
                .refreshable { await viewModel.loadAll(recipeId: recipeId) }

                // Comment input bar (pinned to bottom)
                if APIClient.shared.isAuthenticated {
                    commentInputBar
                }
            }
            .navigationTitle(NSLocalizedString("comments.title", value: "Отзывы", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Закрыть", comment: "")) { dismiss() }
                        .tint(.orange)
                }
            }
            .alert(NSLocalizedString("comments.delete_confirm", value: "Удалить комментарий?", comment: ""), isPresented: $showDeleteAlert) {
                Button(NSLocalizedString("Удалить", comment: ""), role: .destructive) {
                    if let target = deleteTarget {
                        Task { try? await viewModel.deleteComment(recipeId: recipeId, commentId: target.id) }
                    }
                }
                Button(NSLocalizedString("Отмена", comment: ""), role: .cancel) {}
            }
        }
        .task { await viewModel.loadAll(recipeId: recipeId) }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Rating section

    @ViewBuilder
    private var ratingSectionView: some View {
        Section {
            VStack(spacing: 16) {
                // Summary row
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        if let r = viewModel.rating, r.count > 0 {
                            Text(String(format: "%.1f", r.average))
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                            StarRatingView(rating: r.average, userRating: nil, starSize: 16)
                            Text(
                                String(
                                    format: NSLocalizedString("comments.ratings_count", value: "%d оценок", comment: ""),
                                    r.count
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else if viewModel.isLoadingRating {
                            ProgressView()
                        } else {
                            Text(NSLocalizedString("comments.no_ratings_yet", value: "Нет оценок", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 70)

                    // User rating picker
                    if APIClient.shared.isAuthenticated {
                        VStack(spacing: 8) {
                            Text(NSLocalizedString("comments.your_rating", value: "Ваша оценка", comment: ""))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            let displayRating = pendingRating ?? viewModel.rating?.userRating ?? 0
                            StarRatingView(
                                rating: Double(displayRating),
                                userRating: displayRating > 0 ? displayRating : nil,
                                starSize: 28,
                                interactive: true
                            ) { star in
                                pendingRating = star
                            }

                            if let pending = pendingRating,
                               pending != (viewModel.rating?.userRating ?? 0) {
                                Button {
                                    submitRating()
                                } label: {
                                    if viewModel.isSubmittingRating {
                                        ProgressView()
                                            .frame(height: 28)
                                    } else {
                                        Text(NSLocalizedString("comments.submit_rating", value: "Отправить", comment: ""))
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(Color.orange)
                                            .clipShape(Capsule())
                                    }
                                }
                                .disabled(viewModel.isSubmittingRating)
                                .transition(.scale.combined(with: .opacity))
                            }

                            if ratingSubmitted {
                                Label(
                                    NSLocalizedString("comments.rating_saved", value: "Сохранено!", comment: ""),
                                    systemImage: "checkmark.circle.fill"
                                )
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                                .transition(.opacity)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.2), value: pendingRating)
                        .animation(.easeInOut(duration: 0.2), value: ratingSubmitted)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Comments section

    @ViewBuilder
    private var commentsSectionView: some View {
        Section {
            if viewModel.isLoadingComments && viewModel.comments.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if viewModel.comments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(NSLocalizedString("comments.empty", value: "Пока нет комментариев.\nБудьте первым!", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.comments) { comment in
                    CommentRowView(
                        comment: comment,
                        canDelete: canDelete(comment: comment),
                        onDelete: {
                            deleteTarget = comment
                            showDeleteAlert = true
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                // Load more trigger
                if viewModel.hasMore {
                    HStack {
                        Spacer()
                        if viewModel.isLoadingComments {
                            ProgressView()
                        } else {
                            Button(NSLocalizedString("comments.load_more", value: "Загрузить ещё", comment: "")) {
                                Task { await viewModel.loadMore(recipeId: recipeId) }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .onAppear {
                        Task { await viewModel.loadMore(recipeId: recipeId) }
                    }
                }
            }
        } header: {
            Text(
                String(
                    format: NSLocalizedString("comments.section_header", value: "Комментарии (%d)", comment: ""),
                    viewModel.rating?.count ?? viewModel.comments.count
                )
            )
        }
    }

    // MARK: - Comment input bar

    private var commentInputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                TextField(
                    NSLocalizedString("comments.placeholder", value: "Написать комментарий…", comment: ""),
                    text: $newCommentText,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .focused($commentFieldFocused)
                .submitLabel(.send)
                .onSubmit { sendComment() }

                Button {
                    sendComment()
                } label: {
                    if viewModel.isSubmittingComment {
                        ProgressView()
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .orange)
                    }
                }
                .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSubmittingComment)
                .accessibilityLabel(NSLocalizedString("comments.send_button", value: "Отправить", comment: ""))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Actions

    private func sendComment() {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        commentFieldFocused = false
        let text = trimmed
        newCommentText = ""
        Task {
            do {
                try await viewModel.postComment(recipeId: recipeId, text: text)
            } catch {
                ErrorBannerState.shared.show(error)
                newCommentText = text   // restore on failure
            }
        }
    }

    private func submitRating() {
        guard let stars = pendingRating else { return }
        Task {
            do {
                try await viewModel.rate(recipeId: recipeId, stars: stars)
                withAnimation { ratingSubmitted = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { ratingSubmitted = false }
                }
            } catch {
                ErrorBannerState.shared.show(error)
            }
        }
    }

    private func canDelete(comment: Comment) -> Bool {
        // Allow deletion if current user is the author
        // We compare by username stored in UserDefaults (set on login)
        guard let savedUsername = UserDefaults.standard.string(forKey: "currentUsername") else { return false }
        return comment.author.username == savedUsername
    }
}

// MARK: - Preview

#Preview {
    CommentsView(recipeId: UUID())
}
