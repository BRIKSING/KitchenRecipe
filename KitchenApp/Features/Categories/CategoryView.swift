import SwiftUI

struct CategoryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Категории",
                                   systemImage: "square.grid.2x2",
                                   description: Text("Будет реализовано в Этапе 8"))
                .navigationTitle("Категории")
        }
    }
}
