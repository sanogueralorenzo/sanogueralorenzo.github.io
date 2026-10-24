import CoreGraphics

/// How wide a credential prompt is allowed to be.
enum BrowserCredentialPromptWidth: Equatable, Sendable {
    /// Pinned to one exact width. A panel floating over the page has no
    /// container to take its width from, so it decides its own.
    case fixed(CGFloat)

    /// As wide as the container allows, up to this much.
    case bounded(CGFloat)

    /// Whatever the container gives it.
    case flexible

    /// The most width this allows, where it names one at all.
    var boundedWidth: CGFloat? {
        switch self {
        case .fixed(let width), .bounded(let width):
            width
        case .flexible:
            nil
        }
    }
}

/// The surface a shell draws a credential prompt on.
enum BrowserCredentialPromptSurfaceStyle: Equatable, Sendable {
    /// A rounded, stroked panel lifted off the page it floats over.
    case panel

    /// A band across the width of the content, closed by a divider.
    case band
}

/// How a shell says a site holds nothing it can offer.
enum BrowserCredentialSuggestionEmptyStatePresentation: Equatable, Sendable {
    /// A short line beside a quiet glyph. A panel that has nothing to offer
    /// should read as a remark, not as a form.
    case compact

    /// The full sentence, on a row sized like the account rows it stands in
    /// for, so a band does not change height as the vault answers.
    case sentence
}

/// Where a shell puts the save prompt's two actions.
enum BrowserCredentialSaveActionPlacement: Equatable, Sendable {
    /// In the row that opens the prompt, after the title.
    case besideTitle

    /// On a row of their own under everything else, where each one can be a
    /// full target and a large text size can stack them.
    case belowContent
}

/// The drawn geometry of the credential prompts, resolved once per shell rather
/// than spelled out by each fork of a prompt.
///
/// Every prompt holds the same anatomy everywhere — a title row with a close
/// control, an optional cross-origin notice, the prompt's own content, and its
/// failures. What changes between shells is the surface under it, how much room
/// it may claim, and whether its rows have to be aimed at with a finger.
struct BrowserCredentialPromptMetrics: Equatable, Sendable {
    let surfaceStyle: BrowserCredentialPromptSurfaceStyle

    let horizontalPadding: CGFloat

    let verticalPadding: CGFloat

    /// The width a fill prompt — suggestions or strong password — claims.
    ///
    /// The one profile value a shell narrows after resolving it: an anchored
    /// panel takes the width of the field it points at, inside the bounds this
    /// profile already set. Nothing else about a resolved profile moves.
    var fillPromptWidth: BrowserCredentialPromptWidth

    /// Whether a fill prompt is drawn under the field that asked for it rather
    /// than in the place the shell keeps for chrome.
    ///
    /// A pointer can put a panel anywhere and read it where it lands. A touch
    /// shell cannot: a band under a field is a band under the keyboard, or
    /// under the thumb holding the phone.
    let anchorsFillPromptToField: Bool

    /// The least width an anchored fill prompt claims, whatever the field's own
    /// width, or `nil` where the shell never anchors. A search-sized login box
    /// is still a panel with a title, an origin, and a way out.
    let anchoredFillPromptMinimumWidth: CGFloat?

    /// The room a floating prompt keeps between itself and the edges of the
    /// page it floats over. A band meets both edges, so it keeps none.
    let chromeInset: CGFloat

    /// The band the saved-password list is kept inside, or `nil` where the list
    /// simply grows the prompt.
    ///
    /// A pointer shell floats a panel that can be as tall as its content. A
    /// touch shell's prompt pushes the page down, so the list scrolls instead.
    let suggestionListMaximumHeight: CGFloat?

    /// The room a suggestion row keeps above and below itself.
    let suggestionRowVerticalPadding: CGFloat

    /// The height a suggestion row claims, or `nil` where the row keeps the
    /// height its content gives it.
    let suggestionRowMinimumHeight: CGFloat?

    /// The height the loading and empty states claim, so the prompt does not
    /// resize as the vault answers, or `nil` where they size to their text.
    let suggestionStateMinimumHeight: CGFloat?

    /// How the prompt says a site has nothing saved for it.
    let suggestionEmptyStatePresentation: BrowserCredentialSuggestionEmptyStatePresentation

