import Foundation

public actor AIMDController {
    public private(set) var currentConnections: Int
    public let minConnections: Int
    public let maxConnections: Int

    private var lastEvaluationTime: Date
    private var lastSpeed: Double = 0.0
    private var backoffUntil: Date?

    public init(
        initialConnections: Int = 4,
        minConnections: Int = 1,
        maxConnections: Int = 16
    ) {
        self.currentConnections = initialConnections
        self.minConnections = minConnections
        self.maxConnections = maxConnections
        self.lastEvaluationTime = Date()
    }

    /// Evaluates current throughput and applies Additive Increase
    public func evaluateThroughput(currentSpeed: Double) -> Int {
        let now = Date()

        // If in backoff period, do not increase
        if let backoff = backoffUntil, now < backoff {
            return currentConnections
        }

        let elapsed = now.timeIntervalSince(lastEvaluationTime)
        guard elapsed >= 3.0 else {
            return currentConnections
        }

        // Check if throughput increased by > 5%
        if lastSpeed > 0 && currentSpeed > lastSpeed * 1.05 {
            if currentConnections < maxConnections {
                currentConnections += 1
            }
        }

        lastSpeed = currentSpeed
        lastEvaluationTime = now
        return currentConnections
    }

    /// Multiplicative Decrease: called upon 429, 503, connection drops or rate-limiting
    public func recordCongestion(retryAfterSeconds: Double? = nil) -> Int {
        // Halve connection count
        currentConnections = max(minConnections, currentConnections / 2)

        let penalty = retryAfterSeconds ?? 30.0
        backoffUntil = Date().addingTimeInterval(penalty)
        lastEvaluationTime = Date()
        return currentConnections
    }
}
