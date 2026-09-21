#if os(macOS)
import AppKit
import Testing
@testable import PermissionFlow

@Test
func launchMeshStartsAtButtonAndEndsAtPanel() {
    let source = CGRect(x: -800, y: 400, width: 120, height: 28)
    let target = CGRect(x: 200, y: 100, width: 500, height: 160)
    let canvas = source.union(target)
    for (progress, expected) in [(0.0, source), (1.0, target)] {
        let positions = PanelLaunchGeometry.positions(source: source, target: target, canvas: canvas, progress: progress)
        for row in 0...PanelLaunchGeometry.rows {
            for edge in 0...1 {
                let point = positions[row * 2 + edge]
                let x = CGFloat(point.x) * canvas.width + canvas.minX
                let y = CGFloat(point.y) * canvas.height + canvas.minY
                #expect(abs(x - (expected.minX + expected.width * CGFloat(edge))) < 0.001)
                #expect(abs(y - (expected.minY + expected.height * CGFloat(row) / CGFloat(PanelLaunchGeometry.rows))) < 0.001)
            }
        }
    }
}

@Test(arguments: [CGFloat(-500), CGFloat(0), CGFloat(500)])
func launchMeshRemainsOrderedAndInsideCanvas(verticalTravel: CGFloat) {
    let source = CGRect(x: -600, y: 100, width: 100, height: 32)
    let target = CGRect(x: 200, y: 100 + verticalTravel, width: 480, height: 160)
    let canvas = source.union(target)
    for step in 0...100 {
        let positions = PanelLaunchGeometry.positions(source: source, target: target, canvas: canvas, progress: Double(step) / 100)
        for row in 0...PanelLaunchGeometry.rows {
            let left = positions[row * 2]
            let right = positions[row * 2 + 1]
            #expect(left.x < right.x)
            #expect(left.y == right.y)
            #expect(left.x >= 0 && right.x <= 1 && left.y >= 0 && left.y <= 1)
            if row > 0 { #expect(left.y > positions[(row - 1) * 2].y) }
        }
    }
}

@Test @MainActor
func floatingPanelStaysAboveOrdinaryWindowsWhileDragging() {
    let panel = FloatingDropPanel(controller: PermissionFlowController())
    defer { panel.close() }
    #expect(panel.level == .screenSaver)
    #expect(!panel.canBecomeKey)
    panel.setDraggingPassthrough(true)
    #expect(panel.ignoresMouseEvents)
    #expect(panel.level == .screenSaver)
    panel.setDraggingPassthrough(false)
    #expect(!panel.ignoresMouseEvents)
    #expect(panel.level == .screenSaver)
}
@Test @MainActor
func closingPanelCancelsLaunchOverlay() {
    let panel = FloatingDropPanel(controller: PermissionFlowController())
    panel.present(
        from: CGRect(x: 100, y: 400, width: 100, height: 32),
        to: CGRect(x: 200, y: 300, width: 800, height: 500)
    )
    panel.close()
    #expect(!panel.isVisible)
    #expect(!NSApp.windows.contains { $0 is PanelLaunchAnimation && $0.isVisible })
}

@Test @MainActor
func closingPanelCancelsWaitingFallback() async throws {
    let panel = FloatingDropPanel(controller: PermissionFlowController())
    panel.show(at: CGRect(x: 100, y: 400, width: 100, height: 32))
    panel.close()
    try await Task.sleep(for: .milliseconds(1200))
    #expect(!panel.isVisible)
}
#endif