    /// The corner a suggestion row's resting highlight is drawn with, or `nil`
    /// where rows draw none. Only a shell whose pointer can rest over a row
    /// without committing to it has a resting state to draw.
    let suggestionRowHighlightCornerRadius: CGFloat?

    /// How far a row's highlight reaches past the text it is behind. The rows
    /// keep the prompt's own margin, so the highlight is bled back outwards
    /// rather than the text being pushed in.
    let suggestionRowHighlightBleed: CGFloat

    /// Whether an account row files its login under the name it was saved
    /// with. A band's rows are one line tall so that every one of them is a
    /// reachable target; a panel has the room to say which account is which.
    let suggestionRowShowsAccountDetail: Bool

    /// The frame the header's close control claims. A finger needs the full
    /// target; a pointer needs a control the size of the rest of the chrome,
    /// and a 44pt one only pushes the title row apart.
    let closeControlSize: CGFloat

    /// The least width a prompt's own action claims, or `nil` where the action
    /// is already given the whole prompt to fill.
    let actionMinimumWidth: CGFloat?

    /// The most width a prompt's own action may claim. A touch shell spends the
    /// whole band on it; a pointer shell leaves it the width of its label.
    let actionMaximumWidth: CGFloat?

    /// The width the save prompt claims. It carries a title, a destination, and
    /// two actions, so it is given more room than a fill prompt.
    let savePromptWidth: BrowserCredentialPromptWidth

    /// Where the save prompt's actions go.
    let saveActionPlacement: BrowserCredentialSaveActionPlacement

    /// The frame the save prompt's spinner claims while it stands in for the
    /// commit action, or `nil` where it keeps the size its control size gives
    /// it. A touch shell holds the target open so the row does not resize.
    let saveBusyIndicatorSize: CGFloat?

    /// Whether the destination line spells iCloud sync out beside the Space or
    /// folds it into the one sentence.
    let destinationPresentation: BrowserCredentialPromptDestinationPresentation

    /// How the cross-origin warning names the credential it is about.
    let saveCrossOriginSubject: BrowserCredentialPromptCrossOriginSubject

    /// A pointer shell: a fixed-width panel floating over the page, rows sized
    /// by their content, and a list that grows the panel.
    static let pointer = BrowserCredentialPromptMetrics(
        surfaceStyle: .panel,
        horizontalPadding: CrestSpacing.medium,
        verticalPadding: CrestSpacing.medium,
        fillPromptWidth: .fixed(360),
        anchorsFillPromptToField: true,
        anchoredFillPromptMinimumWidth: 264,
        chromeInset: CrestSpacing.medium,
        suggestionListMaximumHeight: nil,
        suggestionRowVerticalPadding: 5,
        suggestionRowMinimumHeight: nil,
        suggestionStateMinimumHeight: nil,
        suggestionEmptyStatePresentation: .compact,
        suggestionRowHighlightCornerRadius: CrestRadius.compact,
        suggestionRowHighlightBleed: 6,
        suggestionRowShowsAccountDetail: true,
        closeControlSize: 28,
        actionMinimumWidth: 44,
        actionMaximumWidth: nil,
        savePromptWidth: .bounded(560),
        saveActionPlacement: .besideTitle,
        saveBusyIndicatorSize: nil,
        destinationPresentation: .separateSyncStatus,
        saveCrossOriginSubject: .definiteCredential
    )

    /// A touch shell: a band across the top of the page, full 44pt targets, and
    /// a list that scrolls rather than pushing the page further down.
    ///
    /// The targets are literals rather than `CrestLayout.minimumHitTarget`, for
    /// the same reason `BrowserFindBarMetrics.touch`'s are: this profile is
    /// compared against from a suite hosted on macOS, where that token resolves
    /// to the pointer shell's 28, and a touch control still has to be 44.
    static let touch = BrowserCredentialPromptMetrics(
        surfaceStyle: .band,
        horizontalPadding: CrestSpacing.large,
        verticalPadding: CrestSpacing.medium,
        fillPromptWidth: .flexible,
        anchorsFillPromptToField: false,
        anchoredFillPromptMinimumWidth: nil,
        chromeInset: 0,
        suggestionListMaximumHeight: 176,
        suggestionRowVerticalPadding: 0,
        suggestionRowMinimumHeight: 44,
        suggestionStateMinimumHeight: 44,
        suggestionEmptyStatePresentation: .sentence,
        suggestionRowHighlightCornerRadius: nil,
        suggestionRowHighlightBleed: 0,
        suggestionRowShowsAccountDetail: false,
        closeControlSize: 44,
        actionMinimumWidth: nil,
        actionMaximumWidth: .infinity,
        savePromptWidth: .flexible,
        saveActionPlacement: .belowContent,
        saveBusyIndicatorSize: 44,
        destinationPresentation: .combinedStatus,
        saveCrossOriginSubject: .currentCredential
    )

