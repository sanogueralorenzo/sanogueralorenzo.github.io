/// One beat of the utility fan opening. Each step runs itself on the fan, so
/// the fan's opening is its steps run in order.
protocol BrowserUtilityFanExpansionStep: Sendable {
    /// Runs the step on `fan`. Returns false when the opening stops here.
    @MainActor
    func run(on fan: BrowserUtilityFanControl, reduceMotion: Bool) async -> Bool
}
