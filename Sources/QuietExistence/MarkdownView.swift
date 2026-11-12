import AppKit
import SwiftUI

/// Minimal block-level Markdown: headings, lists, quotes, rules, paragraphs and fenced code.
/// Inline styling (bold, italic, `code`, links) is handled by AttributedString.
enum MarkdownBlock: Hashable {
    case heading(level: Int, text: String)
    case listItem(marker: String, text: String, indent: Int)
    case quote(String)
    case rule
    case paragraph(String)
    case code(language: String, code: String)

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?
        var language = ""

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }

        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(language: language, code: lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    code = []
                }
                continue
            }
            if code != nil { code!.append(raw); continue }

            if line.isEmpty { flushParagraph(); continue }

            if line.hasPrefix("#") {
                let level = line.prefix { $0 == "#" }.count
                let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                if level <= 6, !text.isEmpty { flushParagraph(); blocks.append(.heading(level: level, text: text)); continue }
            }
            if line == "---" || line == "***" || line == "___" { flushParagraph(); blocks.append(.rule); continue }
            if line.hasPrefix("> ") { flushParagraph(); blocks.append(.quote(String(line.dropFirst(2)))); continue }

            let indent = (raw.prefix { $0 == " " }.count) / 2
            if let bullet = ["- ", "* ", "• "].first(where: line.hasPrefix) {
                flushParagraph()
                blocks.append(.listItem(marker: "•", text: String(line.dropFirst(bullet.count)), indent: indent))
                continue
            }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
               line[line.index(after: dot)...].hasPrefix(" ") {
                flushParagraph()
                blocks.append(.listItem(marker: String(line[...dot]), text: String(line[line.index(dot, offsetBy: 2)...]), indent: indent))
                continue
            }
            paragraph.append(line)
        }
        // An unclosed fence still renders as code while the answer is streaming.
        if let lines = code { blocks.append(.code(language: language, code: lines.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }
}

struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlock.parse(markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(.system(size: level == 1 ? 17 : level == 2 ? 15 : 13.5, weight: .semibold))
                .padding(.top, level <= 2 ? 6 : 2)
        case .listItem(let marker, let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(marker).foregroundStyle(Color.white.opacity(0.85)).monospacedDigit()
                Text(inline(text)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .quote(let text):
            Text(inline(text))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Capsule().fill(.white.opacity(0.25)).frame(width: 3) }
        case .rule:
            Divider().opacity(0.5)
        case .paragraph(let text):
            Text(inline(text)).fixedSize(horizontal: false, vertical: true)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        var attributed = (try? AttributedString(markdown: text,
                                                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        // Style `inline code` runs.
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].font = .system(size: 12, design: .monospaced)
            attributed[run.range].backgroundColor = Color.white.opacity(0.1)
        }
        return attributed
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Color.green : Color.white.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.15)).frame(height: 1) }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(10)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.3)))
    }
}
