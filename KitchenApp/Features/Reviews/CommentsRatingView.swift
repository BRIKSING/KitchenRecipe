import SwiftUI

// MARK: - CommentsRatingView

/// Секция комментариев и оценок для RecipeDetailView.
/// Показывает среднюю оценку, список отзывов с пагинацией
/// и форму добавления нового комментария.
struct CommentsRatingView: View {
    let recipeId: UUID

    @StateObject private var vm = CommentsViewModel()
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            ratingSummaryRow
            Divider()
            commentsList
        }
        .task { await vm.load(recipeId: recipeId) }
        .sheet(isPresented: $showAddSheet) {
            AddCommentSheet(recipeId: recipeId) { comment in
                vm.prepend(comment)
            }
        }
    }

    // MARK: - Section header

    private var sectionHeader: some View {
        HStack {
            Text("Отзывы")
                .font(.headline)
            Spacer()
            Button {
                showAddSheet = true
            } label: {
                Label("Оставить отзыв", systemImage: "square.and.pencil")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }
            .accessibilityLabel("Оставить отзыв о рецепте")
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Rating summary

    @ViewBuilder
    private var ratingSummaryRow: some View {
        if let summary = vm.ratingSummary {
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", summary.average))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("из 5")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    StarRatingView(rating: summary.average, size: 22)
                    Text("\(summary.count) \(pluralReviews(summary.count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 14)
        } else if vm.isLoadingSummary {
            HStack {
                ProgressView()
                    .padding(.horizontal)
                    .padding(.bottom, 14)
                Spacer()
            }
        }
    }

    // MARK: - Comments list

    @ViewBuilder
    private var commentsList: some View {
        if vm.comments.isEmpty && vm.isLoading {
            ForEach(0..<3, id: \.self) { _ in
                CommentSkeletonRow()
                Divider()
            }
        } else if vm.comments.isEmpty && !vm.isLoading {
            Text("Пока нет отзывов. Будьте первым!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        } else {
            LazyVStack(spacing: 0) {
                ForEach(vm.comments) { comment in
                    CommentRow(comment: comment) {
                        Task { await vm.deleteComment(comment, recipeId: recipeId) }
                    }
                    Divider()
                        .padding(.leading, 60)

                    // Пагинация: подгружаем при достижении последнего элемента
                    if comment.id == vm.comments.last?.id && vm.hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .task { await vm.loadNextPage(recipeId: recipeId) }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func pluralReviews(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "отзыв" }
        if mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14) { return "отзыва" }
        return "отзывов"
    }
}

// MARK: - CommentRow

private struct CommentRow: View {
    let comment: RecipeComment
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    private var currentUserId: UUID? {
        guard let idStr = UserDefaults.standard.string(forKey: "currentUserId") else { return nil }
        return UUID(uuidString: idStr)
    }

    private var isOwn: Bool { currentUserId == comment.author.id }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Аватар-заглушка
            ZStack {
                Circle()
                    .fill(avatarColor(for: comment.author.username))
                    .frame(width: 40, height: 40)
                Text(comment.author.username.prefix(1).uppercased())
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.author.username)
                        .font(.subheadline.bold())
                    Spacer()
                    Text(comment.createdAt.shortFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let rating = comment.rating {
                    StarRatingView(rating: Double(rating), size: 13)
                }

                Text(comment.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isOwn {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Удалить комментарий?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Удалить", role: .destructive, action: onDelete)
            Button("Отмена", role: .cancel) {}
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(comment.author.username): \(comment.text)")
    }

    private func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.orange, .blue, .green, .purple, .pink, .teal, .indigo]
        let idx = abs(name.hashValue) % colors.count
        return colors[idx]
    }
}

// MARK: - Skeleton placeholder

private struct CommentSkeletonRow: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray6))
                    .frame(width: 200, height: 14)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .redacted(reason: .placeholder)
        .shimmering()
    }
}

// MARK: - AddCommentSheet

struct AddCommentSheet: View {
    let recipeId: UUID
    let onAdded: (RecipeComment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var selectedRating: Int = 0
    @State private var isSubmitting = false
    @FocusState private var isTextFocused: Bool

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    interactiveStars
                } header: {
                    Text("Ваша оценка (необязательно)")
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Поделитесь впечатлениями о рецепте…")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $text)
                            .focused($isTextFocused)
                            .frame(minHeight: 100)
                    }
                } header: {
                    Text("Комментарий")
                }
            }
            .navigationTitle("Новый отзыв")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Опубликовать") {
                            Task { await submit() }
                        }
                        .bold()
                        .disabled(!canSubmit || isSubmitting)
                    }
                }
            }
            .onAppear { isTextFocused = true }
        }
    }

    // MARK: - Interactive star rating

    private var interactiveStars: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= selectedRating ? "star.fill" : "star")
                    .font(.system(size: 28))
                    .foregroundStyle(star <= selectedRating ? .orange : Color(.systemGray4))
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            selectedRating = (selectedRating == star) ? 0 : star
                        }
                    }
                    .accessibilityLabel("\(star) звезд\(star == 1 ? "а" : star < 5 ? "ы" : "")")
                    .accessibilityAddTraits(star <= selectedRating ? .isSelected : [])
            }
            Spacer()
            if selectedRating > 0 {
                Text(ratingLabel(selectedRating))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
    }

    private func ratingLabel(_ r: Int) -> String {
        switch r {
        case 1: return "Плохо"
        case 2: return "Так себе"
        case 3: return "Нормально"
        case 4: return "Хорошо"
        case 5: return "Отлично!"
        default: return ""
        }
    }

    // MARK: - Submit

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = AddCommentRequest(
            text: trimmed,
            rating: selectedRating > 0 ? selectedRating : nil
        )

        do {
            let comment: RecipeComment = try await APIClient.shared.request(
                .addComment(recipeId: recipeId),
                body: body
            )
            onAdded(comment)
            dismiss()
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }
}

