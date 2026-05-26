import SwiftUI

// MARK: - Recipe Comments Section

struct RecipeCommentsSectionView: View {
    let recipeId: UUID
    @ObservedObject var viewModel: CommentsRatingViewModel

    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // MARK: Header
            HStack {
                Text(NSLocalizedString("comments.title", value: "Комментарии", comment: ""))
                    .font(.headline)
                Spacer()
                if !viewModel.comments.isEmpty {
                    Text("\(viewModel.comments.count)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Input (authenticated users only)
            if APIClient.shared.isAuthenticated {
                commentInputView
            }

            // MARK: Comments list
            if viewModel.isLoadingComments && viewModel.comments.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 8)

            } else if viewModel.comments.isEmpty {
                Text(
                    NSLocalizedString(
                        "comments.empty",
                        value: "Будьте первым, кто оставит комментарий!",
                        comment: ""
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)

            } else {
                ForEach(viewModel.comments) { comment in
                    commentRow(comment)
                        .contextMenu {
                            if APIClient.shared.isAuthenticated {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteComment(
                                            recipeId: recipeId,
                                            commentId: comment.id
                                        )
                                    }
                                } label: {
                                    Label(
                                        NSLocalizedString("Удалить", value: "Удалить", comment: ""),
                                        systemImage: "trash"
                                    )
                                }
                            }
                        }
                }

                // MARK: Load more
                if viewModel.hasMoreComments {
                    Button {
                        Task { await viewModel.loadComments(recipeId: recipeId) }
                    } label: {
                        Group {
                            if viewModel.isLoadingComments {
                                ProgressView()
                            } else {
                                Text(
                                    NSLocalizedString(
                                        "comments.load_more",
                                        value: "Загрузить ещё",
                                        comment: ""
                                    )
                                )
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding()
        .task {
            await viewModel.loadComments(recipeId: recipeId, reset: true)
        }
    }

    // MARK: - Comment input

    private var commentInputView: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                NSLocalizedString(
                    "comments.placeholder",
                    value: "Написать комментарий...",
                    comment: ""
                ),
                text: $viewModel.commentText,
                axis: .vertical
            )
            .lineLimit(1 ... 4)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .focused($isInputFocused)
            .submitLabel(.send)
            .onSubmit {
                Task { await viewModel.sendComment(recipeId: recipeId) }
            }

            // Send button
            Button {
                Task { await viewModel.sendComment(recipeId: recipeId) }
            } label: {
                if viewModel.isSendingComment {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.orange)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            viewModel.commentText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color(.systemGray4)
                                : Color.orange
                        )
                }
            }
            .disabled(
                viewModel.commentText.trimmingCharacters(in: .whitespaces).isEmpty
                    || viewModel.isSendingComment
            )
            .animation(.easeInOut(duration: 0.15), value: viewModel.commentText.isEmpty)
        }
    }

    // MARK: - Comment row

    private func commentRow(_ comment: RecipeComment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Avatar (initial letter)
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Text(comment.author.username.prefix(1).uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(comment.author.username)
                        .font(.subheadline.bold())
                    Text(comment.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            Text(comment.text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
        }
        .padding(.vertical, 2)
    }
}
