import SwiftUI
import AppKit

/// Scroll view with the app's scroll cues: no native bar (it covered the status chips), a soft fade
/// on whichever edge still has content beyond it, and a slim thumb parked in the card gutter.
struct FadingScrollView<Content: View>: View {
    var fadeHeight: CGFloat = 16
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
                    ScrollMetricsReader { offset, content, viewport in
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
    var onChange: (_ offset: CGFloat, _ contentHeight: CGFloat, _ viewportHeight: CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollMetricsProbeView {
        let view = ScrollMetricsProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ScrollMetricsProbeView, context: Context) {
        nsView.onChange = onChange
        nsView.report()
    }
}

final class ScrollMetricsProbeView: NSView {
    var onChange: ((CGFloat, CGFloat, CGFloat) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var lastReport: (CGFloat, CGFloat, CGFloat) = (-1, -1, -1)

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attach()
    }

    private func attach() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()

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
            ) { [weak self] _ in self?.report() }
        )
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
