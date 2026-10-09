import SwiftUI
import AppKit
import OnePercentCore

/// Scroll view with the app's scroll cues: no native bar (it covered the status chips), a soft fade
/// on whichever edge still has content beyond it, and a slim thumb parked in the card gutter.
struct FadingScrollView<Content: View>: View {
    var fadeHeight: CGFloat = 16
    /// Whenever this value changes the list jumps back to the top (the panel opening, another day).
    var resetToken: AnyHashable? = nil
    @ViewBuilder var content: () -> Content

    @State private var viewportHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var isThumbActive = false
    @State private var thumbToken = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .background(
                    ScrollMetricsReader(resetToken: resetToken) { offset, content, viewport in
                        scrollOffset = offset
                        contentHeight = content
                        viewportHeight = viewport
                        pulseThumb()
                    }
                )
        }
        .scrollBounceBehavior(.basedOnSize)
        .mask { edgeMask }
        .overlay(alignment: .topTrailing) { thumb }
        .animation(IslandAnimations.hoverFade, value: canScrollUp)
        .animation(IslandAnimations.hoverFade, value: canScrollDown)
    }

    private var overflows: Bool { contentHeight > viewportHeight + 1 }
    private var canScrollUp: Bool { overflows && scrollOffset > 1 }
    private var canScrollDown: Bool { overflows && scrollOffset < contentHeight - viewportHeight - 1 }

    private var edgeMask: some View {
        VStack(spacing: 0) {
            edgeFade(visible: canScrollUp, leading: true)
            Color.black
            edgeFade(visible: canScrollDown, leading: false)
        }
    }

    private func edgeFade(visible: Bool, leading: Bool) -> some View {
        ZStack {
            Color.black.opacity(visible ? 0 : 1)
            LinearGradient(
                colors: leading ? [.clear, .black] : [.black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(visible ? 1 : 0)
        }
        .frame(height: fadeHeight)
    }

    @ViewBuilder
    private var thumb: some View {
        if overflows, viewportHeight > 0 {
            let thumbHeight = max(18, viewportHeight * viewportHeight / contentHeight)
            let travel = max(0, viewportHeight - thumbHeight)
            let maxOffset = max(1, contentHeight - viewportHeight)
            let progress = min(max(scrollOffset / maxOffset, 0), 1)

            Capsule()
                .fill(Color.white.opacity(isThumbActive ? 0.42 : 0.16))
                .frame(width: 2.5, height: thumbHeight)
                .offset(x: 9, y: progress * travel)
                .animation(IslandAnimations.hoverFade, value: isThumbActive)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func pulseThumb() {
        thumbToken += 1
        let token = thumbToken
        isThumbActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if token == thumbToken { isThumbActive = false }
        }
    }
}

/// Reports scroll offset / content height / viewport height of the enclosing `NSScrollView`.
/// SwiftUI on macOS 14 has no scroll-geometry API, so this observes the clip view directly.
struct ScrollMetricsReader: NSViewRepresentable {
    var resetToken: AnyHashable? = nil
    var onChange: (_ offset: CGFloat, _ contentHeight: CGFloat, _ viewportHeight: CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollMetricsProbeView {
        let view = ScrollMetricsProbeView()
        view.onChange = onChange
        view.lastResetToken = resetToken
        return view
    }

    func updateNSView(_ nsView: ScrollMetricsProbeView, context: Context) {
        nsView.onChange = onChange
        if nsView.lastResetToken != resetToken {
            nsView.lastResetToken = resetToken
            nsView.scrollToTop()
        }
        nsView.report()
    }
}

final class ScrollMetricsProbeView: NSView {
    var onChange: ((CGFloat, CGFloat, CGFloat) -> Void)?
    var lastResetToken: AnyHashable?

    /// The list is meant to sit at the very top until the user scrolls it. While the card scales in
    /// and out, AppKit re-derives the clip view's origin on a pixel grid of the scaled space and
    /// leaves it a few points down; this flag lets the list correct that drift (and nothing else).
    private(set) var isPinnedToTop = true
    /// Anything beyond this is a real scroll, not rounding drift.
    private static let driftLimit: CGFloat = 12

    private var observers: [NSObjectProtocol] = []
    private var wheelMonitor: Any?
    private var snapScheduled = false
    private var lastReport: (CGFloat, CGFloat, CGFloat) = (-1, -1, -1)

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attach()
    }

    private func attach() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
        wheelMonitor = nil

        guard let scrollView = enclosingScrollView else {
            // The hosting layer may not be wired up yet on the first pass.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.enclosingScrollView != nil else { return }
                self.attach()
            }
            return
        }

        scrollView.hasVerticalScroller = false
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main
            ) { [weak self] _ in
                self?.boundsDidChange()
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification, object: scrollView, queue: .main
            ) { [weak self] _ in
                self?.isPinnedToTop = false
            }
        )
        // A notched mouse wheel does not start a "live" scroll, so watch for wheel events over the list.
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak scrollView] event in
            if let self, let scrollView, event.window === scrollView.window,
               scrollView.bounds.contains(scrollView.convert(event.locationInWindow, from: nil)) {
                self.isPinnedToTop = false
            }
            return event
        }
        if let documentView = scrollView.documentView {
            documentView.postsFrameChangedNotifications = true
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: documentView, queue: .main
                ) { [weak self] _ in self?.report() }
            )
        }
        report()
    }

    private func boundsDidChange() {
        guard let origin = enclosingScrollView?.contentView.bounds.origin else { return }
        if isPinnedToTop, abs(origin.y) >= Self.driftLimit {
            isPinnedToTop = false
        }
        report()
        snapToTopIfPinned(origin)
    }

    /// Puts a drifted origin back on the exact top, on the next turn so AppKit finishes its own layout first.
    private func snapToTopIfPinned(_ origin: NSPoint) {
        guard isPinnedToTop, !snapScheduled, abs(origin.y) > 0.001 || abs(origin.x) > 0.001 else { return }
        snapScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.snapScheduled = false
            if self.isPinnedToTop { self.scrollToTop() }
        }
    }

    func scrollToTop() {
        isPinnedToTop = true
        guard let scrollView = enclosingScrollView, let documentView = scrollView.documentView else { return }
        let top = documentView.isFlipped ? 0 : max(0, documentView.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func report() {
        guard let scrollView = enclosingScrollView, let documentView = scrollView.documentView else { return }
        let viewport = scrollView.contentView.bounds.height
        let content = documentView.frame.height
        let visible = scrollView.documentVisibleRect
        let offset = documentView.isFlipped ? visible.minY : content - visible.maxY

        let next = (offset.rounded(), content.rounded(), viewport.rounded())
        guard next != lastReport else { return }
        lastReport = next
        onChange?(next.0, next.1, next.2)
    }
}
