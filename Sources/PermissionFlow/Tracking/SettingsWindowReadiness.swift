#if os(macOS)
import CoreGraphics
import Foundation

/// Window-server geometry can arrive before Settings finishes appearing.
/// Require the same opaque, active window to settle before publishing its first frame.
struct SettingsWindowReadiness {
    struct Window {
        let id: CGWindowID
        let frame: CGRect
        let alpha: Double
    }

    private let settlingInterval: TimeInterval = 0.25
    private var candidate: Window?
    private var stableSince: TimeInterval?

    mutating func readyFrame(window: Window?, isActive: Bool, at time: TimeInterval) -> CGRect? {
        guard isActive, let window, window.alpha >= 0.99 else {
            candidate = nil
            stableSince = nil
            return nil
        }
        if candidate?.id != window.id || candidate?.frame != window.frame {
            candidate = window
            stableSince = time
            return nil
        }
        guard let stableSince, time - stableSince >= settlingInterval else { return nil }
        return window.frame
    }
}
#endif
