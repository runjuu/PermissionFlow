#if os(macOS)
import AppKit
import Foundation

@available(macOS 13.0, *)
public struct PermissionFlowConfiguration: Sendable {
    /// Apps that should already appear in the floating panel.
    public var requiredAppURLs: [URL]

    /// When enabled, tracking can prompt for Accessibility access so AX-based
    /// window observation becomes available immediately.
    public var promptForAccessibilityTrust: Bool

    /// Optional locale identifier injected into the floating panel's SwiftUI
    /// environment to override localization.
    public var localeIdentifier: String?

    /// The host owns saving work and relaunching. No automatic termination occurs.
    public var onRestartRequested: (@MainActor @Sendable () -> Void)?

    public init(
        requiredAppURLs: [URL] = [],
        promptForAccessibilityTrust: Bool = false,
        localeIdentifier: String? = nil,
        onRestartRequested: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.requiredAppURLs = requiredAppURLs
        self.promptForAccessibilityTrust = promptForAccessibilityTrust
        self.onRestartRequested = onRestartRequested
        self.localeIdentifier = localeIdentifier
    }
}
#endif
