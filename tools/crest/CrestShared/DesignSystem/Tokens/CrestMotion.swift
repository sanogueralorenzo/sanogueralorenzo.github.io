import SwiftUI

/// Shared motion roles for Crest-authored transitions.
///
/// Crest names motion by semantic role so chrome, flows, controls, and collection
/// interactions never invent their own pacing. Anything longer belongs to native,
/// system-owned motion.
///
/// Never apply these animations directly. Route every Crest-authored animation
/// through `Animation.unlessReducingMotion(_:)` so the
/// system's Reduce Motion setting can drop the animation entirely:
///
/// ```swift
/// .animation(
///     CrestMotion.pane.unlessReducingMotion(reduceMotion),
///     value: selection
/// )
/// ```
enum CrestMotion {
    /// The deliberate hold that distinguishes a long press from an ordinary tap.
    static let longPressRecognitionDelay: TimeInterval = 0.55
    /// Advancing or retreating a step in a multi-step flow.
    static let stepTransition: TimeInterval = 0.30
    /// A control acknowledging a press.
    static let pressFeedback: TimeInterval = 0.14
    /// A compact control acknowledging a press without moving surrounding chrome.
    static let compactPressFeedback: TimeInterval = 0.12
    /// A dense developer control acknowledging a press.
    static let developerPressFeedback: TimeInterval = 0.16
    /// Hover and selection changes on compact interactive surfaces.
    static let surfaceTransition: TimeInterval = 0.12
    /// Inserting, removing, or reordering items in a collection.
    static let collectionTransition: TimeInterval = 0.22
    /// Morphing the content represented by an active drag preview.
    static let dragPreviewTransition: TimeInterval = 0.18
    /// Selecting a destination or changing a window's browsing mode.
    static let navigationTransition: TimeInterval = 0.28
    /// Showing or hiding the app's primary browser chrome.
    static let chromeTransition: TimeInterval = 0.28
    /// Handing the sidebar surface between its docked and floating placements.
    static let sidebarMorphTransition: TimeInterval = 0.28
    /// Moving page surfaces aside before a floating sidebar attaches to the row.
    static let sidebarDockApproachTransition: TimeInterval = 0.22
    /// The short final handoff from the floating sidebar card to its docked seat.
    static let sidebarDockAttachmentTransition: TimeInterval = 0.16
    /// Letting the undocked sidebar retreat after pointer interaction ends.
    static let sidebarRetreatTransition: TimeInterval = 0.30
    /// Keeps phased sidebar work aligned with the visible geometry handoff.
    static let sidebarMorphCompletionDelay: Duration = .seconds(
        sidebarMorphTransition
    )
    /// Keeps the dock handoff behind the page-surface approach.
    static let sidebarDockApproachCompletionDelay: Duration = .seconds(
        sidebarDockApproachTransition
    )
    /// Keeps the morph alive until the card has finished attaching.
    static let sidebarDockAttachmentCompletionDelay: Duration = .seconds(
        sidebarDockAttachmentTransition
    )
    /// Showing or changing a secondary pane layered over browser chrome.
    static let floatingPaneTransition: TimeInterval = 0.24
    /// Showing or hiding compact toolbars within web content.
    static let toolbarTransition: TimeInterval = 0.24
    /// Removing transient feedback or secondary chrome.
    static let dismissalTransition: TimeInterval = 0.18
    /// Hover feedback for sidebar rows.
    static let hoverTransition: TimeInterval = 0.14
    /// Expanding or collapsing a sidebar disclosure group.
    static let disclosureTransition: TimeInterval = 0.20
    /// Updating an address field's determinate loading fill.
    static let loadingProgressTransition: TimeInterval = 0.22
    /// Selecting a choice within an onboarding flow.
    static let selectionTransition: TimeInterval = 0.20
    /// Applying or removing the persistent visual state of a drag source.
    static let dragSourceTransition: TimeInterval = 0.20
    /// Aligning a programmatically selected item within a scrolling picker.
    static let scrollAlignmentTransition: TimeInterval = 0.24
    /// Handing visible content from the start page to a destination page.
    static let contentNavigationTransition: TimeInterval = 0.42
    /// Settling an interactive horizontal Space swipe.
    static let spaceSwipeTransition: TimeInterval = 0.32
    /// Shaking a control to show a swipe has nowhere further to go.
    static let boundaryShakeTransition: TimeInterval = 0.36
    /// Fading a page in where Reduce Motion stills a slide.
    static let reducedMotionFadeTransition: TimeInterval = 0.2
    /// Presenting Peek inside a Quick Window.
    static let quickPeekEntranceTransition: TimeInterval = 0.34
    /// Revealing initial Peek web content after its first commit.
    static let contentRevealTransition: TimeInterval = 0.12
    /// Updating a favicon-derived palette or comparable content state.
    static let paletteTransition: TimeInterval = 0.18
    /// Revealing or hiding recovery details after a navigation failure.
    static let recoveryTransition: TimeInterval = 0.18
    /// Updating the loaded state rendered inside a pinned-tab tile, or a
    /// comparable state glyph in browser chrome.
    static let contentStateTransition: TimeInterval = 0.22
    /// Presenting transient confirmation feedback in browser chrome.
    static let feedbackPresentationTransition: TimeInterval = 0.22
    /// Dismissing a Peek card back into browser chrome.
    static let peekDismissalTransition: TimeInterval = 0.22
    /// Revealing one destination in the utility fan.
    static let utilityFanRevealTransition: TimeInterval = 0.42
    /// The complete press-and-return cycle for reload feedback.
    static let reloadFeedbackDuration: Duration = .milliseconds(240)
    /// One half of the reload feedback cycle.
    static let reloadFeedbackPhaseDuration: Duration = .milliseconds(120)
    /// SwiftUI animation APIs express the reload phase in seconds.
    static let reloadFeedbackPhaseSeconds: TimeInterval = 0.12

