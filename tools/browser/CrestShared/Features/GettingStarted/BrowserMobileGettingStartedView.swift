#if os(iOS)
    import SwiftUI

    /// A touch tour backed by the same isolated store and real sidebar as the Mac guide.
    struct BrowserMobileGettingStartedView: View {
        var showsCompactNavigation = false
        @Bindable var state: BrowserGettingStartedState
        private var practice: BrowserGettingStartedPractice { state.practice }
        private var lesson: BrowserGettingStartedLesson {
            get { state.lesson }
            nonmutating set { state.lesson = newValue }
        }

        init(showsCompactNavigation: Bool = false, state: BrowserGettingStartedState = BrowserGettingStartedState()) {
            self.showsCompactNavigation = showsCompactNavigation
            self.state = state
        }
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 700
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 10) {
                            CrestStartPageMark().frame(width: 24, height: 28)
                            Text("Getting Started").font(.headline)
                            Spacer()
                            Button("Reset practice", systemImage: "arrow.counterclockwise") {
                                practice.reset()
                                lesson = .pin
                            }
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                        }
                        if wide {
                            HStack(alignment: .top, spacing: 28) {
                                tabLesson.frame(maxWidth: 300)
                                sidebar.frame(maxWidth: 380).frame(height: 510)
                            }
                        } else {
                            tabLesson
                            sidebar.frame(height: 470)
                        }
                        Text("Practice uses an example Space. Your tabs are unchanged.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("This guide stays in your Saved tabs.")
                            .font(.footnote).foregroundStyle(.secondary)
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "hand.draw")
                                .font(.title2)
                                .foregroundStyle(CrestBrandPalette.coral)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Return to your tabs").font(.headline)
                                Text(
                                    showsCompactNavigation
                                        ? "Swipe up on the URL bar or tap the tabs button on its right to return to your Space and start browsing."
                                        : "Select a tab in the sidebar, or choose New Tab to start browsing."
                                )
                                .font(.subheadline).foregroundStyle(.secondary)
                                Image(systemName: "square.on.square").font(.title3)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CrestBrandTheme.surface, in: .rect(cornerRadius: 16))
                        .accessibilityIdentifier("getting-started-navigation-hint")
                    }
                    .padding(20)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                    .id("mobile-guide-top")
                }
                .browserNativeScrollState(state.scroll)
                .background(CrestBrandTheme.canvas)
            }
            .environment(practice.sidebarInteraction)
            .onDisappear { practice.sidebarInteraction.cancel() }
            .animation(reduceMotion ? nil : CrestMotion.collection, value: practice.space.sidebar.lists.map(\.rows))

        }

        private var sidebar: some View {
            BrowserGettingStartedPracticeSidebar(
                practice: practice,
                capabilities: BrowserInteractionCapabilities(
                    supportsHover: false, supportsTouch: true, pairsRowWithPromotedSurface: false)
            )
            .clipShape(.rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(CrestBrandTheme.line))
            .accessibilityIdentifier("getting-started-practice-sidebar")
        }

        private var tabLesson: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Tabs & folders").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(lesson.number) / \(BrowserGettingStartedLesson.all.count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(lesson.touchTitle).font(CrestTypography.display(28))
                Text(lesson.touchDetail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { lessonActions }
                    VStack(alignment: .leading, spacing: 12) { lessonActions }
                }
                HStack {
                    if let previous = lesson.previous {
                        Button("Previous") { lesson = previous }.frame(minHeight: 44)
                    }
                    Spacer()
                    Button(lesson.next == nil ? "Practice again" : "Next", systemImage: "arrow.right") {
                        if let next = lesson.next {
                            lesson = next
                        } else {
                            practice.reset()
                            lesson = .pin
                        }
                    }
                    .frame(minHeight: 44)
                }
                .font(.subheadline.weight(.semibold))
            }
        }

        @ViewBuilder private var lessonActions: some View {
            switch lesson.kind {
            case .pin:
                BrowserGettingStartedPinAction(practice: practice)
            case .save:
                BrowserGettingStartedSaveAction(
                    practice: practice, title: "Save A weekend away", systemImage: "bookmark")
            case .folders:
                BrowserGettingStartedFolderActions(practice: practice)
            case .clear:
                BrowserGettingStartedCleanUpAction(practice: practice)
            }
        }

    }
#endif
