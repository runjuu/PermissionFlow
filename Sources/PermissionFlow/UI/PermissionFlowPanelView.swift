#if os(macOS)
import SwiftUI

/// Keeps the nested card corners aligned with the panel's inset.
enum PermissionFlowPanelLayout {
    static let cornerRadius: CGFloat = 18
    static let spacing: CGFloat = 8
    static let cardCornerRadius = cornerRadius - spacing
}

@available(macOS 13.0, *)
struct PermissionFlowPanelView: View {
    @ObservedObject var controller: PermissionFlowController

    var body: some View {
        VStack(alignment: .leading, spacing: PermissionFlowPanelLayout.spacing) {
            header
            if let primaryApp = controller.preferredAppURL {
                AppDragItemView(
                    url: primaryApp,
                    localeIdentifier: controller.localeIdentifier
                ) { isDragging in
                    controller.setPanelDragging(isDragging)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(PermissionFlowPanelLayout.spacing)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: PermissionFlowPanelLayout.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    /// Keeps the header logic isolated from the drag card layout.
    private var header: some View {
        HStack(alignment: .top, spacing: 3) {
            HeaderDirectionIcon(
                isDragging: controller.isDraggingApp,
                isPresentationComplete: controller.isPanelPresentationComplete
            )
            Text(headerTitle).font(.system(size: 14))
            Spacer()
            HStack(alignment: .top, spacing: 3) {
                if controller.isSettingsFrontmost == false {
                    Button {
                        controller.reopenCurrentSettingsPane()
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 15, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, .secondary.opacity(0.35))
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    controller.closePanel(returnToPreviousApp: true)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.primary, .secondary.opacity(0.35))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// Builds a markdown-backed localized title such as:
    /// "Drag **Example** to the list above to allow **Accessibility**."
    /// On macOS 27+, the permission name is "Device Control and Data Access".
    private var headerTitle: AttributedString {
        let localizedTemplate = PermissionFlowLocalizer.string(
            "permission_flow.panel.title",
            defaultValue: "Drag **%@** to the list above to allow **%@**.",
            localeIdentifier: controller.localeIdentifier
        )

        let markdown = String(
            format: localizedTemplate,
            locale: localizationLocale,
            appDisplayName,
            paneDisplayTitle
        )

        return (try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }

    /// Prefers the Finder-style display name so the title reads naturally even
    /// when the URL contains a plain bundle filename.
    private var appDisplayName: String {
        guard let appURL = controller.preferredAppURL else {
            return PermissionFlowLocalizer.string(
                "permission_flow.app.this_app",
                defaultValue: "This App",
                localeIdentifier: controller.localeIdentifier
            )
        }

        return FileManager.default.displayName(atPath: appURL.path)
    }

    /// Uses the current pane's localized title so each permission can render a
    /// specific instruction in the shared panel title template.
    private var paneDisplayTitle: String {
        controller.currentPane?.localizedTitle(localeIdentifier: controller.localeIdentifier)
            ?? PermissionFlowLocalizer.string(
                "permission_flow.pane.permission",
                defaultValue: "Permission",
                localeIdentifier: controller.localeIdentifier
            )
    }

    /// Uses the explicitly injected panel locale when available.
    private var localizationLocale: Locale {
        controller.localeIdentifier.map(Locale.init(identifier:)) ?? .current
    }
}

@available(macOS 13.0, *)
private struct HeaderDirectionIcon: View {
    let isDragging: Bool
    let isPresentationComplete: Bool

    @State private var attentionOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldAnimateAttention: Bool {
        isPresentationComplete && !isDragging && !reduceMotion
    }

    var body: some View {
        Image(systemName: "arrowshape.up.fill")
            .font(.system(size: 14, weight: .bold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .offset(y: reduceMotion ? 0 : (isDragging ? -2 : attentionOffset))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.18),
                value: isDragging
            )
            .task(id: shouldAnimateAttention) {
                attentionOffset = 0
                guard shouldAnimateAttention else { return }
                do {
                    // Let the live panel settle after the launch overlay is removed.
                    try await Task.sleep(for: .milliseconds(180))
                    for _ in 0..<2 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            attentionOffset = -3
                        }
                        try await Task.sleep(for: .milliseconds(200))
                        withAnimation(.easeInOut(duration: 0.2)) {
                            attentionOffset = 0
                        }
                        try await Task.sleep(for: .milliseconds(340))
                    }
                } catch {
                    // The replacement task resets the offset when dragging,
                    // dismissal, or Reduce Motion cancels this cue.
                }
            }
            .accessibilityHidden(true)
    }
}
#endif
