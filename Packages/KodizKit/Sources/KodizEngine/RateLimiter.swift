import Foundation

public actor RateLimiter {
    private var bytesPerSecond: Int64
    private var availableTokens: Double
    private var lastRefillTime: Date

    public init(bytesPerSecond: Int64) {
        self.bytesPerSecond = bytesPerSecond
        self.availableTokens = Double(bytesPerSecond)
        self.lastRefillTime = Date()
    }

    public func setLimit(_ bytesPerSecond: Int64) {
        self.bytesPerSecond = bytesPerSecond
        if bytesPerSecond <= 0 {
            self.availableTokens = .infinity
        }
    }

    public func acquire(bytes: Int64) async {
        guard bytesPerSecond > 0 else { return }

        while true {
            refill()
            if availableTokens >= Double(bytes) {
                availableTokens -= Double(bytes)
                return
            }

            let needed = Double(bytes) - availableTokens
            let waitSeconds = needed / Double(bytesPerSecond)
            let sleepNanoseconds = UInt64(max(0.01, waitSeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: sleepNanoseconds)
        }
    }

    private func refill() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefillTime)
        let newTokens = elapsed * Double(bytesPerSecond)
        availableTokens = min(Double(bytesPerSecond * 2), availableTokens + newTokens)
        lastRefillTime = now
    }
}
