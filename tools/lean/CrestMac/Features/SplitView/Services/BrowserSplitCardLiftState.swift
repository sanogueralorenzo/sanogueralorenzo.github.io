import AppKit
import Observation

/// The live carry: which card is off the row, where the pointer has taken it,
/// and how the release is settling.
///
/// One per window, owned by the window's root model, because a carry is a
/// property of the content area somebody is pointing at rather than of the
/// session. Two windows presenting the same group carry independently and
/// neither can see the other's gap.
///
/// The state answers *what* is being carried and never *where it may go*: the
/// slot arrives already resolved, from `BrowserSplitCardLift` measuring
/// the pointer against the frames the row registered. Keeping resolution out
/// here is what lets the whole geometry be exercised without a carry, and the
/// whole carry be exercised without a window.
///
/// ## The whole state machine
///
/// A pickup is two steps, the same stage-then-promote contract the sidebar's
/// reorder uses, and for the same reason: the pickup has work to do — asking
/// WebKit for a picture — that must happen *before* anything changes on screen,
/// and that work needs an identity to belong to before the carry exists.
///
/// ```
/// idle ──reserve()──▶ staged ──begin(token:)──▶ carrying ──drop()───▶ settling ──▶ idle
///   ▲                   │                          │  ──cancel()──▶ settling ──▶ idle
///   │                   │                          │  ──abandon()──────────────▶ idle
///   └───discard(token)──┘                          └──reserve()/begin() ────────▶ carrying
/// ```
///
/// Every entry has a guaranteed exit and no state is duplicated anywhere else.
/// `isCarrying` is the single answer to "does the pointer belong to a carry", so
/// the event monitor asks rather than remembering — a monitor with its own copy
/// of that boolean is a monitor that can be left swallowing events for a carry
/// that has already ended, which is exactly how a window ends up unable to pick
/// anything up ever again.
///
/// A staged pickup holds nothing on screen and mutates nothing. Refusing one is
/// therefore free: `discard` returns the state to idle with no trace, and any
/// image the refused pickup asked for is refused on arrival because no carry
/// bears its token.
@Observable
@MainActor
final class BrowserSplitCardLiftState {
    private(set) var lift: BrowserSplitCardLift?

    /// The pickup that has been staged but has not yet become a carry, if any.
    ///
    /// At most one: a second press arrives only after the first has been
    /// resolved, and staging again supersedes rather than accumulates.
    @ObservationIgnored private var stagedToken: BrowserSplitCardLiftToken?

    /// Monotonic, so a token is never reused and a stale answer can only fail to
    /// match.
    @ObservationIgnored private var issuedTokens: UInt64 = 0

    /// Clears the lift once its settle has finished playing.
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    /// The card the row must draw as a gap: one that is genuinely away, not one
    /// whose preview is still fading onto the slot it has already returned to.
    var carriedTabID: UUID? {
        guard let lift, !lift.isSettling else { return nil }
        return lift.tabID
    }

    /// Whether a card is on the pointer right now, which every pointer-driven
    /// focus path has to stand aside for — and the only answer to whether the
    /// pointer's events belong to a carry.
    var isCarrying: Bool {
        carriedTabID != nil
    }

    /// Stage a pickup: mint the identity its snapshot request will be matched
    /// against, before a single thing changes on screen.
    ///
    /// Deliberately inert. Nothing is drawn, nothing is mutated, and an existing
    /// carry is left exactly as it was, so a pickup that turns out to be refused
    /// costs nothing and takes nothing down with it.
    func reserve() -> BrowserSplitCardLiftToken {
        issuedTokens += 1
        let token = BrowserSplitCardLiftToken(sequence: issuedTokens)
        stagedToken = token
        return token
    }

