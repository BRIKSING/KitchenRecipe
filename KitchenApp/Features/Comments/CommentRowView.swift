import SwiftUI

// MARK: - CommentRowView

struct CommentRowView: View {
    let comment: Comment
    var canDelete: Bool = false
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar — initials circle
            avatarView

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.author.username)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(comment.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(comment.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canDelete, let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(NSLocalizedString("Удалить", comment: ""), systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(comment.author.username): \(comment.text)")
    }

    // MARK: - Avatar

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: comment.author.username))
                .frame(width: 38, height: 38)
            Text(initials(for: comment.author.username))
                .font(.subheadline.bold())
                .foregroundStyle(.white)
        }
    }

    // MARK: - Helpers

    private func initials(for name: String) -> String {
        let parts = name.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    private func avatarColor(for name: String) -> Color {
        let palette: [Color] = [
            .orange, .blue, .purple, .green, .teal, .indigo, .pink, .brown
        ]
        let index = abs(name.hashValue) % palette.count
        return palette[index]
    }
}

// MARK: - Preview

#Preview {
    List {
        CommentRowView(
            comment: Comment(
                id: UUID(),
                author: CommentAuthor(id: UUID(), username: "Анна К."),
                text: "Отличный рецепт! Паста получилась просто идеальной, спасибо!",
                createdAt: Date().addingTimeInterval(-3600)
            ),
            canDelete: true,
            onDelete: {}
        )
        CommentRowView(
            comment: Comment(
                id: UUID(),
                author: CommentAuthor(id: UUID(), username: "mike_chef"),
                text: "Добавил чуть больше чеснока — вкус стал ещё насыщеннее.",
                createdAt: Date().addingTimeInterval(-86400)
            )
        )
    }
    .listStyle(.plain)
}
