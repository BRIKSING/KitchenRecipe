import SwiftUI

// MARK: - Global error state

final class ErrorBannerState: ObservableObject {
    static let shared = ErrorBannerState()
    @Published var message: String?

    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, duration: TimeInterval = 4) {
        DispatchQueue.main.async {
            self.message = message
            self.dismissTask?.cancel()
            self.dismissTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                if !Task.isCancelled {
                    await MainActor.run { self.message = nil }
                }
            }
        }
    }

    func show(_ error: Error) {
        show(error.localizedDescription)
    }
}

// MARK: - Banner view

private struct ErrorBannerView: View {
    @ObservedObject var state: ErrorBannerState

    var body: some View {
        if let message = state.message {
            VStack {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white)
                    Text(message)
                        .foregroundStyle(.white)
                        .font(.subheadline)
                    Spacer()
                    Button {
                        withAnimation { state.message = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()
                .background(Color.red.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                Spacer()
            }
        }
    }
}

// MARK: - ViewModifier

private struct ErrorBannerModifier: ViewModifier {
    @ObservedObject private var state = ErrorBannerState.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            ErrorBannerView(state: state)
                .animation(.spring(response: 0.4), value: state.message)
        }
    }
}

extension View {
    func errorBanner() -> some View {
        modifier(ErrorBannerModifier())
    }
}
