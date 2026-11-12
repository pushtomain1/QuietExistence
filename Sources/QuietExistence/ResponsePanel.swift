import AppKit
import SwiftUI

/// Translucent panel that drops down from under the notch without stealing focus from Zoom/Meet.
final class ResponsePanel: NSPanel {
    static let defaultSize = NSSize(width: 560, height: 440)

    init(session: Session) {
        super.init(contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        // A window shadow would trace every glyph once the background is clear.
        hasShadow = false
        // Explicitly accepting mouse events keeps clear areas clickable/draggable instead of click-through.
        ignoresMouseEvents = false
        appearance = NSAppearance(named: .darkAqua)
        minSize = NSSize(width: 420, height: 260)
        maxSize = NSSize(width: 900, height: 900)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = ResponseView(session: session, close: { [weak self] in self?.dismiss() })
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 16
        hosting.layer?.masksToBounds = true
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }

    /// Esc closes the panel.
    override func cancelOperation(_ sender: Any?) { dismiss() }

    /// Show centred just below the notch (or menu bar) of the screen the mouse is on.
    func present() {
        guard !isVisible else { return orderFrontRegardless() }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            return orderFrontRegardless()
        }
        let top = screen.visibleFrame.maxY   // bottom edge of the menu bar / notch
        let size = frame.size
        let finalFrame = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height - 8,
                                width: size.width, height: size.height)
        setFrame(finalFrame.offsetBy(dx: 0, dy: 12), display: false)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(finalFrame, display: true)
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
        })
    }
}

// MARK: - Content

struct ResponseView: View {
    @ObservedObject var session: Session
    let close: () -> Void
    @State private var showMaterial = false
    @State private var copied = false
    /// 0 = fully transparent, 1 = solid dark (Settings → Panel background).
    @AppStorage("panelOpacity") private var panelOpacity = 0.0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .foregroundStyle(.white)
        // Dark outline around all text and icons so they stay readable over any background.
        .compositingGroup()
        .shadow(color: .black, radius: 0.6)
        .shadow(color: .black, radius: 0.6)
        .shadow(color: .black.opacity(0.9), radius: 1.5)
        .shadow(color: .black.opacity(0.6), radius: 4)
        // Near-zero alpha (not 0) so the whole panel still receives clicks and drags.
        .background(Color.black.opacity(max(panelOpacity, 0.004)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.25)))
        .font(.system(size: 13.5, weight: .medium))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(busy: session.isBusy, color: statusColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle).font(.system(size: 12.5, weight: .semibold))
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.85)).lineLimit(1)
            }
            Spacer(minLength: 8)
            ActionChip(title: "Summarize", icon: "text.alignleft",
                       active: session.lastAction == Action.summarize, disabled: session.isBusy) { session.run(.summarize) }
            ActionChip(title: "Answer", icon: "questionmark.bubble",
                       active: session.lastAction == Action.answer, disabled: session.isBusy) { session.run(.answer) }
            IconButton(icon: "camera.viewfinder", help: "Rescan screen") {
                session.captureAndRun(session.lastAction == .answer ? .answer : .summarize)
            }
            IconButton(icon: copied ? "checkmark" : "doc.on.doc", help: "Copy answer") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.response, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
            .disabled(session.response.isEmpty)
            IconButton(icon: "xmark", help: "Close (Esc)", action: close)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusTitle: String {
        switch session.status {
        case .idle: return "QuietExistence"
        case .capturing: return "Reading screen…"
        case .thinking: return "Thinking…"
        case .streaming: return "Writing…"
        case .done: return "Done"
        case .failed: return "Something went wrong"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .failed: return .red
        case .done: return .green
        case .idle: return .gray
        default: return .accentColor
        }
    }

    private var subtitle: String {
        let agent = AgentProvider.current.displayName
        return session.sourceLabel.isEmpty ? agent : "\(session.sourceLabel) · \(agent)"
    }

    // MARK: Body

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    mainContent
                    if !session.material.isEmpty { capturedText }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: session.response) { _, _ in
                if session.status == .streaming { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder private var mainContent: some View {
        switch session.status {
        case .failed(let message):
            ErrorCard(message: message)
        case .idle:
            Text("Press ⌃⌥S to summarize or ⌃⌥A to answer what's on screen.")
                .foregroundStyle(Color.white.opacity(0.85))
        case .capturing, .thinking:
            LoadingLines()
        case .streaming, .done:
            MarkdownView(markdown: session.response)
        }
    }

    private var capturedText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showMaterial.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showMaterial ? 90 : 0))
                    Text("Captured text · \(session.material.count) characters")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)

            if showMaterial {
                TextEditor(text: $session.material)
                    .font(.system(size: 11.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 110)
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                Text("Edit the text above, then press Summarize or Answer to re-run.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .padding(.top, 4)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(Color.white.opacity(0.85))
            TextField("Ask a follow-up about this material…", text: $session.question)
                .textFieldStyle(.plain)
                .onSubmit { session.askQuestion() }
            Button(action: session.askQuestion) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(canAsk ? Color.accentColor : Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canAsk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var canAsk: Bool {
        !session.question.trimmingCharacters(in: .whitespaces).isEmpty && !session.isBusy
    }
}

// MARK: - Pieces

private struct StatusDot: View {
    let busy: Bool
    let color: Color
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(busy && dim ? 0.3 : 1)
            .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever()) { dim = true } }
    }
}

private struct ActionChip: View {
    let title: String
    let icon: String
    let active: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(active ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

private struct IconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .medium))
                .frame(width: 24, height: 24)
                .background(hovering ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

private struct LoadingLines: View {
    @State private var bright = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach([0.9, 0.75, 0.95, 0.6], id: \.self) { fraction in
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(bright ? 0.14 : 0.06))
                        .frame(width: geo.size.width * fraction, height: 10)
                }
                .frame(height: 10)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { bright = true } }
    }
}

private struct ErrorCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
