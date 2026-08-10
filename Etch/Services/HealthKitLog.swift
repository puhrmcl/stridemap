import Foundation
import os

/// DEBUG-only diagnostics for HealthKit route synchronisation. Kept deliberately terse —
/// enough to answer "why is this run's map missing?" without per-coordinate spam.
///
/// Compiled out of release builds entirely, so it costs nothing in shipping binaries.
enum HealthKitLog {

    private static let logger = Logger(subsystem: "com.nwagtech.etch", category: "healthkit")

    static func route(_ message: @autoclosure () -> String) {
        #if DEBUG
        logger.debug("[HealthKit] \(message(), privacy: .public)")
        #endif
    }
}
