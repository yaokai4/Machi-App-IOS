import Foundation

enum NumberFormatterUtils {
    static func compact(_ value: Int) -> String {
        let doubleValue = Double(value)
        if value < 1_000 { return "\(value)" }
        if value < 1_000_000 {
            let compact = doubleValue / 1_000
            return compact.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(compact))K"
                : String(format: "%.1fK", compact)
        }
        let compact = doubleValue / 1_000_000
        return compact.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(compact))M"
            : String(format: "%.1fM", compact)
    }
}
