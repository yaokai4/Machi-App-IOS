import Foundation
import OSLog

/// Lightweight performance instrumentation for the app's hot paths
/// (cold launch, tab switch, feed load, Guide load, image decode, …).
///
/// Each `measure`/`event` emits an `os_signpost` so the interval shows up in
/// Instruments' **os_signpost / Points of Interest** track — open Instruments,
/// add the os_signpost instrument, filter to subsystem `com.yaokai.kaizi`. In
/// DEBUG it also logs the measured duration to the unified log under the
/// `Performance` category, so timings are visible in Console.app / `log stream`
/// without Instruments (the prompt's "Instruments 或 日志级性能检查").
///
/// Signposts are near-zero cost and compiled to no-ops when signpost logging is
/// disabled, so this is safe to leave in release builds.
enum KXPerf {
    static let signposter = OSSignposter(subsystem: "com.yaokai.kaizi", category: .pointsOfInterest)
    #if DEBUG
    private static let logger = Logger(subsystem: "com.yaokai.kaizi", category: "Performance")
    #endif

    /// Measure an async operation: signpost interval + (DEBUG) duration log.
    @discardableResult
    static func measure<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            signposter.endInterval(name, state)
            #if DEBUG
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            logger.info("\(name, privacy: .public): \(ms, format: .fixed(precision: 1)) ms")
            #endif
        }
        return try await body()
    }

    /// Measure a synchronous operation.
    @discardableResult
    static func measureSync<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            signposter.endInterval(name, state)
            #if DEBUG
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            logger.info("\(name, privacy: .public): \(ms, format: .fixed(precision: 1)) ms")
            #endif
        }
        return try body()
    }

    /// A single point-in-time marker (e.g. "first content shown").
    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
        #if DEBUG
        logger.info("\(name, privacy: .public)")
        #endif
    }
}
