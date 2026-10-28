/// A pause between two destinations coming out of the fan.
struct BrowserUtilityFanWait: BrowserUtilityFanExpansionStep {
    // MARK: - Variables

    let delay: Double

    // MARK: - Actions - Opening

    @MainActor
    func run(on fan: BrowserUtilityFanControl, reduceMotion: Bool) async -> Bool {
        try? await Task.sleep(
            for: .seconds(delay)
        )
        return true
    }
}
