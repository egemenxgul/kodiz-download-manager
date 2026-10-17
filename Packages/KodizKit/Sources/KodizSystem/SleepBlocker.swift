import Foundation
import IOKit.pwr_mgt

public final class SleepBlocker: @unchecked Sendable {
    public static let shared = SleepBlocker()
    private var assertionID: IOPMAssertionID = 0
    private var activeCount: Int = 0
    private let lock = NSLock()

    private init() {}

    public func retainSleepAssertion(reason: String = "Kodiz Download Manager is actively downloading") {
        lock.lock()
        defer { lock.unlock() }

        activeCount += 1
        if activeCount == 1 {
            let cfReason = reason as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoIdleSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                cfReason,
                &assertionID
            )
            if result != kIOReturnSuccess {
                assertionID = 0
            }
        }
    }

    public func releaseSleepAssertion() {
        lock.lock()
        defer { lock.unlock() }

        guard activeCount > 0 else { return }
        activeCount -= 1
        if activeCount == 0 && assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }
}
