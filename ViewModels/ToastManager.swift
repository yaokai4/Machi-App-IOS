import Combine
import Foundation
import SwiftUI

struct ToastItem: Identifiable {
    let id = UUID()
    let state: ErrorState
    let retry: (() -> Void)?
}

@MainActor
final class ToastManager: ObservableObject {
    @Published private(set) var current: ToastItem?
    private var dismissTask: Task<Void, Never>?

    func show(_ state: ErrorState, duration: TimeInterval? = 4, retry: (() -> Void)? = nil) {
        dismissTask?.cancel()
        current = ToastItem(state: state, retry: retry)

        guard let duration else { return }
        dismissTask = Task { [weak self] in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.snappy(duration: 0.2)) {
            current = nil
        }
    }
}
