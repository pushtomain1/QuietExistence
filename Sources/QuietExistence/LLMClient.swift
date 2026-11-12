import Foundation

enum Action: Equatable {
    case summarize
    case answer
    case ask(String)

    var instruction: String {
        switch self {
        case .summarize:
            return "Turn this class material into concise study notes: key concepts, definitions, formulas and examples. Use short headings and bullet points."
        case .answer:
            return "I'm practicing real world interview question shared by the HR for my interview prep, Find every question, exercise or problem in this material and answer each one clearly. Show working steps for problems. If there are no questions, explain the main concept shown. if there is coding problem give the code in this lanaguage"
        case .ask(let question):
            return "Using this material as context, answer my question: \(question)"
        }
    }
}

enum LLMError: LocalizedError {
    case notInstalled(AgentProvider)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let provider):
            return "Couldn't find \(provider.displayName). Install it (\(provider.installHint)) or set its path in Settings."
        case .failed(let message):
            return message
        }
    }
}

/// Preferred language for code in answers (Settings → Coding language).
enum CodeLanguage: String, CaseIterable, Identifiable {
    case auto, python, java, cpp, c, javascript, typescript, go, rust, csharp, kotlin, swift, sql

    var id: String { rawValue }

    /// nil = let the model match the material.
    var name: String? {
        switch self {
        case .auto: return nil
        case .python: return "Python"
        case .java: return "Java"
        case .cpp: return "C++"
        case .c: return "C"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .go: return "Go"
        case .rust: return "Rust"
        case .csharp: return "C#"
        case .kotlin: return "Kotlin"
        case .swift: return "Swift"
        case .sql: return "SQL"
        }
    }

    var label: String { name ?? "Auto (match the material)" }

    static var current: CodeLanguage {
        CodeLanguage(rawValue: UserDefaults.standard.string(forKey: "codeLanguage") ?? "") ?? .auto
    }
}

/// Runs the selected coding-agent CLI headlessly and streams its answer.
enum AgentClient {
    static let basePrompt = """
    You are a study companion for a student attending online classes (Zoom / Google Meet). \
    The text you receive was captured from the student's screen, usually by OCR of shared slides or documents. \
    It may contain OCR mistakes and stray meeting UI (participant names, buttons, chat, timers) — ignore those \
    and focus on the teaching material. Do not use any tools or edit files; just answer. \
    Format answers in simple Markdown (headings, bullets, bold). Put any code in fenced code blocks with a language tag. \
    Never use LaTeX: write math in plain text with Unicode symbols, e.g. F = m × a, x², √2, ≤, π.
    """

    /// Base prompt plus the coding-language preference from Settings.
    static var systemPrompt: String {
        guard let language = CodeLanguage.current.name else { return basePrompt }
        return basePrompt + "\n\n" + """
        When the material contains a coding problem or asks for code, write the solution in \(language), \
        even if the material uses a different language. Use idiomatic \(language), explain the approach briefly, \
        and state the time and space complexity.
        """
    }

    static func stream(_ action: Action, material: String) -> AsyncThrowingStream<String, Error> {
        let provider = AgentProvider.current
        return AsyncThrowingStream { continuation in
            guard let path = provider.executablePath() else {
                continuation.finish(throwing: LLMError.notInstalled(provider))
                return
            }
            let prompt = "\(action.instruction)\n\n<material>\n\(material)\n</material>"
            let (args, stdinText) = provider.invocation(systemPrompt: systemPrompt, prompt: prompt)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            // Neutral working directory so no project instructions (CLAUDE.md, AGENTS.md) get pulled in.
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            process.environment = ShellEnvironment.environment

            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            // Drain stderr continuously (chatty CLIs would otherwise block on a full pipe); keep the tail.
            let errorTail = TailBuffer(limit: 4000)
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { handle.readabilityHandler = nil } else { errorTail.append(chunk) }
            }

            var parser = OutputParser(format: provider.outputFormat)
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    // EOF: the process is done writing.
                    handle.readabilityHandler = nil
                    for text in parser.flush() { continuation.yield(text) }
                    process.waitUntilExit()
                    finish(process, parser.resultError, errorTail.string)
                    return
                }
                for text in parser.consume(chunk) { continuation.yield(text) }
            }

            func finish(_ proc: Process, _ resultError: String?, _ stderrText: String) {
                if let resultError {
                    continuation.finish(throwing: LLMError.failed(resultError))
                } else if proc.terminationStatus != 0 && proc.terminationReason != .uncaughtSignal {
                    let message = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.finish(throwing: LLMError.failed(message.isEmpty
                        ? "\(provider.displayName) exited with code \(proc.terminationStatus). Run it in Terminal to check you're logged in."
                        : "\(provider.displayName): \(message)"))
                } else {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
                if let stdinText { stdin.fileHandleForWriting.write(Data(stdinText.utf8)) }
                try? stdin.fileHandleForWriting.close()
            } catch {
                continuation.finish(throwing: LLMError.failed("Couldn't start \(provider.displayName): \(error.localizedDescription)"))
            }
        }
    }
}

/// Turns raw stdout bytes into text chunks for display.
private struct OutputParser {
    let format: AgentProvider.OutputFormat
    private(set) var resultError: String?
    private var buffer = Data()

    init(format: AgentProvider.OutputFormat) { self.format = format }

    mutating func consume(_ chunk: Data) -> [String] {
        buffer.append(chunk)
        var out: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let text = handle(line) { out.append(text) }
        }
        return out
    }

    mutating func flush() -> [String] {
        defer { buffer.removeAll() }
        guard !buffer.isEmpty, format == .plainText else { return [] }
        return [Self.stripANSI(String(decoding: buffer, as: UTF8.self))]
    }

    private mutating func handle(_ line: Data) -> String? {
        switch format {
        case .plainText:
            return Self.stripANSI(String(decoding: line, as: UTF8.self)) + "\n"
        case .claudeStreamJSON:
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
            switch event["type"] as? String {
            case "stream_event":
                if let inner = event["event"] as? [String: Any],
                   let delta = inner["delta"] as? [String: Any],
                   delta["type"] as? String == "text_delta" {
                    return delta["text"] as? String
                }
            case "result":
                if event["is_error"] as? Bool == true {
                    resultError = event["result"] as? String ?? "Claude Code returned an error."
                }
            default:
                break
            }
            return nil
        }
    }

    private static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }
}

/// Thread-safe rolling buffer for the end of stderr.
private final class TailBuffer: @unchecked Sendable {
    private let limit: Int
    private var data = Data()
    private let lock = NSLock()

    init(limit: Int) { self.limit = limit }

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        if data.count > limit { data.removeFirst(data.count - limit) }
    }

    var string: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
