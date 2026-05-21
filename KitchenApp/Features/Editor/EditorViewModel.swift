import Foundation
import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Mutable models for the editor

struct DraftIngredient: Identifiable {
    var id = UUID()
    var name = ""
    var amount = ""
    var unit = "г"
}

struct DraftStep: Identifiable {
    var id = UUID()
    var title = ""
    var description = ""
    var timerEnabled = false
    var timerMinutes: Int = 0
    var timerSeconds: Int = 0
    var photos: [UIImage] = []
}

// MARK: - Private API bodies

private struct StepBody: Encodable {
    let title: String
    let description: String
    let sortOrder: Int
    let timerSec: Int?

    enum CodingKeys: String, CodingKey {
        case title, description
        case sortOrder = "sort_order"
        case timerSec  = "timer_sec"
    }
}

private struct RecipeIDResponse: Decodable { let id: UUID }

private struct EmptyResponse: Decodable {
    init(from decoder: Decoder) throws {}
}

// MARK: - EditorViewModel

@MainActor
final class EditorViewModel: ObservableObject {

    // MARK: Form state

    @Published var title = ""
    @Published var recipeDescription = ""
    @Published var selectedCategory: RecipeCategory?
    @Published var difficulty: Difficulty = .easy
    @Published var cookTimeMin = 30
    @Published var servings = 2
    @Published var coverImageItem: PhotosPickerItem?
    @Published var coverImage: UIImage?
    @Published var ingredients: [DraftIngredient] = [DraftIngredient()]
    @Published var steps: [DraftStep] = [DraftStep()]
    @Published var selectedTagIds: Set<UUID> = []
    @Published var availableTags: [Tag] = []

    // MARK: UI state

    @Published var isLoading = false
    @Published var isDirty = false
    @Published var isPublished = false
    @Published var alertMessage: String?
    @Published var showAlert = false

    let existingRecipeId: UUID?
    private var draftModelId: UUID?
    private var autosaveTask: Task<Void, Never>?
    private let api = APIClient.shared

    init(existingRecipeId: UUID? = nil) {
        self.existingRecipeId = existingRecipeId
    }

    // MARK: - Tags

    func loadTags(query: String? = nil) async {
        do {
            let tags: [Tag] = try await api.request(.tags(q: query))
            availableTags = tags
        } catch {}
    }

    func toggleTag(_ tag: Tag) {
        if selectedTagIds.contains(tag.id) {
            selectedTagIds.remove(tag.id)
        } else {
            selectedTagIds.insert(tag.id)
        }
        isDirty = true
    }

    // MARK: - Cover image

    func loadCoverImage() async {
        guard let item = coverImageItem,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        coverImage = image.cropped(toAspect: 16.0 / 9.0)
        isDirty = true
    }

    // MARK: - Validation

