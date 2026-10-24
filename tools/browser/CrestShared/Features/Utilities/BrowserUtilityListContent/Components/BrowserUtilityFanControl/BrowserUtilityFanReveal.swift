import SwiftUI

/// One destination coming out of the fan.
struct BrowserUtilityFanReveal: BrowserUtilityFanExpansionStep {
    // MARK: - Variables

    let surface: BrowserUtilitySurface

    // MARK: - Actions - Opening

    @MainActor
    func run(on fan: BrowserUtilityFanControl, reduceMotion: Bool) async -> Bool {
        guard !Task.isCancelled else { return false }
        withAnimation(
            CrestMotion.utilityFanReveal.unlessReducingMotion(reduceMotion)
        ) {
            _ = fan.revealedSurfaces.insert(surface)
        }
        return true
    }
}
