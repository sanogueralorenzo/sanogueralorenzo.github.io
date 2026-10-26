import Foundation
import SwiftUI

struct BrowserUtilityListContent: View {
    let surface: BrowserUtilitySurface
    let space: SpaceModel
    let downloads: [DownloadState]
    let searchText: String
    let filter: BrowserUtilityListFilter
    let actions: BrowserUtilityListActions
    var dismissOnBlankSpace: (() -> Void)? = nil
    /// The images the listed tabs wear, as the read model holds them.
    var favicons: FaviconAssets? = nil
    var preparationClock: BrowserUtilityListClock = .live
    var preparationCalendar: Calendar = .autoupdatingCurrent

    @Environment(\.browserSpaceContentIsLocked) private var isLocked
    @State private var preparedRequest: BrowserUtilityListRequest?
    @State private var sections: [BrowserUtilityListSection] = []

    var body: some View {
        BrowserUtilityListPresentation(
            surface: surface,
            searchText: searchText,
            filter: filter,
            presentationRequest: preparedPresentationRequest,
            sections: sections,
            downloads: isLocked ? [] : downloads,
            actions: actions,
            dismissOnBlankSpace: dismissOnBlankSpace
        )
        .environment(\.browserFavicons, favicons)
        .accessibilityIdentifier(BrowserUtilityAccessibilityID.list(surface))
        .task(id: request) {
            await refreshSections(for: request)
        }
    }

    private var request: BrowserUtilityListRequest {
        BrowserUtilityListRequest(
            surface: surface,
            space: space,
            downloads: downloads,
            searchText: searchText,
            filter: filter,
            isUnlocked: !isLocked
        )
    }

    private var preparedPresentationRequest: BrowserUtilityListRequest? {
        guard let preparedRequest,
            preparedRequest.hasSamePresentationOwnership(as: request)
        else { return nil }
        return preparedRequest
    }

    @MainActor
    private func refreshSections(for request: BrowserUtilityListRequest) async {
        while !Task.isCancelled {
            let now = preparationClock.currentDate()
            await prepareSections(for: request, now: now)
            guard preparationClock.refreshesOverTime,
                !Task.isCancelled,
                let deadline = BrowserUtilityListPreparation.nextRefreshDate(
                    for: request,
                    now: now,
                    calendar: preparationCalendar
                )
            else { return }

            let delay = max(deadline.timeIntervalSinceNow, 0.1)
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
        }
    }

    @MainActor
    private func prepareSections(
        for request: BrowserUtilityListRequest,
        now: Date
    ) async {
        if let preparedRequest,
            preparedRequest.searchText != request.searchText
        {
            try? await Task.sleep(
                for: BrowserUtilityListPreparation.searchDebounce
            )
            guard !Task.isCancelled else { return }
        }
        let calendar = preparationCalendar
        let preparation = Task.detached(priority: .userInitiated) {
            BrowserUtilityListPreparation.sections(
                for: request,
                now: now,
                calendar: calendar
            )
        }
        let preparedSections = await withTaskCancellationHandler {
            await preparation.value
        } onCancel: {
            preparation.cancel()
        }
        guard !Task.isCancelled else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            sections = preparedSections
            preparedRequest = request
        }
    }

}

#Preview("History Results", traits: .fixedLayout(width: 360, height: 420)) {
    if let space = BrowserUtilityListPreviewFixture.historySpaceModel {
        BrowserUtilityListContent(
            surface: .history,
            space: space,
            downloads: [],
            searchText: "",
            filter: .all,
            actions: BrowserUtilityListActions(),
            preparationClock: .fixed(
                BrowserUtilityListPreviewFixture.referenceDate
            ),
            preparationCalendar: BrowserUtilityListPreviewFixture.fixedCalendar
        )
    }
}
