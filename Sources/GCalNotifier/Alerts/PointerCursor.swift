import SwiftUI

// MARK: - Pointer Cursor Extension

extension View {
    /// Applies the pointing hand cursor when hovering over this view.
    func pointerCursor() -> some View {
        self.pointerStyle(.link)
    }
}
