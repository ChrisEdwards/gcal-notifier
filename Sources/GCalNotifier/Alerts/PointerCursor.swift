import SwiftUI

// MARK: - Pointer Cursor Extension

extension View {
    /// Applies the pointing hand cursor when hovering over this view.
    /// Uses the native SwiftUI `.pointerStyle(.link)` API for proper cursor handling
    /// in non-activating panels.
    func pointerCursor() -> some View {
        self.pointerStyle(.link)
    }
}
