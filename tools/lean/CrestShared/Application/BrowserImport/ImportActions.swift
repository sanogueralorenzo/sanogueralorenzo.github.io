import Foundation

protocol BrowserImportIntent: Sendable {
    @MainActor func apply(to store: NativeBrowserImport) throws
}

struct StartBrowserImport: BrowserImportIntent, Equatable, Sendable {
    let workspaceID: UUID
}

struct OfferImportSources: BrowserImportIntent, Equatable, Sendable {
    let installed: [ImportSource]
}

struct ToggleImportSource: BrowserImportIntent, Equatable, Sendable {
    let source: ImportSource
}

struct ContinueImport: BrowserImportIntent, Equatable, Sendable {
}

struct ShowImportStep: BrowserImportIntent, Equatable, Sendable {
    let step: ImportStep
}

struct CancelImportRead: BrowserImportIntent, Equatable, Sendable {
}

struct FailImport: BrowserImportIntent, Equatable, Sendable {
    let source: ImportSource
    let reason: ImportFailureReason
    let detail: String?
}

struct ReviewImport: BrowserImportIntent, Equatable, Sendable {
    let source: ImportSource
    let spaces: [SpaceState]
    let extensions: [ImportSpaceExtensions]?
    let leftOut: [ImportLeftOut]?
    let title: String?
}

struct ChooseImportDestination: BrowserImportIntent, Equatable, Sendable {
    let sourceSpaceID: UUID
    let destinationSpaceID: UUID?
}

struct IncludeImportTabs: BrowserImportIntent, Equatable, Sendable {
    let sourceSpaceID: UUID
    let tabIDs: [UUID]
    let included: Bool
}

struct PlaceImportTab: BrowserImportIntent, Equatable, Sendable {
    let sourceSpaceID: UUID
    let tabID: UUID
    let placement: TabPlacement
}

struct IncludeImportSpace: BrowserImportIntent, Equatable, Sendable {
    let sourceSpaceID: UUID
    let included: Bool
}

struct IncludeImportExtension: BrowserImportIntent, Equatable, Sendable {
    let sourceSpaceID: UUID
    let extensionID: String
    let included: Bool
}

struct CustomizeImportSpace: BrowserImportIntent, Equatable, Sendable {
    let sourceSpaceID: UUID
    let customization: SpaceCustomization
}

struct ShowImportSpace: BrowserImportIntent, Equatable, Sendable {
    let sourceSpaceID: UUID
}

struct BeginImportCommit: BrowserImportIntent, Equatable, Sendable {
}

struct FinishImportCommit: BrowserImportIntent, Equatable, Sendable {
}

