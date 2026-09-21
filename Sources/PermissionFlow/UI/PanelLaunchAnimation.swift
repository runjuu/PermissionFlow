#if os(macOS)
import AppKit
import SpriteKit

/// A continuous mesh lets the leading edge unfold before the trailing edge,
/// without relaying out the live SwiftUI panel at every animation frame.
enum PanelLaunchGeometry {
    static let rows = 32

    static func positions(source: CGRect, target: CGRect, canvas: CGRect, progress: Double) -> [SIMD2<Float>] {
        let progress = min(1, max(0, progress))
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
                    Float((x + (targetX - x) * eased - canvas.minX) / canvas.width),
                    Float((y + (targetY - y) * eased - canvas.minY) / canvas.height)
                )
            }
        }
    }
}

@available(macOS 13.0, *)
@MainActor
final class PanelLaunchAnimation: NSPanel {
    private let sprite: SKSpriteNode
    private let scene: SKScene
    private let animationView: SKView

    init(image: NSImage, source: CGRect, target: CGRect) {
        let canvas = source.union(target).insetBy(dx: -2, dy: -2)
        sprite = SKSpriteNode(texture: SKTexture(image: image))
        scene = SKScene(size: canvas.size)
        animationView = SKView(frame: CGRect(origin: .zero, size: canvas.size))
        super.init(contentRect: canvas, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
        animationView.allowsTransparency = true
        animationView.preferredFramesPerSecond = 60
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        sprite.anchorPoint = .zero
        sprite.subdivisionLevels = 2
        scene.addChild(sprite)
        contentView = animationView
        update(source: source, target: target, progress: 0)
        animationView.presentScene(scene)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(source: CGRect, target: CGRect, progress: Double) {
        let canvas = source.union(target).insetBy(dx: -2, dy: -2)
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
        orderFrontRegardless()
    }

    override func close() {
        animationView.isPaused = true
        animationView.presentScene(nil)
        super.close()
    }
}
#endif
