#if os(macOS)
import AppKit
import Combine

/// Shared, passive permission observation for UI and feature code. Refresh before
/// protected operations and still handle authorization errors from those operations.
@available(macOS 13.0, *)
@MainActor
public final class PermissionStatusMonitor: ObservableObject {
    private static var monitors: [PermissionFlowPane: PermissionStatusMonitor] = [:]

    public static func shared(for pane: PermissionFlowPane) -> PermissionStatusMonitor {
        if let monitor = monitors[pane] { return monitor }
        let monitor = PermissionStatusMonitor(pane: pane)
        monitors[pane] = monitor
        return monitor
    }

    @Published public private(set) var state: PermissionAuthorizationState = .checking
    /// A recovery suggestion, not evidence that macOS has granted permission.
    @Published public private(set) var shouldSuggestRestart = false

    private let pane: PermissionFlowPane
    private let readState: () -> PermissionAuthorizationState
    private let ticks: () -> AnyPublisher<Date, Never>
    private let now: () -> Date
    private var activation: AnyCancellable?
    private var polling: AnyCancellable?
    private var attempts: Set<UUID> = []
    private var deadline: Date?
    private var awaitingReturn = false

    init(
        pane: PermissionFlowPane,
        readState: (() -> PermissionAuthorizationState)? = nil,
        activations: AnyPublisher<Void, Never> = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification).map { @Sendable _ in () }.eraseToAnyPublisher(),
        ticks: @escaping () -> AnyPublisher<Date, Never> = {
            Timer.publish(every: 1, on: .main, in: .common).autoconnect().eraseToAnyPublisher()
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.pane = pane
        self.readState = readState ?? { PermissionStatusRegistry.provider(for: pane).authorizationState() }
        self.ticks = ticks
        self.now = now
        activation = activations.sink { @Sendable [weak self] in
            // NotificationCenter delivers on the posting thread. Always enter
            // the actor before reading providers or publishing UI state.
            Task { @MainActor [weak self] in self?.didBecomeActive() }
        }
    }

    @discardableResult
    public func refresh() -> PermissionAuthorizationState {
        let result = readState()
        if state != result { state = result }
        if result != .notGranted { shouldSuggestRestart = false }
        if result == .granted {
            awaitingReturn = false
            stopPolling()
        }
        return result
    }

    /// Ownership tokens prevent one controller from stopping another's attempt.
    func beginAuthorization() -> UUID {
        let token = UUID()
        attempts.insert(token)
        awaitingReturn = true
        shouldSuggestRestart = false
        deadline = now().addingTimeInterval(120)
        if refresh() != .granted, polling == nil {
            polling = ticks().sink { [weak self] _ in
                guard let self else { return }
                if let deadline = self.deadline, self.now() >= deadline {
                    self.stopPolling()
                    return
                }
                self.refresh()
            }
        }
        return token
    }

    func endAuthorization(_ token: UUID) {
        attempts.remove(token)
        if attempts.isEmpty { stopPolling() }
    }

    private func didBecomeActive() {
        refresh()
        if awaitingReturn {
            shouldSuggestRestart = pane == .screenRecording && state == .notGranted
            awaitingReturn = false
        }
    }

    private func stopPolling() {
        polling = nil
        deadline = nil
    }
}
#endif
