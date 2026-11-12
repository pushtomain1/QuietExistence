import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

struct Captured {
    enum Source { case selection, screen }
    let text: String
    let source: Source
    let appName: String
}

enum CaptureError: LocalizedError {
    case noScreenPermission, noWindow, noText

    var errorDescription: String? {
        switch self {
        case .noScreenPermission:
            return "Screen Recording permission is needed to read shared slides. Enable QuietExistence in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch the app."
        case .noWindow:
            return "Couldn't find a window to read. Click on your Zoom/Meet window first, then press the shortcut."
        case .noText:
            return "No text was found in the window."
        }
    }
}

enum TextCapture {
    /// Selected text wins (exact, no OCR); otherwise read the front window in memory.
    static func capture(preferSelection: Bool = true) async throws -> Captured {
        let front = NSWorkspace.shared.frontmostApplication
        let appName = front?.localizedName ?? "Screen"

        if preferSelection, let selection = selectedText(),
           !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Captured(text: selection, source: .selection, appName: appName)
        }

        let text = try await ocrWindow(ownedBy: front?.processIdentifier)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CaptureError.noText }
        return Captured(text: text, source: .screen, appName: appName)
    }

    // MARK: Accessibility (real text, no pixels)

    static func selectedText() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    // MARK: In-memory OCR (for screen shares, images, PDFs)

    static func ocrWindow(ownedBy pid: pid_t?) async throws -> String {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw CaptureError.noScreenPermission
        }

        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let myPID = ProcessInfo.processInfo.processIdentifier
        let candidates = content.windows.filter {
            $0.windowLayer == 0 && $0.frame.width > 200 && $0.frame.height > 150
                && $0.owningApplication?.processID != myPID
        }
        let area: (SCWindow) -> CGFloat = { $0.frame.width * $0.frame.height }
        // Largest window of the frontmost app (the meeting window), else any window.
        guard let window = candidates.filter({ $0.owningApplication?.processID == pid }).max(by: { area($0) < area($1) })
                ?? candidates.first
        else { throw CaptureError.noWindow }

        let config = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false

        // Frame lives only in memory; it is discarded after OCR.
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
        return try await Task.detached(priority: .userInitiated) { try recognizeText(in: image) }.value
    }

    private static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .sorted { $0.boundingBox.minY == $1.boundingBox.minY ? $0.boundingBox.minX < $1.boundingBox.minX
                                                                 : $0.boundingBox.minY > $1.boundingBox.minY }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
