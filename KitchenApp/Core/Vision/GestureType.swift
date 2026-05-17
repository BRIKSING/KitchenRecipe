import Foundation

enum GestureType: Equatable {
    case swipeNext   // Open palm moving right → next step
    case swipePrev   // Open palm moving left  → previous step
    case fistHold    // Clenched fist held 1s  → pause/resume timer
    case victory     // Index + middle up (V)  → confirm/hint

    var displayName: String {
        switch self {
        case .swipeNext: return "Следующий шаг"
        case .swipePrev: return "Предыдущий шаг"
        case .fistHold:  return "Пауза / продолжить"
        case .victory:   return "Подтверждение"
        }
    }

    var iconName: String {
        switch self {
        case .swipeNext: return "hand.point.right.fill"
        case .swipePrev: return "hand.point.left.fill"
        case .fistHold:  return "hand.raised.fill"
        case .victory:   return "hand.raised.fingers.spread.fill"
        }
    }
}
