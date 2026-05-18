import SwiftUI
import PhotosUI

struct StepEditorView: View {
    @Binding var step: DraftStep
    let stepNumber: Int

    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        Form {
            basicSection
            photosSection
            timerSection
        }
        .navigationTitle("Шаг \(stepNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItems) { _, newItems in
            Task { await loadPhotos(from: newItems) }
        }
    }

    // MARK: - Sections

    private var basicSection: some View {
        Section("Основное") {
            TextField("Название шага", text: $step.title)
            ZStack(alignment: .topLeading) {
                if step.description.isEmpty {
                    Text("Описание шага...")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $step.description)
                    .frame(minHeight: 120)
            }
        }
    }

    private var photosSection: some View {
        Section {
            if !step.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(step.photos.enumerated()), id: \.offset) { index, photo in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                Button {
                                    step.photos.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if step.photos.count < 5 {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 5 - step.photos.count,
                    matching: .images
                ) {
                    Label(step.photos.isEmpty ? "Добавить фото" : "Ещё фото",
                          systemImage: "photo.badge.plus")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Фотографии (до 5 шт.)")
        }
    }

    private var timerSection: some View {
        Section("Таймер") {
            Toggle("Использовать таймер", isOn: $step.timerEnabled)
                .tint(.orange)

            if step.timerEnabled {
                HStack {
                    Picker("Минуты", selection: $step.timerMinutes) {
                        ForEach(0..<120) { m in
                            Text("\(m) мин").tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Text(":")
                        .font(.title2.bold())

                    Picker("Секунды", selection: $step.timerSeconds) {
                        ForEach(stride(from: 0, to: 60, by: 5).map { $0 }, id: \.self) { s in
                            Text(String(format: "%02d", s)).tag(s)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 120)
            }
        }
    }

    // MARK: - Photo loading

    private func loadPhotos(from items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                loaded.append(img)
            }
        }
        step.photos.append(contentsOf: loaded)
        photoItems = []
    }
}
