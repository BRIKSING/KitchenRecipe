import SwiftUI

// Stub — will be fully implemented in Этап 9.
struct CookingSessionView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.orange)
                Text("Режим приготовления")
                    .font(.title2.bold())
                Text(recipe.title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Будет реализован в Этапе 9")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Выйти") { dismiss() }
                }
            }
        }
    }
}
