#if os(macOS)
import SwiftUI

/// Place below a permission row when the recovery tip should use its full width.
/// Set `showsRestartHint: false` on the corresponding `PermissionFlowButton`.
@available(macOS 13.0, *)
public struct PermissionFlowRestartHint: View {
    @Environment(\.locale) private var locale
    @ObservedObject private var monitor: PermissionStatusMonitor
    private let onRestartRequested: (@MainActor @Sendable () -> Void)?

    public init(
        pane: PermissionFlowPane,
        onRestartRequested: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.monitor = PermissionStatusMonitor.shared(for: pane)
        self.onRestartRequested = onRestartRequested
    }

    public var body: some View {
        if monitor.shouldSuggestRestart {
            VStack(alignment: .leading, spacing: 4) {
                Text(PermissionFlowLocalizer.string(
                    "permission_flow.screen_recording.restart_hint",
                    defaultValue: "If you’ve enabled Screen Recording, quit and reopen this app to finish applying it.",
                    localeIdentifier: locale.identifier
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let onRestartRequested {
                    Button(PermissionFlowLocalizer.string(
                        "permission_flow.button.quit_and_reopen",
                        defaultValue: "Quit and Reopen",
                        localeIdentifier: locale.identifier
                    ), action: onRestartRequested)
                }
            }
        }
    }
}
#endif