    static var step: Animation { .snappy(duration: stepTransition) }
    /// Uses SwiftUI's native default curve for full onboarding-step changes.
    static var onboardingStep: Animation { .default }
    /// Uses SwiftUI's native snappy curve for progress selection feedback.
    static var onboardingProgress: Animation { .snappy }
    /// Uses SwiftUI's native snappy curve for onboarding presentation state.
    static var onboardingPresentation: Animation { .snappy }
    /// The slow cross-fade between the fields the setup stage wears.
    static var onboardingBackdrop: Animation { .easeInOut(duration: onboardingBackdropFade) }
    static let onboardingBackdropFade: TimeInterval = 1.6
    /// How long the welcome holds each template's field before fading to the next.
    static let onboardingWelcomeHold: Duration = .seconds(7)
    static var press: Animation { .easeOut(duration: pressFeedback) }
    static var compactPress: Animation { .easeOut(duration: compactPressFeedback) }
    static var developerPress: Animation { .snappy(duration: developerPressFeedback) }
    static var surface: Animation { .easeInOut(duration: surfaceTransition) }
    static var collection: Animation { .snappy(duration: collectionTransition) }
    static var dragPreview: Animation { .smooth(duration: dragPreviewTransition) }
    static var navigation: Animation { .snappy(duration: navigationTransition) }
    static var chrome: Animation { .smooth(duration: chromeTransition) }
    static var sidebarMorph: Animation {
        .smooth(duration: sidebarMorphTransition)
    }
    static var sidebarDockApproach: Animation {
        .smooth(duration: sidebarDockApproachTransition)
    }
    static var sidebarDockAttachment: Animation {
        .smooth(duration: sidebarDockAttachmentTransition)
    }
    static var sidebarRetreat: Animation {
        .smooth(duration: sidebarRetreatTransition)
    }
    static var floatingPane: Animation { .smooth(duration: floatingPaneTransition) }
    static var toolbar: Animation { .snappy(duration: toolbarTransition) }
    static var dismissal: Animation { .easeOut(duration: dismissalTransition) }
    static var hover: Animation { .easeInOut(duration: hoverTransition) }
    static var disclosure: Animation { .snappy(duration: disclosureTransition) }
    static var loadingProgress: Animation {
        .smooth(duration: loadingProgressTransition)
    }
    static var selection: Animation { .easeInOut(duration: selectionTransition) }
    static var dragSource: Animation { .snappy(duration: dragSourceTransition) }
    static var scrollAlignment: Animation {
        .snappy(duration: scrollAlignmentTransition, extraBounce: 0)
    }
    static var contentNavigation: Animation {
        .snappy(duration: contentNavigationTransition, extraBounce: 0.04)
    }
    static var spaceSwipe: Animation {
        .snappy(duration: spaceSwipeTransition, extraBounce: 0)
    }
    /// The fade Reduce Motion keeps in place of a slide. Unlike the other
    /// roles it is meant for Reduce Motion, so it is used as it is.
    static var reducedMotionFade: Animation {
        .easeInOut(duration: reducedMotionFadeTransition)
    }
    static var quickPeekEntrance: Animation {
        .smooth(duration: quickPeekEntranceTransition)
    }
    static var contentReveal: Animation {
        .easeOut(duration: contentRevealTransition)
    }
    static var palette: Animation { .easeInOut(duration: paletteTransition) }
    static var recovery: Animation { .easeInOut(duration: recoveryTransition) }
    static var contentState: Animation { .snappy(duration: contentStateTransition) }
    static var feedbackPresentation: Animation {
        .snappy(duration: feedbackPresentationTransition)
    }
    static var peekDismissal: Animation { .snappy(duration: peekDismissalTransition) }
    static var utilityFanReveal: Animation {
        .smooth(duration: utilityFanRevealTransition, extraBounce: 0.05)
    }
    static var reloadTurnOut: Animation {
        .easeOut(duration: reloadFeedbackPhaseSeconds)
    }
    static var reloadTurnIn: Animation {
        .easeIn(duration: reloadFeedbackPhaseSeconds)
    }
}
