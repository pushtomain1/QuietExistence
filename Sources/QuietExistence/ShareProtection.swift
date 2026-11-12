
import AppKit

/// Keeps application windows out of supported window-capture APIs.
@MainActor
enum ShareProtection {

    private(set) static var isEnabled = true

    private static var observers: [NSObjectProtocol] = []
    private static var timer: Timer?

    /// Call once during application launch.
    static func install() {

        guard observers.isEmpty else { return }

        let notifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didChangeOcclusionStateNotification
        ]

        for name in notifications {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    sweep()
                }
            }

            observers.append(observer)
        }

        // Fallback for windows created by SwiftUI or AppKit.
        timer = Timer.scheduledTimer(
            withTimeInterval: 2.0,
            repeats: true
        ) { _ in
            MainActor.assumeIsolated {
                sweep()
            }
        }

        sweep()
    }

    /// Enable or disable protection.
    static func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        sweep()
    }

    /// Protect an individual window.
    static func protect(_ window: NSWindow) {
        window.sharingType = isEnabled ? .none : .readOnly
    }

    /// Apply protection to all application windows.
    static func sweep() {

        let target: NSWindow.SharingType =
            isEnabled ? .none : .readOnly

        for window in NSApp.windows {

            guard window.sharingType != target else {
                continue
            }

            window.sharingType = target
        }
    }

    /// Remove observers and timer if protection needs to be stopped.
    static func uninstall() {

        timer?.invalidate()
        timer = nil

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }

        observers.removeAll()
    }
}

/// Window protected immediately after initialization.
@MainActor
final class SecureWindow: NSWindow {

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )

        ShareProtection.protect(self)
    }
}
