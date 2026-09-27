#if os(macOS)
import CoreGraphics
import Testing
@testable import PermissionFlow

struct SettingsWindowReadinessTests {
    private let frame = CGRect(x: 200, y: 300, width: 800, height: 500)

    @Test
    func waitsForStableVisibleWindow() {
        var readiness = SettingsWindowReadiness()
        let window = SettingsWindowReadiness.Window(id: 1, frame: frame, alpha: 1)
        #expect(readiness.readyFrame(window: window, isActive: true, at: 0) == nil)
        #expect(readiness.readyFrame(window: window, isActive: true, at: 0.24) == nil)
        #expect(readiness.readyFrame(window: window, isActive: true, at: 0.25) == frame)
    }

    @Test
    func resizingRestartsSettlingInterval() {
        var readiness = SettingsWindowReadiness()
        let openingWindow = SettingsWindowReadiness.Window(id: 1, frame: frame, alpha: 1)
        let finalFrame = CGRect(x: 200, y: 300, width: 800, height: 700)
        let settledWindow = SettingsWindowReadiness.Window(id: 1, frame: finalFrame, alpha: 1)
        #expect(readiness.readyFrame(window: openingWindow, isActive: true, at: 0) == nil)
        #expect(readiness.readyFrame(window: settledWindow, isActive: true, at: 0.2) == nil)
        #expect(readiness.readyFrame(window: settledWindow, isActive: true, at: 0.4) == nil)
        #expect(readiness.readyFrame(window: settledWindow, isActive: true, at: 0.5) == finalFrame)
    }

    @Test
    func replacementWindowWithSameFrameMustSettleAgain() {
        var readiness = SettingsWindowReadiness()
        let first = SettingsWindowReadiness.Window(id: 1, frame: frame, alpha: 1)
        let replacement = SettingsWindowReadiness.Window(id: 2, frame: frame, alpha: 1)
        #expect(readiness.readyFrame(window: first, isActive: true, at: 0) == nil)
        #expect(readiness.readyFrame(window: replacement, isActive: true, at: 0.2) == nil)
        #expect(readiness.readyFrame(window: replacement, isActive: true, at: 0.3) == nil)
        #expect(readiness.readyFrame(window: replacement, isActive: true, at: 0.5) == frame)
    }

    @Test(arguments: ["inactive", "transparent", "missing"])
    func interruptedVisibilityRestartsSettlingInterval(reason: String) {
        var readiness = SettingsWindowReadiness()
        let window = SettingsWindowReadiness.Window(id: 1, frame: frame, alpha: 1)
        #expect(readiness.readyFrame(window: window, isActive: true, at: 0) == nil)
        let interruptedWindow: SettingsWindowReadiness.Window? = switch reason {
        case "missing": nil
        case "transparent": .init(id: 1, frame: frame, alpha: 0.5)
        default: window
        }
        #expect(readiness.readyFrame(window: interruptedWindow, isActive: reason != "inactive", at: 0.2) == nil)
        #expect(readiness.readyFrame(window: window, isActive: true, at: 0.3) == nil)
        #expect(readiness.readyFrame(window: window, isActive: true, at: 0.5) == nil)
        #expect(readiness.readyFrame(window: window, isActive: true, at: 0.6) == frame)
    }

    @Test
    func slowLaunchHasNoElapsedTimeBypass() {
        var readiness = SettingsWindowReadiness()
        let window = SettingsWindowReadiness.Window(id: 1, frame: frame, alpha: 1)
        #expect(readiness.readyFrame(window: nil, isActive: false, at: 0) == nil)
        #expect(readiness.readyFrame(window: window, isActive: false, at: 5) == nil)
        #expect(readiness.readyFrame(window: window, isActive: true, at: 10) == nil)
        #expect(readiness.readyFrame(window: window, isActive: true, at: 10.25) == frame)
    }
}
#endif
