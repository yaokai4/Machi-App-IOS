import SwiftUI

#if DEBUG
import QuartzCore
import OSLog

/// DEBUG-only frame-rate / hitch monitor — the runtime half of the app's
/// "120 Hz regression guardrail". A `CADisplayLink` (requesting up to the
/// display's native rate, so it observes ProMotion's 120 Hz) measures the gap
/// between vsyncs and flags any frame that runs long enough to read as a stutter.
///
/// It logs two things to the unified log under category `FrameRate`
/// (subsystem `com.yaokai.kaizi`) so you can watch them in Console.app /
/// `log stream` while scrolling the feed:
///   • a rolling FPS reading once per second, and
///   • each hitch (a frame that took ≥ ~1.5× the expected interval), with how
///     long it ran — these are the dropped frames that break the 120 Hz feel.
///
/// Compiled out entirely in release (`#if DEBUG`), so it adds zero cost to
/// shipping builds while giving a cheap, always-available way to catch a change
/// that quietly reintroduces main-thread jank.
@MainActor
final class KXFrameRateMonitor {
    static let shared = KXFrameRateMonitor()

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var framesInWindow = 0
    private var hitchesInWindow = 0
    private let logger = Logger(subsystem: "com.yaokai.kaizi", category: "FrameRate")

    private init() {}

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = 0
        windowStart = 0
        framesInWindow = 0
        hitchesInWindow = 0
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTimestamp = now }
        guard lastTimestamp != 0 else {
            windowStart = now
            return
        }

        let delta = now - lastTimestamp
        // Expected interval for this refresh (≈8.3 ms at 120 Hz, 16.7 ms at 60).
        let expected = link.targetTimestamp - link.timestamp
        let budget = expected > 0 ? expected : 1.0 / 60.0
        framesInWindow += 1
        if delta > budget * 1.5 {
            hitchesInWindow += 1
            let overMs = (delta - budget) * 1000
            KXPerf.event("frame.hitch")
            logger.notice("hitch: frame ran \(delta * 1000, format: .fixed(precision: 1)) ms (+\(overMs, format: .fixed(precision: 1)) ms over budget)")
        }

        if now - windowStart >= 1.0 {
            let fps = Double(framesInWindow) / (now - windowStart)
            logger.info("fps: \(fps, format: .fixed(precision: 0)) over \(self.framesInWindow) frames, \(self.hitchesInWindow) hitches")
            windowStart = now
            framesInWindow = 0
            hitchesInWindow = 0
        }
    }
}
#endif

extension View {
    /// Attach the DEBUG frame-rate monitor to the app's root. No-op in release.
    func kxFrameRateMonitored() -> some View {
        #if DEBUG
        return self
            .onAppear { KXFrameRateMonitor.shared.start() }
            .onDisappear { KXFrameRateMonitor.shared.stop() }
        #else
        return self
        #endif
    }
}
