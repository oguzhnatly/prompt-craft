import Combine
import Foundation
import Network

/// Monitors network connectivity using NWPathMonitor.
/// Publishes `isConnected` for UI bindings (e.g., a "No internet" banner).
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var isExpensive: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.promptcraft.networkMonitor", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
            }
        }
        monitor.start(queue: queue)
        Logger.shared.info("NetworkMonitor started")
    }

    deinit {
        monitor.cancel()
    }

    /// Check if localhost is reachable (for Ollama). This does a quick TCP connection check.
    func checkLocalhostConnectivity(port: UInt16 = 11434) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: .ipv4(.loopback),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            let timeout = DispatchWorkItem {
                connection.cancel()
                continuation.resume(returning: false)
            }
            queue.asyncAfter(deadline: .now() + 2.0, execute: timeout)

            connection.stateUpdateHandler = { state in
                timeout.cancel()
                switch state {
                case .ready:
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    connection.cancel()
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
            connection.start(queue: self.queue)
        }
    }
}
