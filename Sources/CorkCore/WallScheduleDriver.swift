import Foundation
import Observation

@MainActor @Observable public final class WallScheduleDriver {
    public private(set) var running = false
    public private(set) var problem: String?
    @ObservationIgnored public var canRun: (() -> Bool)?
    @ObservationIgnored public var onFire: ((RandomizationSchedule) async throws -> Void)?
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var execution: Task<Void, Never>?
    @ObservationIgnored private var current = RandomizationSchedule()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var retryAfter: Date?

    public init() {}
    public func apply(_ schedule: RandomizationSchedule, force: Bool = false) {
        if !force && current == schedule && (timer != nil || running) { return }
        timer?.cancel(); timer = nil; generation = UUID(); current = schedule; retryAfter = nil
        guard schedule.enabled else { problem = nil; return }
        if !running { arm() }
    }
    private func arm() {
        guard current.enabled, !running, timer == nil else { return }
        let schedule = current
        let token = generation
        timer = Task { [weak self] in
            guard let self else { return }
            do {
                guard let planned = try schedule.nextRun ?? schedule.next(after: Date()) else { return }
                let due = max(planned, self.retryAfter ?? .distantPast)
                try await Task.sleep(for: .seconds(max(0, due.timeIntervalSinceNow)))
                try Task.checkCancellation(); guard self.generation == token else { return }
                self.timer = nil
                guard self.canRun?() == true else {
                    self.problem = "Waiting for photos, editing or a save to finish."
                    self.retryAfter = Date().addingTimeInterval(30)
                    self.arm(); self.onChange?(); return
                }
                self.execute(schedule, token: token)
            } catch is CancellationError { }
            catch { self.problem = error.localizedDescription; self.onChange?() }
        }
    }
    private func execute(_ schedule: RandomizationSchedule, token: UUID) {
        running = true; problem = nil; onChange?()
        execution = Task { [weak self] in
            guard let self else { return }
            do { try await self.onFire?(schedule) }
            catch is CancellationError { }
            catch { self.problem = error.localizedDescription }
            self.running = false; self.execution = nil
            if self.generation == token { self.retryAfter = Date().addingTimeInterval(60) }
            self.arm(); self.onChange?()
        }
    }
    public func wake() { apply(current, force: true) }
    public func finish() async { timer?.cancel(); timer = nil; await execution?.value; timer?.cancel(); timer = nil }
    public func stop() { generation = UUID(); timer?.cancel(); execution?.cancel(); timer = nil }
}
