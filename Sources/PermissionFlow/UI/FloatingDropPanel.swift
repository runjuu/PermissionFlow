#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

@available(macOS 13.0, *)
@MainActor
final class FloatingDropPanel: NSPanel {
    private weak var panelController: PermissionFlowController?
    private let hostingView: NSHostingView<AnyView>
    private let sizingView: NSHostingView<AnyView>
    private let initialPanelWidth: CGFloat = 420

    /// System Settings has a leading sidebar. Matching the trailing content
    /// area width keeps the floating panel visually aligned with the pane that
    /// the user is actively interacting with.
    private let sidebarWidth: CGFloat = 230
    private let screenInset: CGFloat = 12
    private let minimumPanelHeight: CGFloat = 96
    private let sizingHeightLimit: CGFloat = 4096

    /// Gives the unfolding mesh time to travel while Settings settles.
    private let animationDuration: TimeInterval = 0.72
    private var launchOverlay: PanelLaunchAnimation?
    private var waitingTimer: Timer?
    private var launchTimer: Timer?
    private var launchStartTime: CFTimeInterval = 0
    private var launchFromFrame = NSRect.zero
    private var launchToFrame = NSRect.zero
    private var isAnimatingLaunch = false
    private var localeIdentifier: String?

    init(controller: PermissionFlowController) {
        panelController = controller
        localeIdentifier = controller.localeIdentifier
        let panelView = Self.makePanelView(controller: controller, localeIdentifier: controller.localeIdentifier)
        hostingView = NSHostingView(rootView: panelView)
        sizingView = NSHostingView(rootView: panelView)
        super.init(
            contentRect: CGRect(origin: .zero, size: CGSize(width: initialPanelWidth, height: minimumPanelHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        // Prevent the hosting view from pushing its SwiftUI layout size back
        // onto the enclosing NSWindow. `NSHostingView.sizingOptions` defaults
        // to `[.intrinsicContentSize]` on macOS 13.3+, which makes the host
        // re-advertise the SwiftUI root view's intrinsic size to the window
        // on every layout pass. For the panel content (ultraThinMaterial
        // background + `.fixedSize(vertical: true)` + a markdown-wrapped
        // header `AttributedString`), that intrinsic value diverges from the
        // `sizingView.fittingSize` that `measuredPanelHeight` uses — so the
        // window auto-grows well past the content-size we set, and every
        // subsequent `setFrame(...)` from `snap(to:)` is reverted on the
        // next layout tick, leaving the panel stuck off-screen.
        //
        // Opting out of `.intrinsicContentSize` makes the existing
        // `measuredPanelHeight` → `setContentSize` / `snap(to:)` pipeline the
        // single source of truth for panel geometry.
        if #available(macOS 13.3, *) {
            hostingView.sizingOptions = []
        }
        contentView = hostingView
        setContentSize(CGSize(width: initialPanelWidth, height: measuredPanelHeight(for: initialPanelWidth)))
    }

    /// Updates the locale environment used by the floating panel content.
    func updateLocaleIdentifier(_ localeIdentifier: String?) {
        guard self.localeIdentifier != localeIdentifier else { return }
        self.localeIdentifier = localeIdentifier
        guard let panelController else { return }
        let panelView = Self.makePanelView(controller: panelController, localeIdentifier: localeIdentifier)
        hostingView.rootView = panelView
        sizingView.rootView = panelView
        setContentSize(CGSize(width: frame.width, height: measuredPanelHeight(for: frame.width)))
    }

    /// The panel intentionally stays non-activating so System Settings remains
    /// the visible focus owner underneath it.
    override var canBecomeKey: Bool { false }

    override var canBecomeMain: Bool { false }

    /// If the system temporarily tries to key this panel, immediately ask the
    /// controller to keep System Settings visually frontmost underneath it.
    override func becomeKey() {
        super.becomeKey()
        panelController?.keepSettingsVisible()
    }

    /// Mirrors becomeKey() for main-window promotion attempts so the helper
    /// remains non-disruptive to the actual System Settings interaction.
    override func becomeMain() {
        super.becomeMain()
        panelController?.keepSettingsVisible()
    }

    /// Keeps System Settings visually present when the panel receives a mouse
    /// down event, while still forwarding the event through normal handling.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            panelController?.keepSettingsVisible()
        }
        super.sendEvent(event)
    }

    /// Shows the panel at its current frame without any positioning changes.
    func show() {
        orderFrontRegardless()
    }

