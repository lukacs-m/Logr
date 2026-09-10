import Logr
import Observation

/// Owns the statistics shown by ``LogViewer``'s summary panel and ``LogStatisticsView``.
///
/// Keeps at most one computation in flight, coalesces requests that arrive while it runs into a
/// single trailing recompute from the latest service state, and publishes every completed result
/// so a cache that keeps changing still shows progress instead of staying empty. ``reset()``
/// invalidates a computation already in flight.
@Observable
final class LogStatisticsRefresher {
    private(set) var statistics: LogStatistics = .empty
    private var isComputing = false
    private var hasPendingRequest = false
    private var generation = 0

    func refresh(from logr: any LogRService, isActive: Bool = true) async {
        guard isActive else {
            reset()
            return
        }
        guard !isComputing else {
            hasPendingRequest = true
            return
        }
        isComputing = true
        defer { isComputing = false }
        repeat {
            hasPendingRequest = false
            let requested = generation
            let updated = await logr.logStatistics()
            guard requested == generation else { return }
            statistics = updated
        } while hasPendingRequest
    }

    func reset() {
        generation += 1
        hasPendingRequest = false
        statistics = .empty
    }
}
