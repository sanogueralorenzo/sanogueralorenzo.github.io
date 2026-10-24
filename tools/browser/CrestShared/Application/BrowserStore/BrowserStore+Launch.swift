import Foundation

extension BrowserStore {
    // MARK: - Actions - Launch

    /// The destination this launch's first window opens: the core's launch
    /// plan applies the saved startup preference this workspace keeps, the
    /// launch's isolation and whether first-run setup holds the first window
    /// back, which the core decides. A workspace that keeps no preferences
    /// opens the Start Page.
    func startupBehavior(for environment: BrowserLaunchEnvironment) -> StartupBehavior {
        let plan = LaunchPlan(
            workspaceID: family.workspaceID, platform: .current, environment: environment.coreEnvironment)
        return ((try? core.query(plan)) ?? LaunchDecision.unavailable).startup
    }
}
