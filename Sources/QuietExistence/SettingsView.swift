import ApplicationServices
import SwiftUI

struct SettingsView: View {
    @AppStorage("provider") private var providerRaw = AgentProvider.claudeCode.rawValue
    @AppStorage("customCommand") private var customCommand = ""
    @AppStorage("codeLanguage") private var codeLanguage = CodeLanguage.auto.rawValue
    @AppStorage("panelOpacity") private var panelOpacity = 0.0
    @State private var model = ""
    @State private var pathOverride = ""
    @State private var resolvedPath: String?
    @State private var accessibilityOK = AXIsProcessTrusted()
    @State private var screenOK = CGPreflightScreenCaptureAccess()

    private var provider: AgentProvider { AgentProvider(rawValue: providerRaw) ?? .claudeCode }

    var body: some View {
        Form {
            Section {
                Picker("Agent", selection: $providerRaw) {
                    ForEach(AgentProvider.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                if provider == .custom {
                    TextField("Command", text: $customCommand, prompt: Text("mycli --print {prompt}"))
                } else {
                    TextField("Model", text: $model, prompt: Text(provider.modelPlaceholder))
                        .onChange(of: model) { _, value in UserDefaults.standard.set(value, forKey: provider.modelKey) }
                    TextField("CLI path", text: $pathOverride, prompt: Text("Auto-detect"))
                        .onChange(of: pathOverride) { _, value in UserDefaults.standard.set(value, forKey: provider.pathKey) }
                }
                HStack(alignment: .top) {
                    Image(systemName: resolvedPath != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(resolvedPath != nil ? .green : .red)
                    Text(resolvedPath ?? "Not found. \(provider.installHint)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("AI agent")
            } footer: {
                Text(provider == .custom
                     ? "{prompt} is replaced with the prompt. Without it, the prompt is sent on stdin. Output is shown as it's printed."
                     : "Uses your own \(provider.displayName) login. Make sure it works in Terminal first.")
            }
            Section {
                Picker("Coding language", selection: $codeLanguage) {
                    ForEach(CodeLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                }
                LabeledContent("Panel background") {
                    HStack {
                        Slider(value: $panelOpacity, in: 0...0.9)
                        Text(panelOpacity < 0.01 ? "Clear" : "\(Int(panelOpacity * 100))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("Answers")
            } footer: {
                Text("Solutions to coding problems will be written in this language. Raise the panel background if text is hard to read over busy screens.")
            }
            Section("Permissions") {
                permissionRow("Screen Recording (read slides via OCR)", ok: screenOK) {
                    CGRequestScreenCaptureAccess()
                    open("Privacy_ScreenCapture")
                }
                permissionRow("Accessibility (read selected text, optional)", ok: accessibilityOK) {
                    AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                    open("Privacy_Accessibility")
                }
            }
            Section("Shortcuts") {
                LabeledContent("Summarize screen", value: "⌃⌥S")
                LabeledContent("Answer questions on screen", value: "⌃⌥A")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 600)
        .onAppear(perform: loadProviderFields)
        .onChange(of: providerRaw) { _, _ in loadProviderFields() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibilityOK = AXIsProcessTrusted()
            screenOK = CGPreflightScreenCaptureAccess()
            resolvedPath = provider.executablePath()
        }
    }

    private func loadProviderFields() {
        model = UserDefaults.standard.string(forKey: provider.modelKey) ?? ""
        pathOverride = UserDefaults.standard.string(forKey: provider.pathKey) ?? ""
        resolvedPath = provider.executablePath()
    }

    private func permissionRow(_ title: String, ok: Bool, request: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? .green : .orange)
            Text(title)
            Spacer()
            if !ok { Button("Grant…", action: request) }
        }
    }

    private func open(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}