    /// The profile a shell draws its credential prompts with.
    ///
    /// Touch decides it for the same reason it decides the find bar's: a prompt
    /// is a column of hit targets before it is a panel, so its sizing follows
    /// the least precise input the shell accepts.
    static func resolve(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserCredentialPromptMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }

    /// This profile with its fill prompts narrowed to an anchored width.
    ///
    /// The width is the only thing the field decides. Everything else about a
    /// prompt under a login box is what the shell already said a prompt is.
    func narrowingFillPrompt(to width: CGFloat) -> BrowserCredentialPromptMetrics {
        var narrowed = self
        narrowed.fillPromptWidth = .fixed(width)
        return narrowed
    }

    // MARK: - Anatomy both shells agree on

    /// The gap between the field and the panel pointing at it. Close enough to
    /// read as attached to the field, far enough that the panel's shadow is
    /// still a shadow rather than a smudge on the input's border.
    static let fieldAnchorGap: CGFloat = 5

    /// The identity mark a fill prompt's header opens with: the site's own
    /// icon where the page has one, and the Space's key where it does not.
    static let headerIdentitySize: CGFloat = 28
    static let headerIdentityIconSize: CGFloat = 16
    static let headerIdentitySymbolSize: CGFloat = 13
    static let headerIdentityCornerRadius = CrestRadius.compact
    static let headerIdentityTintOpacity = 0.14

    /// The account glyph a suggestion row is filed under.
    static let suggestionRowIconSize: CGFloat = 17

    /// The gap between an account's name and the login beneath it.
    static let suggestionRowTextSpacing: CGFloat = 1

    /// The glyph the compact empty state is filed under, sized to sit on the
    /// same line as the remark rather than above it.
    static let suggestionEmptySymbolSize: CGFloat = 12
    static let suggestionEmptySpacing = CrestSpacing.extraSmall

    /// The gap between the prompt's stacked parts.
    static let contentSpacing = CrestSpacing.small

    /// The gap the strong-password prompt keeps instead, its explanation
    /// needing more room from its neighbours than a list of accounts does.
    static let strongPasswordContentSpacing: CGFloat = 10

    /// The gap the save prompt keeps between its title, its destination, its
    /// warnings, and its actions.
    static let savePromptContentSpacing: CGFloat = 9

    /// The gap between the header's symbol, its titles, and its close control.
    static let headerSpacing: CGFloat = 9

    /// The gap between a header's title and the origin beneath it.
    static let headerTextSpacing: CGFloat = 1

    /// The least room kept between a header's titles and its close control.
    static let headerSpacerLength = CrestSpacing.small

    /// The least room kept between the save prompt's title and the actions a
    /// pointer shell draws beside it.
    static let saveHeaderSpacerLength = CrestSpacing.large

    /// The gap between the save prompt's two actions.
    static let saveActionSpacing = CrestSpacing.small

    /// The gap between the destination line's parts.
    static let destinationSpacing: CGFloat = 6

    /// The Space crest drawn on the destination line.
    static let destinationIconSize: CGFloat = 16

    /// The frame a prompt's own controls claim.
    static let controlHitTarget: CGFloat = 44

    static let suggestionRowSpacing: CGFloat = 10

    static let suggestionRowSpacerLength: CGFloat = 10

    /// The panel's corner, stroke, and lift. A band draws none of them, and
    /// neither shell draws the lift once the reader has asked for reduced
    /// transparency.
    static let cornerRadius = CrestRadius.control
    static let strokeWidth: CGFloat = 0.5
    static let shadowOpacity = CrestOpacity.controlShadow
    static let shadowRadius: CGFloat = 14
    static let shadowOffset: CGFloat = 6
}
