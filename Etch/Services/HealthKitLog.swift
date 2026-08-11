import Foundation
import os

/// DEBUG-only diagnostics for HealthKit route synchronisation. Kept deliberately terse —
/// enough to answer "why is this run's map missing?" without per-coordinate spam.
///
/// Compiled out of release builds entirely, so it costs nothing in shipping binaries.
enum HealthKitLog {

    private static let logger = Logger(subsystem: "com.nwagtech.etch", category: "healthkit")

    /// Logged at `.notice` so it persists and is visible in Console.app even for TestFlight
    /// (Release) builds — connect the phone to a Mac, open Console, filter by "Etch".
    static func route(_ message: @autoclosure () -> String) {
        let text = message()
        logger.notice("\(text, privacy: .public)")
    }
}
