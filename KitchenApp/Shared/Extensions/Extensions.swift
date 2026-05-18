import Foundation
import SwiftUI
import UIKit

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

// MARK: - UIImage crop

extension UIImage {
    func cropped(toAspect aspect: CGFloat) -> UIImage {
        let imageAspect = size.width / size.height
        var cropRect: CGRect
        if imageAspect > aspect {
            let w = size.height * aspect
            cropRect = CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        } else {
            let h = size.width / aspect
            cropRect = CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
        }
        let scaledRect = cropRect.applying(CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = cgImage?.cropping(to: scaledRect) else { return self }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }
}
