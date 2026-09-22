#if os(macOS)
import AppKit
import SpriteKit
import Testing
@testable import PermissionFlow

@Suite(.serialized)
@MainActor
struct PanelLaunchTimingTests {
    @Test
    func launchWaitsForFirstFrameBeforeStartingClock() async throws {
        // Reduced motion intentionally bypasses the launch overlay.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let controller = PermissionFlowController()
        let panel = FloatingDropPanel(controller: controller)
        defer { panel.close() }
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        panel.present(
            from: CGRect(x: 100, y: 400, width: 100, height: 32),
            to: CGRect(x: 200, y: 300, width: 800, height: 500)
        )
        let overlay = try #require(NSApp.windows.first { $0 is PanelLaunchAnimation && !existingWindows.contains(ObjectIdentifier($0)) })
        let view = try #require(overlay.contentView as? SKView)
        let scene = try #require(view.scene)
        view.isPaused = true

        // Delay the renderer longer than the entire launch duration.
        try await Task.sleep(for: .seconds(1))
        #expect(panel.alphaValue == 0)
        #expect(overlay.isVisible)

        // Deliver the rendering lifecycle callback, then allow the clock to run.
        scene.didFinishUpdate()
        await Task.yield()
        #expect(panel.alphaValue == 0)
        try await Task.sleep(for: .seconds(1))
        #expect(panel.alphaValue == 1)
        #expect(!overlay.isVisible)
    }

    @Test
    func firstFrameCallbackIsDeliveredOnlyOnce() {
        let scene = PanelLaunchScene(size: CGSize(width: 100, height: 100))
        var callbacks = 0
        scene.onFirstFrame = { callbacks += 1 }
        scene.didFinishUpdate()
        scene.didFinishUpdate()
        #expect(callbacks == 1)
    }

    @Test
    func closingOverlayCancelsPendingFirstFrameCallback() throws {
        let overlay = PanelLaunchAnimation(
            image: NSImage(size: CGSize(width: 100, height: 100)),
            source: CGRect(x: 0, y: 0, width: 100, height: 32),
            target: CGRect(x: 100, y: 100, width: 300, height: 100)
        )
        let view = try #require(overlay.contentView as? SKView)
        let scene = try #require(view.scene)
        var called = false
        overlay.onFirstFrame = { called = true }
        overlay.close()
        scene.didFinishUpdate()
        #expect(!called)
    }
}
#endif
