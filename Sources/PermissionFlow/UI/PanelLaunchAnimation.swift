#if os(macOS)
import AppKit
import Combine
import SpriteKit

/// A continuous mesh lets the leading edge unfold before the trailing edge,
/// without relaying out the live SwiftUI panel at every animation frame.
enum PanelLaunchGeometry {
    static let rows = 32

    /// Reserve space for the arc as well as both endpoint rectangles.
    static func canvas(source: CGRect, target: CGRect) -> CGRect {
        let endpoints = source.union(target)
        let bend = arcOffset(source: source, target: target)
        return endpoints.union(endpoints.offsetBy(dx: bend.x, dy: bend.y)).insetBy(dx: -2, dy: -2)
    }

    /// Start with an upward perpendicular arc (rightward for vertical travel),
    /// then stretch its horizontal sweep. Short trips still get a smaller bend.
    private static func arcOffset(source: CGRect, target: CGRect) -> CGPoint {
        let dx = target.midX - source.midX
        let dy = target.midY - source.midY
        let distance = hypot(dx, dy)
        guard distance > 0 else { return .zero }
        let height = min(140, distance * 0.18)
        let direction: CGFloat = dx < 0 || (dx == 0 && dy > 0) ? -1 : 1
        return CGPoint(x: -dy / distance * height * direction * 2, y: dx / distance * height * direction)
    }

    static func positions(source: CGRect, target: CGRect, canvas: CGRect, progress: Double) -> [SIMD2<Float>] {
        let progress = min(1, max(0, progress))
        let travel = CGFloat(progress * progress * (3 - 2 * progress))
        let arc = 4 * travel * (1 - travel)
        let bend = arcOffset(source: source, target: target)
        // Apply the same offset to every row so the curve cannot fold the mesh.
        return (0...rows).flatMap { row -> [SIMD2<Float>] in
            let fraction = CGFloat(row) / CGFloat(rows)
            let rank = target.midY >= source.midY ? 1 - fraction : fraction
            let phase = min(1, max(0, CGFloat(progress) * 1.3 - rank * 0.3))
            let eased = phase * phase * (3 - 2 * phase)
            let y = source.minY + source.height * fraction
            let targetY = target.minY + target.height * fraction
            return [CGFloat(0), CGFloat(1)].map { edge in
                let x = source.minX + source.width * edge
                let targetX = target.minX + target.width * edge
                return SIMD2(
                    Float((x + (targetX - x) * eased + bend.x * arc - canvas.minX) / canvas.width),
                    Float((y + (targetY - y) * eased + bend.y * arc - canvas.minY) / canvas.height)
                )
            }
        }
    }
}

@available(macOS 13.0, *)
@MainActor
final class PanelLaunchAnimation: NSPanel {
    private let sprite: SKSpriteNode
    private let scene: PanelLaunchScene
    private let animationView: SKView
    private var activationObservers = Set<AnyCancellable>()

    init(image: NSImage, source: CGRect, target: CGRect) {
        let canvas = PanelLaunchGeometry.canvas(source: source, target: target)
        sprite = SKSpriteNode(texture: SKTexture(image: image))
        scene = PanelLaunchScene(size: canvas.size)
        animationView = SKView(frame: CGRect(origin: .zero, size: canvas.size))
        super.init(contentRect: canvas, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Ordering the window must not expose SpriteKit's uninitialized surface.
        alphaValue = 0
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        animationView.allowsTransparency = true
        animationView.isAsynchronous = false
        animationView.preferredFramesPerSecond = 60
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        sprite.anchorPoint = .zero
        sprite.subdivisionLevels = 2
        scene.addChild(sprite)
        contentView = animationView
        update(source: source, target: target, progress: 0)
        animationView.presentScene(scene)
        observeActivationChanges()
    }

    /// Called once after SpriteKit has prepared its first frame.
    var onFirstFrame: (() -> Void)? {
        get { scene.onFirstFrame }
        set { scene.onFirstFrame = newValue }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(source: CGRect, target: CGRect, progress: Double) {
        let canvas = PanelLaunchGeometry.canvas(source: source, target: target)
        if frame != canvas { setFrame(canvas, display: false) }
        scene.size = canvas.size
        sprite.size = canvas.size
        sprite.warpGeometry = SKWarpGeometryGrid(
            columns: 1,
            rows: PanelLaunchGeometry.rows,
            destinationPositions: PanelLaunchGeometry.positions(
                source: source, target: target, canvas: canvas, progress: progress
            )
        )
        if isVisible { orderFrontRegardless() }
    }

    /// Activation can reorder windows while the renderer or main run loop is
    /// still preparing the next animation frame. Restore the overlay immediately
    /// after that handoff without making the panel key or activating its app.
    private func observeActivationChanges() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isVisible else { return }
                self.orderFrontRegardless()
            }
            .store(in: &activationObservers)
    }

    override func close() {
        activationObservers.removeAll()
        scene.onFirstFrame = nil
        animationView.isPaused = true
        animationView.presentScene(nil)
        super.close()
    }
}

@available(macOS 13.0, *)
@MainActor
final class PanelLaunchScene: SKScene {
    var onFirstFrame: (() -> Void)?

    override func didFinishUpdate() {
        let callback = onFirstFrame
        onFirstFrame = nil
        callback?()
    }
}
#endif
