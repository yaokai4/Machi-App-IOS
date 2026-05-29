import Foundation
import SwiftUI

extension String {
    var kaixMediaURL: URL? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }

        return nil
    }

    var normalizedUsername: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
    }

    var normalizedTopicName: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    var extractedHashtags: [String] {
        let pattern = #"#[\p{L}\p{N}_-]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: self) else { return nil }
            return String(self[swiftRange]).normalizedTopicName
        }
    }
}

extension Array where Element == String {
    var normalizedHashtagStorage: String {
        map(\.normalizedTopicName)
            .filter { !$0.isEmpty }
            .removingDuplicates()
            .joined(separator: "|")
    }

    var normalizedDisplayHashtags: [String] {
        map(\.normalizedTopicName)
            .filter { !$0.isEmpty }
            .removingDuplicates()
    }

    func removingDuplicates() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}

extension String {
    var storedHashtags: [String] {
        split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }
}

extension Color {
    static func kaixNamed(_ name: String) -> Color {
        switch name.lowercased() {
        case "black": .black
        case "blue": .blue
        case "green": .green
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        case "red": .red
        case "teal": .teal
        case "yellow": .yellow
        case "indigo": .indigo
        case "mint": .mint
        case "cyan": .cyan
        case "brown": .brown
        default: .blue
        }
    }
}
