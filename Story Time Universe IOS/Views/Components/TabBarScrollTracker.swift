import SwiftUI
import UIKit

private struct TabScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Tracks vertical scroll and toggles `AppState.tabBarVisible` (hide on down, show on up).
struct TabBarScrollTracker: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @State private var lastOffset: CGFloat?
    @State private var accumulated: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: TabScrollOffsetKey.self,
                            value: geo.frame(in: .named("universeTabScroll")).minY
                        )
                }
            }
            .onPreferenceChange(TabScrollOffsetKey.self) { minY in
                handleOffsetChange(minY)
            }
    }

    private func handleOffsetChange(_ minY: CGFloat) {
        // Content moves up (minY ↓) when scrolling down.
        guard let last = lastOffset else {
            lastOffset = minY
            return
        }
        let delta = minY - last
        lastOffset = minY
        applyScrollDelta(delta, absoluteY: -minY)
    }

    fileprivate func applyScrollDelta(_ delta: CGFloat, absoluteY: CGFloat) {
        if absoluteY <= 24 {
            accumulated = 0
            showTabBar()
            return
        }

        accumulated += delta
        if accumulated < -28 {
            accumulated = 0
            hideTabBar()
        } else if accumulated > 28 {
            accumulated = 0
            showTabBar()
        }
    }

    private func showTabBar() {
        guard !appState.tabBarVisible else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            appState.tabBarVisible = true
        }
    }

    private func hideTabBar() {
        guard appState.tabBarVisible else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            appState.tabBarVisible = false
        }
    }
}

/// UIKit contentOffset observer — reliable for `List` / UITableView.
struct ListTabBarScrollTracker: ViewModifier {
    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content
            .background(
                ScrollOffsetBridge { delta, y in
                    if y <= 24 {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            appState.tabBarVisible = true
                        }
                        return
                    }
                    if delta > 10 {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            appState.tabBarVisible = false
                        }
                    } else if delta < -10 {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            appState.tabBarVisible = true
                        }
                    }
                }
            )
    }
}

private struct ScrollOffsetBridge: UIViewRepresentable {
    var onChange: (_ delta: CGFloat, _ y: CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.attach(from: uiView)
    }

    final class Coordinator {
        var onChange: (CGFloat, CGFloat) -> Void
        private weak var observed: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var lastY: CGFloat = 0

        init(onChange: @escaping (CGFloat, CGFloat) -> Void) {
            self.onChange = onChange
        }

        func attach(from view: UIView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                guard let scroll = view.findEnclosingScrollView() else { return }
                guard scroll !== self.observed else { return }
                self.observed = scroll
                self.lastY = scroll.contentOffset.y
                self.observation?.invalidate()
                self.observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                    guard let self else { return }
                    let y = scrollView.contentOffset.y
                    let delta = y - self.lastY
                    guard abs(delta) > 6 else { return }
                    self.lastY = y
                    DispatchQueue.main.async {
                        self.onChange(delta, y)
                    }
                }
            }
        }
    }
}

private extension UIView {
    func findEnclosingScrollView() -> UIScrollView? {
        var node: UIView? = self
        while let current = node {
            if let scroll = current as? UIScrollView { return scroll }
            node = current.superview
        }
        // Walk siblings / parent children (SwiftUI hosting layout).
        node = self.superview
        while let current = node {
            if let found = current.subviews.compactMap({ $0 as? UIScrollView }).first {
                return found
            }
            if let found = Self.deepFindScroll(in: current) {
                return found
            }
            node = current.superview
        }
        return nil
    }

    static func deepFindScroll(in root: UIView) -> UIScrollView? {
        if let scroll = root as? UIScrollView { return scroll }
        for child in root.subviews {
            if let found = deepFindScroll(in: child) { return found }
        }
        return nil
    }
}

extension View {
    /// Apply on the **content inside** a ScrollView, and put
    /// `.tabScrollCoordinateSpace()` on that scroll container.
    func trackScrollForTabBar() -> some View {
        modifier(TabBarScrollTracker())
    }

    /// Apply on a `List` (UIKit-backed).
    func trackListScrollForTabBar() -> some View {
        modifier(ListTabBarScrollTracker())
    }

    func tabScrollCoordinateSpace() -> some View {
        coordinateSpace(name: "universeTabScroll")
    }
}
