#if os(macOS)
import AppKit
import Combine
import Foundation
import Testing
@testable import PermissionFlow

@MainActor
private final class MonitorFixture {
    var permission: PermissionAuthorizationState = .notGranted
    var reads = 0
    var date = Date(timeIntervalSince1970: 0)
    let activations = PassthroughSubject<Void, Never>()
    let ticks = PassthroughSubject<Date, Never>()
    lazy var monitor = PermissionStatusMonitor(
        pane: .screenRecording,
        readState: { [unowned self] in reads += 1; return permission },
        activations: activations.eraseToAnyPublisher(),
        ticks: { [unowned self] in ticks.eraseToAnyPublisher() },
        now: { [unowned self] in date }
    )
}

@Test @MainActor
func delayedGrantPublishesWithoutAppActivationAndStopsPolling() {
    let f = MonitorFixture()
    var observed: [PermissionAuthorizationState] = []
    let subscription = f.monitor.$state.sink { observed.append($0) }
    let token = f.monitor.beginAuthorization()
    #expect(f.monitor.state == .notGranted)
    f.permission = .granted
    f.ticks.send(f.date)
    #expect(observed == [.checking, .notGranted, .granted])
    let reads = f.reads
    f.ticks.send(f.date)
    #expect(f.reads == reads)
    f.monitor.endAuthorization(token)
    withExtendedLifetime(subscription) {}
}

@Test @MainActor
func activationDetectsRevocationAfterPollingStops() async {
    let f = MonitorFixture()
    f.permission = .granted
    let token = f.monitor.beginAuthorization()
    f.monitor.endAuthorization(token)
    f.permission = .notGranted
    f.activations.send(())
    await drainActivation()
    #expect(f.monitor.state == .notGranted)
    #expect(!f.monitor.shouldSuggestRestart)
}

@Test @MainActor
func returningDeniedSuggestsRestartWithoutClaimingGrant() async {
    let f = MonitorFixture()
    f.activations.send(())
    await drainActivation()
    #expect(!f.monitor.shouldSuggestRestart)
    let token = f.monitor.beginAuthorization()
    #expect(!f.monitor.shouldSuggestRestart)
    f.monitor.endAuthorization(token)
    f.activations.send(())
    await drainActivation()
    #expect(f.monitor.shouldSuggestRestart)
    #expect(f.monitor.state == .notGranted)
    f.permission = .granted
    f.activations.send(())
    await drainActivation()
    #expect(!f.monitor.shouldSuggestRestart)
}

@Test @MainActor
func ownersSharePollingAndLastOwnerStopsIt() {
    let f = MonitorFixture()
    let first = f.monitor.beginAuthorization()
    let second = f.monitor.beginAuthorization()
    f.monitor.endAuthorization(first)
    let before = f.reads
    f.ticks.send(f.date)
    #expect(f.reads == before + 1)
    f.monitor.endAuthorization(second)
    f.ticks.send(f.date)
    #expect(f.reads == before + 1)
}

@Test @MainActor
func timeoutStopsPollingAndAnotherAttemptCanRestartIt() {
    let f = MonitorFixture()
    let first = f.monitor.beginAuthorization()
    let reads = f.reads
    f.date = f.date.addingTimeInterval(120)
    f.ticks.send(f.date)
    #expect(f.reads == reads)
    let second = f.monitor.beginAuthorization()
    f.permission = .granted
    f.ticks.send(f.date)
    #expect(f.monitor.state == .granted)
    f.monitor.endAuthorization(first)
    f.monitor.endAuthorization(second)
}

@Test @MainActor
func otherPermissionsAndUnknownStatusDoNotSuggestRestart() async {
    let activations = PassthroughSubject<Void, Never>()
    let ticks = PassthroughSubject<Date, Never>()
    for (pane, state) in [(PermissionFlowPane.accessibility, PermissionAuthorizationState.notGranted),
                          (.screenRecording, .unknown)] {
        let monitor = PermissionStatusMonitor(pane: pane, readState: { state },
            activations: activations.eraseToAnyPublisher(), ticks: { ticks.eraseToAnyPublisher() })
        let token = monitor.beginAuthorization()
        activations.send(())
        await drainActivation()
        #expect(!monitor.shouldSuggestRestart)
        monitor.endAuthorization(token)
    }
}
// A task submitted after the notification runs behind its MainActor refresh.
@MainActor
private func drainActivation() async {
    await Task { @MainActor in }.value
}

@Test @MainActor
func backgroundActivationIsDeliveredOnMainActor() async {
    let center = NotificationCenter()
    var permission: PermissionAuthorizationState = .notGranted
    let monitor = PermissionStatusMonitor(pane: .screenRecording,
        readState: { permission },
        activations: center.publisher(for: NSApplication.didBecomeActiveNotification)
            .map { @Sendable _ in () }.eraseToAnyPublisher())
    monitor.refresh()
    permission = .granted
    await Task.detached {
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    }.value
    await drainActivation()
    #expect(monitor.state == .granted)
}
#endif
