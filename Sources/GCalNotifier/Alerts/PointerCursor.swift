import AppKit
import SwiftUI

// MARK: - Pointer Cursor for Non-Activating Panels

/// A view modifier that shows the pointing hand cursor on hover.
/// Uses `.activeAlways` tracking to work in non-activating panels.
private struct PointerCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                PointerCursorTrackingView(isHovering: $isHovering)
            )
            .onChange(of: isHovering) { _, hovering in
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }
}

/// NSViewRepresentable that creates an AppKit view with `.activeAlways` tracking.
/// This ensures cursor updates work even in non-activating panels.
private struct PointerCursorTrackingView: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> PointerTrackingNSView {
        let view = PointerTrackingNSView()
        view.onHoverChanged = { hovering in
            DispatchQueue.main.async {
                self.isHovering = hovering
            }
        }
        return view
    }

    func updateNSView(_ nsView: PointerTrackingNSView, context: Context) {
        // No updates needed
    }
}

/// Custom NSView that tracks mouse enter/exit with `.activeAlways`.
private class PointerTrackingNSView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        // Use .activeAlways so it works in non-activating panels
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}

// MARK: - View Extension

extension View {
    /// Applies the pointing hand cursor when hovering over this view.
    /// Works correctly in non-activating panels by using `.activeAlways` tracking.
    func pointerCursor() -> some View {
        self.modifier(PointerCursorModifier())
    }
}
