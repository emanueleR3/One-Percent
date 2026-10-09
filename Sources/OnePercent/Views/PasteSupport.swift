import SwiftUI
import AppKit

/// The notch panel is non-activating, so ⌘V does not always reach a focused `TextField`.
/// While `isActive`, this appends the clipboard text to `text` on ⌘V.
private struct PasteSupportModifier: ViewModifier {
    @Binding var text: String
    var isActive: Bool

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear { if isActive { install() } }
            .onChange(of: isActive) { _, active in
                if active { install() } else { remove() }
            }
            .onDisappear { remove() }
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v",
               let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty {
                text += pasted
                return nil
            }
            return event
        }
    }

    private func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

extension View {
    func pasteSupport(text: Binding<String>, isActive: Bool) -> some View {
        modifier(PasteSupportModifier(text: text, isActive: isActive))
    }
}
