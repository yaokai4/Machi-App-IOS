import SwiftUI

/// A dependency-free markdown-lite renderer for Machi Guide article bodies.
///
/// Supports the small subset that curated Guide content actually uses:
/// `##` / `###` headings, `-` (or `*` / `•`) unordered lists, `1.` ordered
/// lists, `| pipe | tables |`, `**bold**`, and `[label](url)` inline links.
/// Everything else is treated as a normal paragraph, so legacy articles that
/// contain no markers render exactly as they did before (plain `\n\n` blocks).
///
/// Inline styling (`**bold**` + `[link](url)`) is delegated to Foundation's
/// `AttributedString(markdown:)` so we never hand-roll a bold/link tokenizer;
/// block structure (headings / lists / tables) is parsed line-by-line here.
struct GuideMarkdownLite: View {
    let text: String
    /// Body text tint (kept as a parameter so both the light Guide card surface
    /// and any dark container can reuse the same renderer).
    var inkColor: Color = .primary
    var accentColor: Color = KXColor.accent
    var bodyFont: Font = .body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
    }

    // MARK: - block rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(inlineAttributed(block.text))
                .font(headingFont(level))
                .foregroundStyle(inkColor)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 4 : 2)
        case .paragraph:
            Text(inlineAttributed(block.text))
                .font(bodyFont)
                .foregroundStyle(inkColor.opacity(0.92))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        case .unordered(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(accentColor)
                            .frame(width: 5, height: 5)
                            .padding(.top, 8)
                        Text(inlineAttributed(item))
                            .font(bodyFont)
                            .foregroundStyle(inkColor.opacity(0.92))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .ordered(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 9) {
                        Text("\(index + 1).")
                            .font(bodyFont.weight(.bold))
                            .foregroundStyle(accentColor)
                            .monospacedDigit()
                        Text(inlineAttributed(item))
                            .font(bodyFont)
                            .foregroundStyle(inkColor.opacity(0.92))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .table(let rows):
            tableView(rows)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3.weight(.bold)
        case 2: return .headline.weight(.bold)
        default: return .subheadline.weight(.bold)
        }
    }

    /// A simple grid table. Horizontally scrollable so a wide table never forces
    /// the whole article to scroll sideways. The first row is treated as a header.
    @ViewBuilder
    private func tableView(_ rows: [[String]]) -> some View {
        let columnCount = rows.map(\.count).max() ?? 0
        if columnCount > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        GridRow {
                            ForEach(0..<columnCount, id: \.self) { col in
                                let cell = col < row.count ? row[col] : ""
                                Text(inlineAttributed(cell))
                                    .font(rowIndex == 0 ? bodyFont.weight(.bold) : bodyFont)
                                    .foregroundStyle(rowIndex == 0 ? inkColor : inkColor.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(minWidth: 60, alignment: .leading)
                                    .padding(.vertical, 8)
                            }
                        }
                        if rowIndex < rows.count - 1 {
                            Divider().opacity(0.25).gridCellColumns(columnCount)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(minWidth: 0, alignment: .leading)
                .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - inline (bold + links) via Foundation markdown

    private func inlineAttributed(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }

    // MARK: - block parsing

    struct Block: Identifiable {
        enum Kind {
            case heading(Int)
            case paragraph
            case unordered([String])
            case ordered([String])
            case table([[String]])
        }
        let id = UUID()
        let kind: Kind
        var text: String = ""
    }

    private var blocks: [Block] { Self.parse(text) }

    /// Line-oriented block parser. Consecutive list items / pipe-table rows are
    /// merged into one block; blank lines separate paragraphs. Text with no
    /// markers degrades to plain paragraphs split on blank lines (legacy
    /// behavior), so older articles are unaffected.
    static func parse(_ raw: String) -> [Block] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var blocks: [Block] = []
        var paragraphBuffer: [String] = []
        var unorderedBuffer: [String] = []
        var orderedBuffer: [String] = []
        var tableBuffer: [[String]] = []

        func flushParagraph() {
            let joined = paragraphBuffer.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(Block(kind: .paragraph, text: joined)) }
            paragraphBuffer.removeAll()
        }
        func flushUnordered() {
            if !unorderedBuffer.isEmpty { blocks.append(Block(kind: .unordered(unorderedBuffer))) }
            unorderedBuffer.removeAll()
        }
        func flushOrdered() {
            if !orderedBuffer.isEmpty { blocks.append(Block(kind: .ordered(orderedBuffer))) }
            orderedBuffer.removeAll()
        }
        func flushTable() {
            // Drop a markdown separator row (|---|---|) if present, then keep rows
            // that carried real cells.
            let cleaned = tableBuffer.filter { row in
                !row.allSatisfy { cell in
                    let t = cell.trimmingCharacters(in: CharacterSet(charactersIn: " -:"))
                    return t.isEmpty
                }
            }
            if !cleaned.isEmpty { blocks.append(Block(kind: .table(cleaned))) }
            tableBuffer.removeAll()
        }
        func flushAll() { flushParagraph(); flushUnordered(); flushOrdered(); flushTable() }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushAll()
                continue
            }

            // Table row: starts and/or contains pipes (at least one interior pipe).
            if isTableRow(line) {
                flushParagraph(); flushUnordered(); flushOrdered()
                tableBuffer.append(tableCells(line))
                continue
            } else if !tableBuffer.isEmpty {
                flushTable()
            }

            // Heading (# .. ####).
            if let (level, content) = heading(line) {
                flushAll()
                blocks.append(Block(kind: .heading(level), text: content))
                continue
            }

            // Unordered list item.
            if let content = unorderedItem(line) {
                flushParagraph(); flushOrdered()
                unorderedBuffer.append(content)
                continue
            } else if !unorderedBuffer.isEmpty {
                flushUnordered()
            }

            // Ordered list item.
            if let content = orderedItem(line) {
                flushParagraph()
                orderedBuffer.append(content)
                continue
            } else if !orderedBuffer.isEmpty {
                flushOrdered()
            }

            // Plain paragraph line.
            paragraphBuffer.append(line)
        }
        flushAll()
        return blocks
    }

    // MARK: - line classifiers

    private static func heading(_ line: String) -> (Int, String)? {
        for level in 1...4 {
            let prefix = String(repeating: "#", count: level) + " "
            if line.hasPrefix(prefix) {
                // Guard against a longer run of '#': "#### x" must not match "## ".
                let after = line.dropFirst(level)
                if after.first == " " {
                    return (level, String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return nil
    }

    private static func unorderedItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            let content = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return content.isEmpty ? nil : content
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> String? {
        guard let range = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) else { return nil }
        let content = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : content
    }

    private static func isTableRow(_ line: String) -> Bool {
        // Require a leading or interior pipe with at least two cells so a lone
        // stray "|" in prose isn't mistaken for a table.
        guard line.contains("|") else { return false }
        let cells = tableCells(line)
        return cells.count >= 2
    }

    private static func tableCells(_ line: String) -> [String] {
        var trimmed = line
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
