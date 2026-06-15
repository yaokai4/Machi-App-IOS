import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

/// Native, zero-dependency crash & hang capture via MetricKit.
///
/// Why not Crashlytics / Sentry: Machi ships with no third-party SDKs.
/// MetricKit is Apple's first-party diagnostics pipeline — the system
/// delivers crash, hang, CPU-exception and disk-write diagnostics
/// (aggregated, privacy-safe, no PII) on the launch AFTER the event. We
/// persist each payload as JSON under `Caches/Diagnostics` so it can be
/// pulled from the device container / a TestFlight sysdiagnose, and later
/// POSTed to the backend once a diagnostics endpoint exists.
///
/// The simulator never emits real payloads — this is a device / TestFlight
/// facility. Registration is a safe no-op everywhere else.
final class DiagnosticsService: NSObject {
    static let shared = DiagnosticsService()

    /// Keep only the most recent N payloads so a chronic crasher can't grow
    /// the cache unbounded.
    private let maxStoredPayloads = 20

    func activate() {
        #if canImport(MetricKit)
        MXMetricManager.shared.add(self)
        #endif
    }

    private var diagnosticsDirectory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = caches.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func persist(_ json: Data, kind: String) {
        guard let dir = diagnosticsDirectory else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("\(kind)-\(stamp).json")
        try? json.write(to: url, options: .atomic)
        pruneOldPayloads(in: dir)
    }

    private func pruneOldPayloads(in dir: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey]
        ), files.count > maxStoredPayloads else {
            return
        }
        let sorted = files.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return lhs < rhs
        }
        for file in sorted.prefix(files.count - maxStoredPayloads) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

#if canImport(MetricKit)
extension DiagnosticsService: MXMetricManagerSubscriber {
    /// Required by the protocol. We don't act on routine performance metrics
    /// today, but the subscription must accept them.
    func didReceive(_ payloads: [MXMetricPayload]) {}

    /// The signal we care about: crashes, hangs, CPU exceptions, disk-write
    /// exceptions. Delivered on the launch after the event occurs.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            persist(payload.jsonRepresentation(), kind: "diagnostic")
        }
    }
}
#endif