    /// Promote a staged pickup into a carry. `cardFrame` and `pointer` share the
    /// split surface's card-frame space; `surfaceOrigin` is where that space
    /// begins in the window.
    ///
    /// Refuses any token that is not the one currently staged, which is what
    /// makes a second promotion of the same pickup — or a promotion of a pickup
    /// that was already discarded — impossible rather than merely unlikely.
    @discardableResult
    func begin(
        token: BrowserSplitCardLiftToken,
        tabID: UUID,
        originIndex: Int,
        cardFrame: CGRect,
        pointer: CGPoint,
        surfaceOrigin: CGPoint
    ) -> Bool {
        guard stagedToken == token else { return false }
        stagedToken = nil
        settleTask?.cancel()
        settleTask = nil
        lift = BrowserSplitCardLift(
            token: token,
            tabID: tabID,
            originIndex: originIndex,
            cardSize: cardFrame.size,
            grabFraction: BrowserSplitCardLift.grabFraction(
                pointer: pointer,
                in: cardFrame
            ),
            surfaceOrigin: surfaceOrigin,
            pointer: pointer,
            gapIndex: originIndex,
            snapshot: nil
        )
        return true
    }

    /// A staged pickup that never became one: the press was over a divider, over
    /// no card, or the row could not spare the card after all.
    func discard(_ token: BrowserSplitCardLiftToken) {
        guard stagedToken == token else { return }
        stagedToken = nil
    }

    /// One pointer sample, with the slot it resolved to and where the space it
    /// was measured in currently begins.
    ///
    /// A carry that has left the row is not a carry that has ended: the slot is
    /// whatever the pointer's horizontal position says about the neighbours,
    /// wherever on screen the pointer happens to be, and a release far away
    /// commits that same slot. There is no "outside" and nothing to explain
    /// about where a drop stops counting.
    func update(pointer: CGPoint, gapIndex: Int, surfaceOrigin: CGPoint) {
        guard var lift, !lift.isSettling else { return }
        lift.pointer = pointer
        lift.gapIndex = gapIndex
        lift.surfaceOrigin = surfaceOrigin
        self.lift = lift
    }

    /// WebKit's answer to the snapshot the pickup asked for.
    ///
    /// Matched on the carry's own token rather than on the tab, so a picture
    /// asked for by an earlier pickup of the same card — or by a pickup that was
    /// refused — can never be crossfaded onto this one.
    ///
    /// A settling carry still accepts it. The preview is still on screen while
    /// it descends, and the page arriving a frame late is worth showing for that
    /// frame; refusing it is how a short press ends up having shown nothing but
    /// an empty card for its whole life.
    func attach(snapshot: NSImage, token: BrowserSplitCardLiftToken) {
        guard var lift, lift.token == token else { return }
        lift.snapshot = snapshot
        self.lift = lift
    }

    /// Puts the card down, and says which slot to commit.
    ///
    /// The move is the caller's to make. This only stops the carry — the row
    /// puts the card back on show in the slot the gap was already holding, and
    /// the preview fades off it.
    func drop() -> (tabID: UUID, memberIndex: Int)? {
        guard let lift, !lift.isSettling else { return nil }
        beginSettling()
        return (lift.tabID, lift.gapIndex)
    }

    /// Escape, a right-click, a window that stopped being key, or anything else
    /// that ends the carry without a move. The row returns the card to the slot
    /// it came from with the same settle motion a neighbour steps aside with,
    /// and nothing is mutated.
    ///
    /// Safe with nothing in flight, and safe twice: a cancel that finds no carry
    /// leaves the state idle rather than staging one.
    func cancel() {
        stagedToken = nil
        guard let lift, !lift.isSettling else { return }
        beginSettling()
    }

    /// Ends the carry outright, with nothing to settle onto: the window stopped
    /// existing, or the card is no longer one of the cards on show.
    func abandon() {
        stagedToken = nil
        settleTask?.cancel()
        settleTask = nil
        lift = nil
    }

    private func beginSettling() {
        guard var lift else { return }
        lift.isSettling = true
        self.lift = lift
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(CrestMotion.collectionTransition))
            guard !Task.isCancelled else { return }
            self?.lift = nil
        }
    }
}