    var validationError: String? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Введите название рецепта"
        }
        let hasStep = steps.contains { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        if !hasStep {
            return "Добавьте хотя бы один шаг с названием"
        }
        return nil
    }

    // MARK: - Autosave

    func startAutosave(context: ModelContext) {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                await self?.saveDraft(to: context)
            }
        }
    }

    func stopAutosave() {
        autosaveTask?.cancel()
        autosaveTask = nil
    }

    func saveDraft(to context: ModelContext) {
        let enc = JSONEncoder()
        let draft = fetchOrCreateDraft(context: context)

        draft.title            = title
        draft.recipeDescription = recipeDescription
        draft.categoryId       = selectedCategory?.id
        draft.difficulty       = difficulty.rawValue
        draft.cookTimeMin      = cookTimeMin
        draft.servings         = servings
        draft.coverImageData   = coverImage?.jpegData(compressionQuality: 0.8)
        draft.updatedAt        = Date()

        struct SI: Encodable { let name, amount, unit: String }
        draft.ingredientsJSON = try? enc.encode(
            ingredients.map { SI(name: $0.name, amount: $0.amount, unit: $0.unit) }
        )

        struct SS: Encodable { let title, description: String; let timerEnabled: Bool; let timerMin, timerSec: Int }
        draft.stepsJSON = try? enc.encode(
            steps.map { SS(title: $0.title, description: $0.description,
                           timerEnabled: $0.timerEnabled, timerMin: $0.timerMinutes, timerSec: $0.timerSeconds) }
        )

        struct ST: Encodable { let id: String }
        draft.tagsJSON = try? enc.encode(Array(selectedTagIds).map { ST(id: $0.uuidString) })

        try? context.save()
    }

    private func fetchOrCreateDraft(context: ModelContext) -> DraftRecipe {
        let descriptor = FetchDescriptor<DraftRecipe>()
        let all = (try? context.fetch(descriptor)) ?? []
        if let id = draftModelId, let found = all.first(where: { $0.id == id }) { return found }
        let draft = DraftRecipe()
        context.insert(draft)
        draftModelId = draft.id
        return draft
    }

    func loadLatestDraft(context: ModelContext) {
        let descriptor = FetchDescriptor<DraftRecipe>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let draft = (try? context.fetch(descriptor))?.first else { return }
        draftModelId       = draft.id
        title              = draft.title
        recipeDescription  = draft.recipeDescription
        difficulty         = Difficulty(rawValue: draft.difficulty) ?? .easy
        cookTimeMin        = draft.cookTimeMin
        servings           = draft.servings
        if let data = draft.coverImageData { coverImage = UIImage(data: data) }

        struct SI: Decodable { let name, amount, unit: String }
        if let data = draft.ingredientsJSON,
           let arr = try? JSONDecoder().decode([SI].self, from: data), !arr.isEmpty {
            ingredients = arr.map { DraftIngredient(name: $0.name, amount: $0.amount, unit: $0.unit) }
        }

        struct SS: Decodable { let title, description: String; let timerEnabled: Bool; let timerMin, timerSec: Int }
        if let data = draft.stepsJSON,
           let arr = try? JSONDecoder().decode([SS].self, from: data), !arr.isEmpty {
            steps = arr.map {
                DraftStep(title: $0.title, description: $0.description,
                          timerEnabled: $0.timerEnabled, timerMinutes: $0.timerMin, timerSeconds: $0.timerSec)
            }
        }

        struct ST: Decodable { let id: String }
        if let data = draft.tagsJSON,
           let arr = try? JSONDecoder().decode([ST].self, from: data) {
            selectedTagIds = Set(arr.compactMap { UUID(uuidString: $0.id) })
        }
    }

    func deleteDraft(context: ModelContext) {
        guard let id = draftModelId else { return }
        let descriptor = FetchDescriptor<DraftRecipe>()
        if let draft = (try? context.fetch(descriptor))?.first(where: { $0.id == id }) {
            context.delete(draft)
            try? context.save()
        }
        draftModelId = nil
    }

    // MARK: - Publish

    func publish(context: ModelContext) async {
        if let err = validationError {
            alertMessage = err
            showAlert = true
            return
        }
        await performPublish(context: context)
    }

    private func performPublish(context: ModelContext) async {
        isLoading = true
        defer { isLoading = false }
        do {
            // 1. Upload cover image
            if let image = coverImage, let data = image.jpegData(compressionQuality: 0.85) {
                let _: UploadResponse = try await api.upload(imageData: data, to: .uploadImage)
            }

            // 2. Create recipe skeleton
            let req = RecipeCreateRequest(
                title: title.trimmingCharacters(in: .whitespaces),
                description: recipeDescription.isEmpty ? nil : recipeDescription,
                categoryId: selectedCategory?.id,
                difficulty: difficulty.rawValue,
                cookTimeMin: cookTimeMin,
                servings: servings,
                tagIds: selectedTagIds.isEmpty ? nil : Array(selectedTagIds)
            )
            let created: RecipeIDResponse = try await api.request(.createRecipe(req), body: req)
            let recipeId = created.id

            // 3. Create steps
            for (i, step) in steps.enumerated() {
                guard !step.title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                let timerSec: Int? = step.timerEnabled ? (step.timerMinutes * 60 + step.timerSeconds) : nil
                let body = StepBody(title: step.title, description: step.description,
                                    sortOrder: i + 1, timerSec: timerSec)
                let _: EmptyResponse = try await api.request(.createStep(recipeId: recipeId), body: body)
            }

            // 4. Publish
            let _: EmptyResponse = try await api.request(.publishRecipe(recipeId))

            deleteDraft(context: context)
            isPublished = true
            isDirty = false
        } catch {
            ErrorBannerState.shared.show(error)
        }
    }
}
