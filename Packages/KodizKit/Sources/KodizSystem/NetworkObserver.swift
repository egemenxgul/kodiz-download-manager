import Foundation
import Network

public enum NetworkStatus: Sendable {
    case connected(isExpensive: Bool, isConstrained: Bool)
    case disconnected
}

public protocol NetworkObserverDelegate: AnyObject, Sendable {
    func networkStatusDidChange(to status: NetworkStatus) async
}

public final class NetworkObserver: @unchecked Sendable {
    public static let shared = NetworkObserver()

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "dev.kodiz.NetworkObserver", qos: .utility)
    private weak var delegate: NetworkObserverDelegate?

    public private(set) var currentStatus: NetworkStatus = .connected(isExpensive: false, isConstrained: false)

    public init(delegate: NetworkObserverDelegate? = nil) {
        self.delegate = delegate
        self.monitor = NWPathMonitor()
    }

    public func setDelegate(_ delegate: NetworkObserverDelegate) {
        self.delegate = delegate
    }

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let status: NetworkStatus
            if path.status == .satisfied {
                status = .connected(isExpensive: path.isExpensive, isConstrained: path.isConstrained)
            } else {
                status = .disconnected
            }

            self.currentStatus = status

            Task {
                await self.delegate?.networkStatusDidChange(to: status)
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }
}