extension StartBrowserImport {
    @MainActor func apply(to store: NativeBrowserImport) throws { try store.start(workspaceID) }
}
extension OfferImportSources {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.revise { flow, _ in
            flow.offered = installed
            flow.selected = installed.filter(flow.selected.contains)
        }
    }
}
extension ToggleImportSource {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.revise { flow, _ in
            try NativeBrowserImport.requireIdle(flow)
            if let index = flow.selected.firstIndex(of: source) {
                flow.selected.remove(at: index)
            } else {
                flow.selected.append(source)
            }
            let offered = flow.offered
            flow.selected.sort { (offered.firstIndex(of: $0) ?? .max) < (offered.firstIndex(of: $1) ?? .max) }
            flow.step = .importBrowser
            flow.phase = .idle
            flow.queue = ImportQueue(sources: flow.offered.filter(flow.selected.contains), index: 0)
            flow.source = nil
            flow.review = nil
            flow.failure = nil
        }
    }
}
extension ContinueImport {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.revise { flow, _ in
            try NativeBrowserImport.requireIdle(flow)
            guard !flow.selected.isEmpty else { return }
            let queue: ImportQueue
            if let current = flow.queue, current.current != nil,
                Set(current.sources.dropFirst(current.index)) == Set(flow.selected)
            {
                queue = current
            } else {
                queue = ImportQueue(sources: flow.offered.filter(flow.selected.contains), index: 0)
            }
            flow.queue = queue
            flow.step = .importBrowser
            guard let source = queue.current else {
                flow.phase = .idle
                flow.failure = ImportFailure(reason: .sourceUnavailable, source: nil, detail: nil)
                return
            }
            flow.phase = .reading
            flow.source = source
            flow.failure = nil
        }
    }
}
extension ShowImportStep {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.revise { flow, _ in
            try NativeBrowserImport.requireIdle(flow)
            guard step != .review || flow.review != nil else { return }
            flow.step = step
            flow.phase = step == .review ? .reviewing : .idle
        }
    }
}
extension CancelImportRead {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.revise { flow, _ in
            guard flow.phase == .reading else { return }
            flow.phase = .idle
            flow.step = .importBrowser
            flow.source = nil
            flow.failure = nil
        }
    }
}
extension FailImport {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.revise { flow, _ in
            flow.failure = ImportFailure(reason: reason, source: source, detail: detail)
            if reason.returnsToReview && flow.review != nil {
                flow.step = .review
                flow.phase = .reviewing
            } else {
                flow.step = .importBrowser
                flow.phase = .idle
                flow.source = nil
            }
        }
    }
}
extension ReviewImport {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.revise { flow, context in
            guard flow.phase == .reading, flow.source == source else { return }
            try NativeBrowserImport.validate(spaces)
            flow.review = ImportReview.started(self, over: context)
            flow.step = .review
            flow.phase = .reviewing
            flow.failure = nil
        }
    }
}
extension ChooseImportDestination {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.revise { flow, context in
            try NativeBrowserImport.requireIdle(flow)
            guard var review = flow.review else { return }
            let destination = destinationSpaceID.flatMap { id in context.destinations.first { $0.id == id } }
            guard destinationSpaceID == nil || destination != nil else { return }
            review.edit(sourceSpaceID, over: context) { space in
                space.destinationID = destination?.id
                space.customization = SpaceCustomization(name: destination?.settings.name ?? space.source.settings.name)
            }
            flow.review = review
        }
    }
}
extension IncludeImportTabs {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.edit(sourceSpaceID) { space, _ in
            let changed = Set(space.source.tabs.map(\.id)).intersection(tabIDs)
            guard !changed.isEmpty else { return }
            if included {
                space.included = true
                space.includedTabIDs = space.ordered(Set(space.includedTabIDs).union(changed))
            } else {
                space.includedTabIDs.removeAll(where: changed.contains)
            }
        }
    }
}
extension PlaceImportTab {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.edit(sourceSpaceID) { space, _ in
            guard space.source.tabs.contains(where: { $0.id == tabID }) else { return }
            space.included = true
            space.includedTabIDs = space.ordered(Set(space.includedTabIDs + [tabID]))
            space.placements.removeAll { $0.tabID == tabID }
            space.placements.append(TabPlacementChoice(tabID: tabID, placement: placement))
        }
    }
}
extension IncludeImportSpace {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.edit(sourceSpaceID) { space, _ in
            space.included = included
            space.includedTabIDs =
                included ? space.source.tabs.map(\.id).filter { !space.duplicateTabIDs.contains($0) } : []
        }
    }
}
extension IncludeImportExtension {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.edit(sourceSpaceID) { space, _ in
            guard space.extensions.contains(where: { $0.extensionID == extensionID }) else { return }
            space.includedExtensionIDs.removeAll { $0 == extensionID }
            if included { space.includedExtensionIDs.append(extensionID) }
        }
    }
}
extension CustomizeImportSpace {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.edit(sourceSpaceID) { space, _ in space.customization = customization }
    }
}
extension ShowImportSpace {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.revise { flow, _ in
            if flow.review?.spaces.contains(where: { $0.source.id == sourceSpaceID }) == true {
                flow.review?.shownSpaceID = sourceSpaceID
            }
        }
    }
}
extension BeginImportCommit {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.revise { flow, _ in
            try NativeBrowserImport.requireIdle(flow)
            guard let review = flow.review else { throw NativeBrowserImport.Failure.notOpen }
            guard review.hasIncludedSpaces else { throw Rejection.noIncludedSpaces(NoIncludedSpaces()) }
            flow.phase = .committing
            flow.failure = nil
        }
    }
}
extension FinishImportCommit {
    @MainActor func apply(to store: NativeBrowserImport) throws {
        try store.revise { flow, _ in
            guard flow.phase == .committing, let review = flow.review else { return }
            flow.summary = ImportSummary(
                tabCount: review.includedTabCount, spaceCount: review.spaces.filter(\.included).count)
            flow.selected.removeAll { $0 == review.source }
            if flow.queue != nil { flow.queue!.index += 1 }
            flow.phase = .idle
            flow.source = nil
            flow.review = nil
            flow.failure = nil
            if let next = flow.queue?.current {
                flow.step = .importBrowser
                flow.phase = .reading
                flow.source = next
            } else {
                flow.step = .complete
            }
        }
    }
}
