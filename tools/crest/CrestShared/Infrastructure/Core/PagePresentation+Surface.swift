import Foundation
import os

/// What a page surface shows, as the core decides it from the tab's surface
/// and what its engine's page reports. Views ask while they render, so each
/// distinct question is asked of the core once.
extension PagePresentation {
    // MARK: - Types

    private struct Question: Hashable {
        let surface: TabSurface?
        let hasPage: Bool
        let hasNavigationFailure: Bool
        let hasProcessFailure: Bool
        let restoresUnloaded: Bool
    }

    // MARK: - Static Variables

    private static let answers = OSAllocatedUnfairLock(initialState: [Question: PagePresentation]())

    // MARK: - Actions - Presenting

    /// What a surface shows for a tab whose surface is `surface`, or for no
    /// tab: whether its engine holds a page for it, whether that page's
    /// navigation or process failed, and whether the surface restores an
    /// unloaded page by itself. A core that cannot answer shows no selection
    /// rather than a surface it did not choose.
    static func of(
        _ surface: TabSurface?, hasPage: Bool, hasNavigationFailure: Bool, hasProcessFailure: Bool,
        restoresUnloaded: Bool = false
    ) -> PagePresentation {
        let question = Question(
            surface: surface, hasPage: hasPage, hasNavigationFailure: hasNavigationFailure,
            hasProcessFailure: hasProcessFailure, restoresUnloaded: restoresUnloaded)
        if let known = answers.withLock({ $0[question] }) { return known }
        guard
            let answer = try? CrestCore.answer(
                PresentPage(
                    surface: surface, hasPage: hasPage, hasNavigationFailure: hasNavigationFailure,
                    hasProcessFailure: hasProcessFailure, restoresUnloaded: restoresUnloaded))
        else { return .noSelection }
        answers.withLock { $0[question] = answer.presentation }
        return answer.presentation
    }
}
