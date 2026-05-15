import Foundation
import SwiftUI

// MARK: - Duration formatting

extension Int {
    /// Formats minutes as "1 ч 20 мин" or "45 мин"
    var formattedDuration: String {
        if self >= 60 {
            let h = self / 60
            let m = self % 60
            return m > 0 ? "\(h) ч \(m) мин" : "\(h) ч"
        }
        return "\(self) мин"
    }

    /// Formats seconds as "MM:SS"
    var formattedTimer: String {
        let m = self / 60
        let s = self % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - View helpers

extension View {
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Color

extension Color {
    static let kitchenAccent = Color("AccentColor")
}