// MARK: - StarRatingView (reusable, read-only)

struct StarRatingView: View {
    let rating: Double   // 0...5, дробные поддерживаются
    var size: CGFloat = 16

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                starImage(for: index)
                    .font(.system(size: size))
                    .foregroundStyle(index <= Int(rating.rounded()) ? Color.orange : Color(.systemGray4))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Оценка: \(String(format: "%.1f", rating)) из 5")
    }

    private func starImage(for index: Int) -> Image {
        let threshold = Double(index) - 0.5
        if rating >= Double(index) {
            return Image(systemName: "star.fill")
        } else if rating >= threshold {
            return Image(systemName: "star.leadinghalf.filled")
        } else {
            return Image(systemName: "star")
        }
    }
}

// MARK: - CommentsViewModel

@MainActor
final class CommentsViewModel: ObservableObject {
    @Published var comments: [RecipeComment] = []
    @Published var ratingSummary: RecipeRatingSummary?
    @Published var isLoading = false
    @Published var isLoadingSummary = false
    @Published var hasMore = true

    private var currentPage = 1
    private let api = APIClient.shared

    func load(recipeId: UUID) async {
        async let commentsTask: Void = loadFirstPage(recipeId: recipeId)
        async let summaryTask: Void = loadSummary(recipeId: recipeId)
        _ = await (commentsTask, summaryTask)
    }

    private func loadFirstPage(recipeId: UUID) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        currentPage = 1
        do {
            let page: PaginatedResponse<RecipeComment> = try await api.request(
                .comments(recipeId: recipeId, page: 1)
            )
            comments = page.data
            hasMore = page.hasMore
            currentPage = 2
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }

    func loadNextPage(recipeId: UUID) async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let page: PaginatedResponse<RecipeComment> = try await api.request(
                .comments(recipeId: recipeId, page: currentPage)
            )
            comments += page.data
            hasMore = page.hasMore
            currentPage += 1
        } catch {
            // Non-fatal: просто не дозагрузили следующую страницу
        }
    }

    private func loadSummary(recipeId: UUID) async {
        isLoadingSummary = true
        defer { isLoadingSummary = false }

        do {
            let summary: RecipeRatingSummary = try await api.request(.ratingSummary(recipeId: recipeId))
            ratingSummary = summary
        } catch {
            // Non-fatal: оценок может не быть
        }
    }

    func prepend(_ comment: RecipeComment) {
        comments.insert(comment, at: 0)
        // Обновляем среднюю оценку локально, если пришла с рейтингом
        if let newRating = comment.rating {
            let oldCount = ratingSummary?.count ?? 0
            let oldAvg = ratingSummary?.average ?? 0
            let newCount = oldCount + 1
            let newAvg = (oldAvg * Double(oldCount) + Double(newRating)) / Double(newCount)
            ratingSummary = RecipeRatingSummary(average: newAvg, count: newCount)
        }
    }

    func deleteComment(_ comment: RecipeComment, recipeId: UUID) async {
        do {
            struct Empty: Decodable {}
            let _: Empty = try await api.request(.deleteComment(recipeId: recipeId, commentId: comment.id))
            comments.removeAll { $0.id == comment.id }
            // Пересчёт рейтинга, если был
            if let rating = comment.rating, let summary = ratingSummary, summary.count > 1 {
                let newCount = summary.count - 1
                let newAvg = (summary.average * Double(summary.count) - Double(rating)) / Double(newCount)
                ratingSummary = RecipeRatingSummary(average: max(0, newAvg), count: newCount)
            } else if comment.rating != nil {
                ratingSummary = RecipeRatingSummary(average: 0, count: 0)
            }
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }
}

// MARK: - Shimmer effect modifier

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.4),
                        Color.white.opacity(0)
                    ]),
                    startPoint: .init(x: phase - 0.3, y: 0.5),
                    endPoint: .init(x: phase + 0.3, y: 0.5)
                )
                .blendMode(.plusLighter)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

extension View {
    fileprivate func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Date helper

private extension Date {
    var shortFormatted: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) {
            return "Сегодня"
        } else if cal.isDateInYesterday(self) {
            return "Вчера"
        } else {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .none
            fmt.locale = Locale.current
            return fmt.string(from: self)
        }
    }
}
