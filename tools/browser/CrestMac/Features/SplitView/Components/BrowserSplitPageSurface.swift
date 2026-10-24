import SwiftUI

/// The macOS content area when it is presenting more than one card.
///
/// This is the split half of `BrowserRootPageSurface`'s branch: it composes the
/// shared columns layout with macOS cards and re-establishes, at row level, the
/// two things the single-surface path attaches to its one surface — the
/// utility-fan dismissal on web-content interaction, and the per-card decision
/// about a transparent interior that the start page depends on.
///
/// It also owns everything the pointer does to the row, because both of those
/// things are properties of the row rather than of any one card:
///
/// - **Focus.** One `BrowserSplitCardPointerMonitor` for the window. Cards
///   register their bounds in `cardFrames`, the monitor turns a mouse-down into
///   one of them, and the event continues to the page untouched. The hover path
///   is gated by the Follow Mouse preference and evaluated only when a pointer
///   actually arrives. Both funnel through `focusSplitCard`, which is an ordinary
///   selection change and no-ops on the card that already has focus, so the two
///   inputs can never fight.
/// - **The carry.** A ⇧⌘-held press picks a card up: the same monitor keeps the
///   events, the row draws that member's column as the gap wherever the pointer
///   has taken it, and the release commits the slot the gap is standing in.
///   Nothing is mutated until then — a carry that is cancelled leaves no trace
///   in the session at all.
struct BrowserSplitPageSurface: View {
    let model: BrowserRootModel
    let space: SpaceModel
    /// The presented cards in session order. What the row *draws* is this list
    /// with any carried card moved to the gap.
    let members: [TabStateModel]
    /// The slot a drag in flight would drop into, or `nil` when no drop is
    /// resolved. `BrowserRootPageSurface` owns the decision; the row only draws
    /// it.
    let placeholderIndex: Int?
    let tabPromotionNamespace: Namespace.ID
    /// The chords the window's commands show in a Start Page card's palette.
    let shortcuts: BrowserShortcutStore?
    var appearance = BrowserChromeAppearance()

