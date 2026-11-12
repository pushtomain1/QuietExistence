import Foundation

@MainActor
final class Session: ObservableObject {
    enum Status: Equatable { case idle, capturing, thinking, streaming, done, failed(String) }

    @Published var status: Status = .idle
    @Published var material = ""
    @Published var response = ""
    @Published var sourceLabel = ""
    @Published var question = ""
    @Published var lastAction: Action = .summarize

    private var task: Task<Void, Never>?

    /// Capture from screen, then run the action.
    func captureAndRun(_ action: Action) {
        task?.cancel()
        task = Task {
            status = .capturing
            response = ""
            do {
                let captured = try await TextCapture.capture()
                material = captured.text
                sourceLabel = captured.source == .selection ? "Selected text · \(captured.appName)"
                                                            : "Screen · \(captured.appName)"
                await send(action)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    /// Re-run on the already captured (possibly edited) material.
    func run(_ action: Action) {
        guard !material.isEmpty else { return captureAndRun(action) }
        task?.cancel()
        task = Task { await send(action) }
    }

    func askQuestion() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        question = ""
        run(.ask(q))
    }

    var isBusy: Bool { [.capturing, .thinking, .streaming].contains(status) }

    private func send(_ action: Action) async {
        lastAction = action
        status = .thinking
        response = ""
        do {
            for try await chunk in AgentClient.stream(action, material: material) {
                guard !Task.isCancelled else { return }
                if status == .thinking { status = .streaming }
                response += chunk
            }
            guard !Task.isCancelled else { return }
            status = .done
        } catch {
            guard !Task.isCancelled else { return }
            status = .failed(error.localizedDescription)
        }
    }
}
