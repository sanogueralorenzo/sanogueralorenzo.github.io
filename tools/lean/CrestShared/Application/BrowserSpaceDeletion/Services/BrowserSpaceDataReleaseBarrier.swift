import Dispatch
import Foundation

@MainActor
enum BrowserSpaceDataReleaseBarrier {
    static let retainedViewReleaseTimeout: Duration = .seconds(2)

    static func waitForRetainedViews(
        _ probes: [BrowserSpaceDataReleaseProbe] = []
    ) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }

        guard probes.contains(where: { !$0.isReleased }) else { return }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: retainedViewReleaseTimeout)
        while clock.now < deadline,
            probes.contains(where: { !$0.isReleased })
        {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
}
