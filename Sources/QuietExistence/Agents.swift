import Foundation

/// A coding-agent CLI the app can run headlessly. Each one runs under the user's own login for that tool.
enum AgentProvider: String, CaseIterable, Identifiable {
    case claudeCode, openCode, codex, gemini, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .openCode: return "OpenCode"
        case .codex: return "Codex CLI"
        case .gemini: return "Gemini CLI"
        case .custom: return "Custom command"
        }
    }

    /// Executable looked up on the user's PATH.
    var binaryName: String? {
        switch self {
        case .claudeCode: return "claude"
        case .openCode: return "opencode"
        case .codex: return "codex"
        case .gemini: return "gemini"
        case .custom: return nil
        }
    }

    var modelPlaceholder: String {
        switch self {
        case .claudeCode: return "sonnet (or haiku, opus)"
        case .openCode: return "provider/model, e.g. anthropic/claude-sonnet-5"
        case .codex, .gemini: return "CLI default"
        case .custom: return "unused"
        }
    }

    var installHint: String {
        switch self {
        case .claudeCode: return "brew install --cask claude-code"
        case .openCode: return "brew install opencode  (or npm i -g opencode-ai)"
        case .codex: return "brew install codex  (or npm i -g @openai/codex)"
        case .gemini: return "brew install gemini-cli  (or npm i -g @google/gemini-cli)"
        case .custom: return "Enter a full command, using {prompt} where the text should go."
        }
    }

    // MARK: Stored settings

    static var current: AgentProvider {
        AgentProvider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .claudeCode
    }

    var modelKey: String { "model.\(rawValue)" }
    var pathKey: String { "path.\(rawValue)" }

    var model: String {
        let saved = (UserDefaults.standard.string(forKey: modelKey) ?? "").trimmingCharacters(in: .whitespaces)
        if saved.isEmpty, self == .claudeCode { return "sonnet" }
        return saved
    }

    static var customCommand: String {
        UserDefaults.standard.string(forKey: "customCommand") ?? ""
    }

    // MARK: Invocation

    enum OutputFormat { case claudeStreamJSON, plainText }

    var outputFormat: OutputFormat { self == .claudeCode ? .claudeStreamJSON : .plainText }

    /// Resolved executable path, or nil if the tool isn't installed.
    func executablePath() -> String? {
        if self == .custom {
            guard let first = ShellCommand.split(Self.customCommand).first else { return nil }
            return first.contains("/") ? first : ShellEnvironment.which(first)
        }
        let override = (UserDefaults.standard.string(forKey: pathKey) ?? "").trimmingCharacters(in: .whitespaces)
        if !override.isEmpty { return FileManager.default.isExecutableFile(atPath: override) ? override : nil }
        return binaryName.flatMap(ShellEnvironment.which)
    }

    /// Arguments for a run, and text to write to stdin (if any).
    func invocation(systemPrompt: String, prompt: String) -> (args: [String], stdin: String?) {
        // Only Claude Code takes a separate system prompt; others get it prepended.
        let combined = "\(systemPrompt)\n\n\(prompt)"
        let modelArgs = model.isEmpty ? [] : ["--model", model]
        switch self {
        case .claudeCode:
            return (["-p", "--output-format", "stream-json", "--include-partial-messages", "--verbose",
                     "--tools", "", "--no-session-persistence", "--system-prompt", systemPrompt] + modelArgs,
                    prompt)
        case .openCode:
            return (["run"] + modelArgs + [combined], nil)
        case .codex:
            return (["exec", "--skip-git-repo-check"] + modelArgs + [combined], nil)
        case .gemini:
            return (modelArgs + ["-p", combined], nil)
        case .custom:
            let parts = Array(ShellCommand.split(Self.customCommand).dropFirst())
            guard parts.contains(where: { $0.contains("{prompt}") }) else { return (parts, combined) }
            return (parts.map { $0.replacingOccurrences(of: "{prompt}", with: combined) }, nil)
        }
    }
}

/// The user's login-shell environment. Apps launched from Finder get a minimal PATH,
/// which misses tools installed via Homebrew, npm, bun, nvm, etc.
enum ShellEnvironment {
    static let path: String = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "printf '%s' \"$PATH\""]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        var loginPath = ""
        if (try? process.run()) != nil {
            // Don't let a slow or interactive shell profile hang the app.
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if process.isRunning { process.terminate() } }
            process.waitUntilExit()
            loginPath = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .split(separator: "\n").last.map(String.init) ?? ""
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fallback = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.bun/bin",
                        "\(home)/.npm-global/bin", "\(home)/.opencode/bin", "\(home)/.claude/local",
                        "/usr/bin", "/bin"]
        return ([loginPath] + fallback).filter { !$0.isEmpty }.joined(separator: ":")
    }()

    static func which(_ name: String) -> String? {
        path.split(separator: ":")
            .map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        return env
    }
}

enum ShellCommand {
    /// Splits a command line on spaces, honouring single and double quotes.
    static func split(_ command: String) -> [String] {
        var parts: [String] = [], current = "", quote: Character?
        for ch in command {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == " " {
                if !current.isEmpty { parts.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}
