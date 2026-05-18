import SwiftUI
import SwiftData
import PhotosUI

struct RecipeEditorView: View {
    @StateObject private var vm = EditorViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showDiscardAlert = false
    @State private var categories: [RecipeCategory] = []

    private let units = ["г", "кг", "мл", "л", "шт", "ст.л.", "ч.л.", "стакан", "щепотка"]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Form {
                    basicInfoSection
                    coverSection
                    difficultyTimeSection
                    ingredientsSection
                    stepsSection
                    Color.clear.frame(height: 60)
                }

                publishButton
            }
            .navigationTitle(vm.existingRecipeId == nil ? "Новый рецепт" : "Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert(vm.alertMessage ?? "", isPresented: $vm.showAlert) {
                Button("ОК", role: .cancel) {}
            }
            .alert("Выйти без сохранения?", isPresented: $showDiscardAlert) {
                Button("Выйти", role: .destructive) { dismiss() }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Черновик не будет сохранён.")
            }
            .interactiveDismissDisabled(vm.isDirty)
            .onChange(of: vm.coverImageItem) { _, _ in
                Task { await vm.loadCoverImage() }
            }
            .onChange(of: vm.title)              { _, _ in vm.isDirty = true }
            .onChange(of: vm.recipeDescription)  { _, _ in vm.isDirty = true }
            .onChange(of: vm.ingredients.count)  { _, _ in vm.isDirty = true }
            .onChange(of: vm.steps.count)        { _, _ in vm.isDirty = true }
            .onChange(of: vm.isPublished) { _, published in
                if published { dismiss() }
            }
        }
        .task {
            vm.loadLatestDraft(context: modelContext)
            vm.startAutosave(context: modelContext)
            await loadCategories()
        }
        .onDisappear {
            vm.stopAutosave()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Отмена") {
                if vm.isDirty { showDiscardAlert = true } else { dismiss() }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Черновик") {
                vm.saveDraft(to: modelContext)
                vm.isDirty = false
            }
            .tint(.orange)
            .disabled(vm.isLoading)
        }
    }

    // MARK: - Basic info section

    private var basicInfoSection: some View {
        Section("Основная информация") {
            TextField("Название рецепта *", text: $vm.title)
                .onChange(of: vm.title) { _, new in
                    if new.count > 100 { vm.title = String(new.prefix(100)) }
                }

            ZStack(alignment: .topLeading) {
                if vm.recipeDescription.isEmpty {
                    Text("Описание рецепта...")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $vm.recipeDescription)
                    .frame(minHeight: 80)
            }

            Picker("Категория", selection: $vm.selectedCategory) {
                Text("Без категории").tag(Optional<RecipeCategory>.none)
                ForEach(categories) { cat in
                    Text(cat.name).tag(Optional(cat))
                }
            }
        }
    }

    // MARK: - Cover section

    private var coverSection: some View {
        Section("Обложка") {
            if let image = vm.coverImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .listRowInsets(.init(top: 8, leading: 8, bottom: 8, trailing: 8))

                Button("Изменить обложку", role: .none) {}
                    .overlay {
                        PhotosPicker(selection: $vm.coverImageItem, matching: .images) {
                            Color.clear
                        }
                    }
                    .foregroundStyle(.orange)
            } else {
                PhotosPicker(selection: $vm.coverImageItem, matching: .images) {
                    Label("Выбрать фото обложки", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Difficulty & time section

    private var difficultyTimeSection: some View {
        Section("Параметры") {
            Picker("Сложность", selection: $vm.difficulty) {
                ForEach(Difficulty.allCases, id: \.self) { d in
                    Text(d.localizedName).tag(d)
                }
            }
            .pickerStyle(.segmented)

            Stepper(
                "Время: \(vm.cookTimeMin.formattedDuration)",
                value: $vm.cookTimeMin, in: 5...600, step: 5
            )

            Stepper(
                "Порции: \(vm.servings)",
                value: $vm.servings, in: 1...100
            )
        }
    }

    // MARK: - Ingredients section

    private var ingredientsSection: some View {
        Section {
            ForEach($vm.ingredients) { $ingredient in
                HStack(spacing: 8) {
                    TextField("Ингредиент", text: $ingredient.name)
                        .frame(maxWidth: .infinity)

                    TextField("Кол-во", text: $ingredient.amount)
                        .keyboardType(.decimalPad)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)

                    Picker("", selection: $ingredient.unit) {
                        ForEach(units, id: \.self) { u in
                            Text(u).tag(u)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 70)
                }
            }
            .onDelete { vm.ingredients.remove(atOffsets: $0) }
            .onMove  { vm.ingredients.move(fromOffsets: $0, toOffset: $1) }

            Button {
                vm.ingredients.append(DraftIngredient())
            } label: {
                Label("Добавить ингредиент", systemImage: "plus.circle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            HStack {
                Text("Ингредиенты")
                Spacer()
                EditButton()
                    .font(.subheadline)
                    .tint(.orange)
            }
        }
    }

    // MARK: - Steps section

    private var stepsSection: some View {
        Section {
            ForEach(Array($vm.steps.enumerated()), id: \.element.id) { index, $step in
                NavigationLink {
                    StepEditorView(step: $step, stepNumber: index + 1)
                } label: {
                    stepRow(step: step, number: index + 1)
                }
            }
            .onDelete { vm.steps.remove(atOffsets: $0) }
            .onMove  { vm.steps.move(fromOffsets: $0, toOffset: $1) }

            Button {
                vm.steps.append(DraftStep())
            } label: {
                Label("Добавить шаг", systemImage: "plus.circle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            HStack {
                Text("Шаги приготовления")
                Spacer()
                EditButton()
                    .font(.subheadline)
                    .tint(.orange)
            }
        }
    }

    private func stepRow(step: DraftStep, number: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title.isEmpty ? "Шаг \(number)" : step.title)
                    .font(.subheadline)
                    .foregroundStyle(step.title.isEmpty ? .secondary : .primary)

                HStack(spacing: 8) {
                    if !step.photos.isEmpty {
                        Label("\(step.photos.count)", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if step.timerEnabled {
                        let total = step.timerMinutes * 60 + step.timerSeconds
                        Label(total.formattedTimer, systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Publish button

    private var publishButton: some View {
        Button {
            Task { await vm.publish(context: modelContext) }
        } label: {
            Group {
                if vm.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Опубликовать")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(.orange)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .disabled(vm.isLoading)
    }

    // MARK: - Helpers

    private func loadCategories() async {
        do {
            let cats: [RecipeCategory] = try await APIClient.shared.request(.categories)
            categories = cats
        } catch {}
    }
}