    /// Waits for Settings geometry without showing a full-size panel at the button.
    func show(at sourceFrameInScreen: CGRect) {
        stopLaunchAnimation()
        orderOut(nil)
        // Tracking can be unavailable (for example, before Accessibility is
        // granted). Keep the guidance usable even without a destination frame.
        let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.waitingTimer != nil else { return }
                self.waitingTimer = nil
                self.center()
                self.show()
            }
        }
        waitingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Unfurls a snapshot from the button while the live content keeps its final layout.
    func present(from sourceFrameInScreen: CGRect, to settingsFrame: CGRect) {
        stopLaunchAnimation()
        let target = targetFrame(for: settingsFrame)
        setFrame(target, display: false)
        hostingView.layoutSubtreeIfNeeded()

        guard !sourceFrameInScreen.isEmpty,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            alphaValue = 1
            orderFrontRegardless()
            return
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let image = NSImage(size: hostingView.bounds.size)
        image.addRepresentation(bitmap)
        launchFromFrame = sourceFrameInScreen
        launchToFrame = target
        let overlay = PanelLaunchAnimation(image: image, source: sourceFrameInScreen, target: target)
        launchOverlay = overlay
        isAnimatingLaunch = true
        overlay.onFirstFrame = { [weak self, weak overlay] in
            // Hop out of SpriteKit's rendering callback before changing windows.
            Task { @MainActor [weak self, weak overlay] in
                guard let self, let overlay, self.launchOverlay === overlay else { return }
                overlay.alphaValue = 1
                overlay.orderFrontRegardless()
                self.startLaunchClock()
            }
        }
        alphaValue = 0
        orderFrontRegardless()
        overlay.orderFrontRegardless()
    }

    private func startLaunchClock() {
        launchStartTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stepLaunchAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        launchTimer = timer
    }

    override func close() {
        stopLaunchAnimation()
        super.close()
    }

    /// Switches the panel into a drag-friendly mode where mouse events pass
    /// through so System Settings can receive the drop destination interaction.
    func setDraggingPassthrough(_ isDragging: Bool) {
        ignoresMouseEvents = isDragging
        alphaValue = isDragging ? 0.72 : 1.0
        orderFrontRegardless()
    }

    /// Repositions the panel under the latest tracked System Settings frame.
    /// While the launch animation is still running, only the destination is
    /// updated so the motion stays continuous.
    func snap(to settingsFrame: CGRect) {
        let target = targetFrame(for: settingsFrame)
        if isAnimatingLaunch {
            // Tracking updates can arrive during the launch. Updating the final
            // destination preserves the motion instead of abruptly snapping.
            launchToFrame = target
            return
        }

        stopLaunchAnimation()
        setFrame(target, display: false)
        orderFrontRegardless()
    }

    /// Calculates the final panel frame relative to the System Settings window.
    /// The panel aligns to the trailing content area, stays underneath the
    /// window, and is clamped to the visible frame of the matching screen.
    private func targetFrame(for settingsFrame: CGRect) -> CGRect {
        let screenFrame = NSScreen.screens
            .first(where: { $0.frame.intersects(settingsFrame) })?
            .visibleFrame ?? settingsFrame

        // The helper panel is anchored to the trailing content area of System
        // Settings rather than the full window width because the leading
        // sidebar is not the user's active target.
        let contentMinX = settingsFrame.minX + sidebarWidth
        let availableContentWidth = max(240, settingsFrame.width - sidebarWidth)
        let width = min(availableContentWidth, screenFrame.width - (screenInset * 2))
        let height = measuredPanelHeight(for: width)

        // This is the place to tune visual attachment if the panel feels too
        // far from the bottom edge of System Settings.
        //
        // Current behavior:
        //   y = settingsFrame.minY - height
        // means "place the panel immediately below the tracked window frame".
        //
        // If the tracked frame still includes some visual framing/shadow, the
        // panel will look separated by that amount. A manual tweak such as:
        //
        //   y = settingsFrame.minY - height + 28
        //
        // is effectively saying "treat the bottom 28pt as non-visual spacing
        // and pull the panel upward".
        //
        // This is usually a better place for that adjustment than
        // SettingsWindowTracker.appKitScreenFrame(...), because the intent here
        // is clearly visual alignment of the floating panel, not coordinate
        // conversion of the tracked window.
        var origin = CGPoint(
            x: contentMinX,
            y: settingsFrame.minY - height
        )

        origin.x = max(screenFrame.minX + screenInset, min(origin.x, screenFrame.maxX - width - screenInset))
        origin.y = max(screenFrame.minY + screenInset, min(origin.y, screenFrame.maxY - height - screenInset))

        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    /// Measures the SwiftUI content at a specific width so the panel height can
    /// fit its dynamic contents before being positioned or animated.
    private func measuredPanelHeight(for width: CGFloat) -> CGFloat {
        // Constrain the SwiftUI proposal as well as the AppKit frame so
        // fittingSize includes the header wrapping at the displayed width.
        sizingView.rootView = AnyView(hostingView.rootView.frame(width: width))
        sizingView.setFrameSize(NSSize(width: width, height: sizingHeightLimit))
        sizingView.layoutSubtreeIfNeeded()
        return max(minimumPanelHeight, ceil(sizingView.fittingSize.height))
    }

    /// Tracking may move the destination while Settings is opening.
    private func stepLaunchAnimation() {
        guard isAnimatingLaunch else { return }
        let progress = min(1, max(0, (CACurrentMediaTime() - launchStartTime) / animationDuration))
        if progress >= 1 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            setFrame(launchToFrame, display: true)
            alphaValue = 1
            orderFrontRegardless()
            stopLaunchAnimation()
            return
        }
        launchOverlay?.update(source: launchFromFrame, target: launchToFrame, progress: progress)
    }

    private func stopLaunchAnimation() {
        waitingTimer?.invalidate()
        waitingTimer = nil
        launchTimer?.invalidate()
        launchTimer = nil
        isAnimatingLaunch = false
        launchOverlay?.close()
        launchOverlay = nil
        alphaValue = 1
    }

    private static func makePanelView(
        controller: PermissionFlowController,
        localeIdentifier: String?
    ) -> AnyView {
        let view = PermissionFlowPanelView(controller: controller)
        guard let localeIdentifier else { return AnyView(view) }
        return AnyView(view.environment(\.locale, .init(identifier: localeIdentifier)))
    }
}
#endif
