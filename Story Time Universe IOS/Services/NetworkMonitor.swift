import Foundation
import Network
import Combine

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline = true
    private(set) var hasResolvedPath = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.storytime.network")
    private var pathWaiters: [CheckedContinuation<Void, Never>] = []

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isOnline = path.status == .satisfied
                self.hasResolvedPath = true
                let waiters = self.pathWaiters
                self.pathWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        monitor.start(queue: queue)
    }

    /// Wait for the first path update so cold-start offline detection is accurate.
    func waitForInitialPath(timeoutMs: UInt64 = 800) async {
        if hasResolvedPath { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    if self.hasResolvedPath {
                        cont.resume()
                    } else {
                        self.pathWaiters.append(cont)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutMs * 1_000_000)
            }
            await group.next()
            group.cancelAll()
        }
    }
}
