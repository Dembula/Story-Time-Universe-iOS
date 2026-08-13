import SwiftUI
import UIKit

/// Reports vertical scroll direction so the main tab bar can fade.
struct TabBarScrollTracker: ViewModifier {
    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content
            .background(
                ScrollOffsetBridge { delta in
                    withAnimation(.easeInOut(duration: 0.22)) {
                        appState.tabBarVisible = delta <= 0
                    }
                }
            )
    }
}

private struct ScrollOffsetBridge: UIViewRepresentable {
    var onDelta: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDelta: onDelta)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDelta = onDelta
        context.coordinator.attach(from: uiView)
    }

    final class Coordinator {
        var onDelta: (CGFloat) -> Void
        private weak var observed: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var lastY: CGFloat = 0

        init(onDelta: @escaping (CGFloat) -> Void) {
            self.onDelta = onDelta
        }

        func attach(from view: UIView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                guard let scroll = view.enclosingScrollView() else { return }
                guard scroll !== self.observed else { return }
                self.observed = scroll
                self.lastY = scroll.contentOffset.y
                self.observation?.invalidate()
                self.observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                    guard let self else { return }
                    let y = scrollView.contentOffset.y
                    if y <= 12 {
                        self.onDelta(-1)
                        self.lastY = y
                        return
                    }
                    let delta = y - self.lastY
                    guard abs(delta) > 8 else { return }
                    self.onDelta(delta)
                    self.lastY = y
                }
            }
        }
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var node: UIView? = self
        while let current = node {
            if let scroll = current as? UIScrollView {
                return scroll
            }
            node = current.superview
        }
        return nil
    }
}

extension View {
    func trackScrollForTabBar() -> some View {
        modifier(TabBarScrollTracker())
    }
}
