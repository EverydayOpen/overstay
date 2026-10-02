import Dispatch
import Foundation
import OverstayCore

/// The real system behind the `Backend` seam: libproc for scanning, `Signaller` + `ActivityStore` for stopping.
public enum LiveBackend {
    public static func make() -> Backend {
        Backend(
            scan: {
                // Blocking libproc work stays off the main thread and off the cooperative pool.
                await withCheckedContinuation { (c: CheckedContinuation<RawScan, Never>) in
                    DispatchQueue.global(qos: .userInitiated).async { c.resume(returning: ProcessScanner.scan()) }
                }
            },
            stop: { plan, prefs, progress in
                // Fail closed: no log, no stop (BUILD_PLAN §3 rule 14).
                do { try ActivityStore.prepare() } catch {
                    let started = Date()
                    let results = plan.targets.map {
                        TargetOutcome(target: $0, status: .blocked, detail: "Activity log is not writable")
                    }
                    results.forEach(progress)
                    return StopOutcome(batchID: plan.batchID, mode: plan.mode, startedAt: started, finishedAt: Date(),
                                       results: results, skipped: plan.skipped)
                }
                return await Signaller.run(plan, prefs: prefs, now: { Date() }, progress: progress)
            },
            loadLog: { ActivityStore.load() },
            isDemo: false)
    }
}