    /// The core's app preference; an unbound preview store keeps click-to-focus.
    private var appPreferences: BrowserAppPreferenceStore { .shared }
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.browserMacWindows) private var windows
    @State private var cardFrames = BrowserSplitCardFrameRegistry()
    /// Where the card-frame space begins in the window, so a pointer measured in
    /// one can be drawn in the other.
    @State private var surfaceOrigin = CGPoint.zero
    @State private var panelFrame: CGRect?

    private var isSelectedSpace: Bool {
        model.browser.selectedSpaceID == space.id && !model.spaceAccess.isLocked(space)
    }

    private var widthTransaction: Binding<BrowserSplitWidthTransaction> {
        guard !isSelectedSpace else { return model.splitWidthTransactionBinding }
        let persisted = model.browser.shownSplitGroupID(in: space)
            .flatMap { model.windowState?.splitColumnFractions(for: $0) }
        return .constant(
            BrowserSplitWidthTransaction(
                persistedFractions:
                    BrowserSplitColumnLayout.seedFractions(persisted: persisted, memberCount: members.count)))
    }

    var body: some View {
        BrowserSplitColumnsView(
            members: displayMembers,
            focusedTabID: isSelectedSpace ? model.pages.activeTabID : model.browser.selectedTabID(in: space.id),
            frameInsets: appearance.pageInsets(
                docked: model.sidebarPresentation.reservesSidebarWidth, direction: layoutDirection
            ),
            accent: space.settings.look.primaryColor.color,
            placeholderIndex: placeholderIndex,
            liftedTabID: isSelectedSpace ? model.splitCardLift.carriedTabID : nil,
            widthTransaction: widthTransaction,
            onResizeCommit: { if isSelectedSpace { model.commitSplitColumnFractions($0) } },
            onFocus: { if isSelectedSpace { model.focusSplitCard($0) } },
            usesTransparentInnerSurface: usesTransparentInnerSurface,
            content: { member, _ in
                BrowserSplitCardView(
                    tab: member,
                    space: space,
                    browser: model.browser,
                    pages: model.pages,
                    spaceAccess: model.spaceAccess,
                    tabPromotionNamespace: tabPromotionNamespace,
                    startPageFocusRequest:
                        model.chrome.startPageFocusRequest,
                    isCommandPalettePresented:
                        model.chrome.isCommandPalettePresented,
                    commands: model.paletteRegistry(
                        windows: windows, layoutDirection: layoutDirection, shortcuts: shortcuts),
                    cardFrames: cardFrames,
                    focusesOnHover: { focusesOnHover(member.id) },
                    onFocusRequest: { if isSelectedSpace { model.focusSplitCard(member.id) } }
                )
            },
            panel: isSelectedSpace && model.extensionSidePanel.panel != nil
                ? .init(requestedWidth: model.extensionSidePanel.width) : nil,
            onPanelResizeCommit: { model.extensionSidePanel.commitWidth($0) },
            panelContent: {
                if isSelectedSpace, let panel = model.extensionSidePanel.panel {
                    BrowserExtensionSidePanelCard(host: model.extensionSidePanel, panel: panel)
                        // The carry gesture must be able to tell the panel
                        // divider from a card divider.
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: BrowserSplitCardFrameRegistry.coordinateSpace)
                        } action: {
                            panelFrame = $0
                        }
                        .onDisappear { panelFrame = nil }
                }
            }
        )
        .environment(\.browserSplitUsesBorderlessFrame, appearance.borderless)
        .background {
            if isSelectedSpace {
                BrowserSplitCardPointerMonitor(
                    cardFrames: cardFrames,
                    handleMouseDown: handleMouseDown,
                    lift: liftGesture
                )
            }
        }
        // Declared here, on the same view the monitor spans, so a registered card
        // frame and a converted event location share an origin by construction.
        .coordinateSpace(BrowserSplitCardFrameRegistry.coordinateSpace)
        .onGeometryChange(for: CGPoint.self) { proxy in
            proxy.frame(in: .global).origin
        } action: { origin in
            surfaceOrigin = origin
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                model.chrome.handleWebContentInteraction()
            }
        )
        .onChange(of: members.map(\.id), initial: true) { _, identifiers in
            guard isSelectedSpace else { return }
            model.seedSplitColumnFractions()
            // A card that left the row — a sync, another window, a closed tab —
            // is a card with nothing to drop onto and no slot to be put back in.
            if let carried = model.splitCardLift.lift?.tabID,
                !identifiers.contains(carried)
            {
                model.splitCardLift.abandon()
            }
        }
        .onChange(of: isSelectedSpace) { _, selected in
            if selected { model.seedSplitColumnFractions() }
        }
    }

    /// The row as it is drawn: session order, with a carried card moved to the
    /// gap it has reached.
    ///
    /// The carried card is still in the list, at its own identity, which is what
    /// keeps its host — and the live `WKWebView` inside it — alive through a
    /// whole reorder. Once the release settles, the session's own order is the
    /// order already on screen.
    private var displayMembers: [TabStateModel] {
        guard isSelectedSpace, let lift = model.splitCardLift.lift, !lift.isSettling else {
            return members
        }
        return BrowserSplitCardLift.displayMembers(
            members,
            lifted: lift.tabID,
            gapIndex: lift.gapIndex
        )
    }

    private var liftGesture: BrowserSplitCardLiftGesture {
        BrowserSplitCardLiftGesture(
            begin: beginLift,
            update: updateLift,
            drop: dropLift,
            cancel: { model.splitCardLift.cancel() },
            isCarrying: { model.splitCardLift.isCarrying }
        )
    }

    /// The frames of the cards actually on show, by tab.
    ///
    /// The registry is keyed by tab and outlives the cards in it — a member the
    /// row is animating out keeps its frame until SwiftUI runs its disappearance
    /// — so every geometric question the carry asks is asked of the members
    /// rather than of the registry alone.
    private var memberCardFrames: [UUID: CGRect] {
        let frames = cardFrames.frames
        return members.reduce(into: [:]) { result, member in
            result[member.id] = frames[member.id]
        }
    }

    /// A ⇧⌘-held press: picks the card up, or declines and lets the press be an
    /// ordinary click.
    ///
    /// The order is the whole of it, and it is deliberate:
    ///
    /// 1. **Resolve the card** against the row's membership, so the answer is a
    ///    slot as well as a tab and there is no second way to fail.
    /// 2. **Stage the carry**, which mints its identity and changes nothing.
    /// 3. **Ask WebKit for the picture**, issued here inside the mouse-down —
    ///    before the row has been told anything at all.
    /// 4. **Begin the carry**, which is the first thing that changes on screen.
    /// 5. **Focus the card**, last, because focus is a *consequence* of picking a
    ///    card up and never a condition of it. Moving it ahead of the lift makes
    ///    the pickup depend on a selection change that no-ops on the card that
    ///    already has focus, which is precisely the coupling that made the
    ///    focused card behave differently from its neighbours.
    private func beginLift(
        at point: CGPoint,
        modifiers: BrowserKeyboardModifierFlags
    ) -> Bool {
        guard isSelectedSpace else { return false }
        let frames = memberCardFrames
        let card = BrowserSplitCardLift.card(
            at: point,
            members: members,
            cardFrames: frames
        )
        guard
            BrowserSplitCardLift.picksUp(
                modifiers: modifiers,
                isInsideCard: card != nil,
                isOverDivider: BrowserSplitCardLift.isOverDivider(
                    point,
                    orderedCardFrames:
                        BrowserSplitCardLift
                        .orderedMemberFrames(
                            members: members,
                            cardFrames: frames
                        ),
                    panelFrame: panelFrame
                ),
                memberCount: members.count,
                isDraggingSidebarItem:
                    model.sidebarInteraction.sidebarReorderState.isDragging,
                isCommandPalettePresented: model.chrome.isCommandPalettePresented
            ),
            let card
        else { return false }

        let token = model.splitCardLift.reserve()
        loadSnapshot(for: members[card.index], token: token)
        guard
            model.splitCardLift.begin(
                token: token,
                tabID: card.tabID,
                originIndex: card.index,
                cardFrame: card.frame,
                pointer: point,
                surfaceOrigin: surfaceOrigin
            )
        else {
            model.splitCardLift.discard(token)
            return false
        }
        // Picking a card up is a decision about that card, so it becomes the
        // focused one — the same thing an ordinary click on it would have done,
        // and what makes "you are holding this" true of the chrome as well. It
        // is a consequence of the carry, which is why it happens after it.
        model.focusSplitCard(card.tabID)
        return true
    }

    private func updateLift(to point: CGPoint) {
        guard let carried = model.splitCardLift.carriedTabID else { return }
        model.splitCardLift.update(
            pointer: point,
            gapIndex: BrowserSplitCardLift.gapIndex(
                at: point,
                cardFrames: memberCardFrames,
                lifted: carried,
                layoutDirection: layoutDirection
            ),
            surfaceOrigin: surfaceOrigin
        )
    }

    /// The release. The domain clamps the index as well, so the row may hand over
    /// whatever slot the gap ended on without checking the ends first.
    private func dropLift() {
        guard let move = model.splitCardLift.drop() else { return }
        model.browser.moveSplitMember(
            move.tabID,
            toMemberIndex: move.memberIndex,
            matching: BrowserSpaceRuntimeAssignment(space: space)
        )
    }

    /// Asks WebKit for the page as it is drawn right now, and hands it to the
    /// carry when it arrives.
    ///
    /// Issued inside the mouse-down and never awaited: the request is in flight
    /// before the row has been told a card is leaving it, and the card is on the
    /// pointer showing its title and favicon by the time WebKit answers. Putting
    /// a `Task` between the press and the request would spend a main-actor hop
    /// first — the same hop SwiftUI redraws the row in — for no gain the carry
    /// can use.
    ///
    /// The answer is matched against the carry's own token, so a picture asked
    /// for by an earlier pickup of the same card cannot arrive on this one.
    ///
    /// Asked only of a card that is *showing* a live page, which is not the same
    /// question as whether a page exists for it. Selecting a split builds a
    /// `BrowserPage` — and therefore a `WKWebView` — for every member, start
    /// pages included, and a start-page card never loads or even mounts the one
    /// it was given: it draws `BrowserStartPageContent` instead. Snapshotting a
    /// card by page alone therefore pictures a web view that has never rendered
    /// anything, and an empty picture is worse than none — a snapshot that
    /// arrives stands the placeholder down, so the carry shows neither the page
    /// nor the tab it belongs to. The card's own presentation is the authority
    /// on what it is drawing, and it is resolved here by the same policy the card
    /// resolves it with, so the picture and the card cannot disagree.
    private func loadSnapshot(for member: TabStateModel, token: BrowserSplitCardLiftToken) {
        let page = model.pages.presentedPage(
            matching: BrowserTabRuntimeAssignment(tabID: member.id, spaceID: space.id, profileID: space.profileID))
        guard PagePresentation.of(member.surface, page: page).picturesLivePage, let page else { return }
        let lift = model.splitCardLift
        BrowserSplitCardSnapshotLoader.snapshot(of: page) { snapshot in
            guard let snapshot else { return }
            lift.attach(snapshot: snapshot, token: token)
        }
    }

    private func focusesOnHover(_ tabID: UUID) -> Bool {
        isSelectedSpace
            && Self.focusesOnHover(
                followsMouse: appPreferences.splitFocusFollowsMouse,
                isCardFocused: model.pages.activeTabID == tabID,
                isAddressEditing: model.isAddressEditing,
                isDraggingSidebarItem: model.sidebarInteraction.sidebarReorderState.isDragging,
                isCarryingCard: model.splitCardLift.isCarrying,
                isCommandPalettePresented: model.chrome.isCommandPalettePresented
            )
    }

    private func handleMouseDown(_ tabID: UUID) {
        guard
            isSelectedSpace,
            Self.focusesOnClick(
                isCardFocused: model.pages.activeTabID == tabID,
                isDraggingSidebarItem:
                    model.sidebarInteraction.sidebarReorderState.isDragging,
                isCarryingCard: model.splitCardLift.isCarrying,
                isCommandPalettePresented: model.chrome.isCommandPalettePresented
            )
        else { return }
        model.focusSplitCard(tabID)
    }

    /// The transparent-interior decision, made per card rather than once for
    /// the window: a start-page or not-yet-committed card shows the Space's
    /// atmosphere through it while loaded neighbours keep their page background.
    private func usesTransparentInnerSurface(_ member: TabStateModel) -> Bool {
        let page = model.pages.surfacePage(for: member.id, in: space, accessController: model.spaceAccess)
        return BrowserPageSurfacePresentation.usesTransparentInnerSurface(
            isStartPage: member.surface == .startPage,
            hasActivePage: page != nil,
            completedNavigationCount: page?.completedNavigationCount ?? 0
        )
    }
}
