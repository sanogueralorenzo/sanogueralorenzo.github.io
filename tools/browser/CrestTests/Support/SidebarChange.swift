import Foundation

@testable import Crest

/// One kind of change the sidebar's tripwires make, driven through the core.
@MainActor
struct SidebarChange {
    // MARK: - Static Variables

    static let titleReport = SidebarChange(name: "E1 title report") { bench, run in
        bench.report(bench.pages[run % bench.pages.count], title: "Title \(run)")
    }
    static let committedNavigation = SidebarChange(name: "E2 committed navigation") {
        bench, run in
        bench.store.finishNavigation(
            of: bench.pages[run % bench.pages.count], to: URL(string: "https://navigated-\(run).example/")!,
            titled: "Navigated \(run)")
    }
    static let startPageNavigation = SidebarChange(
        name: "E2 Start Page to web page",
        prepare: { bench, _ in
            guard let tabID = bench.store.openSessionTab(.startPage, in: bench.space.id, shouldSelect: false),
                let page = bench.store.openReportingPage(for: tabID, in: bench.space.id)
            else { preconditionFailure("The bench could not open a Start Page.") }
            bench.startPages.append(page)
        },
        perform: { bench, _ in
            guard let page = bench.startPages.last else { return }
            bench.store.finishNavigation(
                of: page, to: URL(string: "https://started-\(bench.startPages.count).example/")!,
                titled: "Started \(bench.startPages.count)")
        })
    static let firstFavicon = SidebarChange(name: "E3 favicon, first") { bench, run in
        bench.showIcon(on: bench.pages[run % bench.pages.count], run: run)
    }
    static let newFavicon = SidebarChange(name: "E3 favicon, replaced") { bench, run in
        bench.showIcon(on: bench.pages[0], run: run + 1)
    }
    static let historyVisit = SidebarChange(name: "E4 history visit") { bench, run in
        bench.store.finishNavigation(
            of: bench.visitPage, to: URL(string: "https://visited-\(run).example/")!, titled: "Visited \(run)")
    }
    static let showAnotherTab = SidebarChange(name: "E5 show another tab") {
        bench, run in
        bench.store.activateSessionTab(bench.currentTabs[10 + run % 2].id, in: bench.space.id)
    }
    static let moveWithinSection = SidebarChange(name: "E6 move within section") {
        bench, run in
        let anchor = bench.currentTabs[run.isMultiple(of: 2) ? 1 : 25]
        _ = bench.store.moveSessionTab(
            bench.currentTabs[20].id, in: bench.space.id, to: .current, before: anchor.id)
    }
    static let collapseFolder = SidebarChange(
        name: "E7 collapse folder"
    ) { bench, run in
        guard let folder = bench.space.folders.models.first(where: { $0.parentID == nil }) else { return }
        bench.store.setFolderCollapsed(folder.id, in: bench.space.id, isCollapsed: run.isMultiple(of: 2))
    }
    static let renameSpace = SidebarChange(name: "E8 rename Space") {
        bench, run in
        bench.store.updateSpaceIdentity(
            bench.space.id, name: "Renamed \(run)", symbol: bench.space.settings.symbol,
            accent: bench.space.settings.accent)
    }
    static let loadingToggle = SidebarChange(name: "E9 loading toggle") { bench, run in
        bench.report(bench.pages[0], isLoading: run.isMultiple(of: 2))
    }
    static let otherWindowSelection = SidebarChange(name: "E10 selection in window B") {
        bench, run in
        bench.other.activateSessionTab(bench.currentTabs[12 + run % 2].id, in: bench.space.id)
    }

    static let all = [
        titleReport, committedNavigation, startPageNavigation, firstFavicon, newFavicon, historyVisit,
        showAnotherTab, moveWithinSection, collapseFolder, renameSpace, loadingToggle, otherWindowSelection,
    ]

    // MARK: - Variables

    let name: String
    let prepare: (@MainActor (SidebarChangeBench, Int) -> Void)?
    let perform: @MainActor (SidebarChangeBench, Int) -> Void

    // MARK: - Initializers

    init(
        name: String,
        prepare: (@MainActor (SidebarChangeBench, Int) -> Void)? = nil,
        perform: @escaping @MainActor (SidebarChangeBench, Int) -> Void
    ) {
        self.name = name
        self.prepare = prepare
        self.perform = perform
    }
}
