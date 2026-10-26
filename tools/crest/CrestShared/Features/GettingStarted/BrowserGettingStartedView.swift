#if os(macOS)
    import SwiftUI

    struct BrowserGettingStartedView: View {
        let openURL: (URL) -> Void
        @Bindable var state: BrowserGettingStartedState
        private var practice: BrowserGettingStartedPractice { state.practice }
        private var chapter: BrowserGettingStartedChapter {
            get { state.chapter }
            nonmutating set { state.chapter = newValue }
        }
        private var lesson: BrowserGettingStartedLesson {
            get { state.lesson }
            nonmutating set { state.lesson = newValue }
        }

        init(state: BrowserGettingStartedState = BrowserGettingStartedState(), openURL: @escaping (URL) -> Void) {
            self.state = state
            self.openURL = openURL
        }
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 820
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        masthead
                        chapterPicker
                        practiceStage(wide: wide, height: max(560, min(680, geometry.size.height - 175)))
                        footer
                    }
                    .padding(geometry.size.width < 600 ? 20 : 30)
                    .frame(maxWidth: 1240)
                    .frame(maxWidth: .infinity)
                }
                .browserNativeScrollState(state.scroll)
                .contentMargins(.trailing, 8, for: .scrollContent)
                .background(CrestBrandTheme.canvas)
            }
            .environment(practice.sidebarInteraction)
            .onDisappear { practice.sidebarInteraction.cancel() }
            .font(CrestTypography.sans(14))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: chapter)
        }

        /// One window keeps its identity as its position and width change between
        /// chapters. The sidebar can overhang in the tabs lesson; Split View brings
        /// the entire window back into the available canvas.
        private func practiceStage(wide: Bool, height: CGFloat) -> some View {
            GeometryReader { stage in
                let instructionsWidth: CGFloat = wide ? 280 : 220
                let windowX: CGFloat = chapter.showsLessons && wide ? instructionsWidth + 28 : 0
                let windowY: CGFloat = chapter.showsLessons && !wide ? 310 : 0
                ZStack(alignment: .topLeading) {
                    if chapter.showsLessons {
                        VStack(alignment: .leading, spacing: 24) {
                            heading
                            tabLesson
                        }
                        .frame(width: wide ? instructionsWidth : stage.size.width, alignment: .leading)
                        .frame(height: wide ? height : 290, alignment: .center)
                        .transition(.opacity)
                    }
                    BrowserGettingStartedPracticeWindow(practice: practice, showsSplit: chapter.showsSplit)
                        .frame(
                            width: chapter.showsLessons && wide
                                ? max(760, stage.size.width - windowX) : stage.size.width,
                            height: height
                        )
                        .offset(x: windowX, y: windowY)
                }
                .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.9), value: chapter)
            }
            .frame(height: height + (chapter.showsLessons && !wide ? 310 : 0))
            .clipped()
        }

        private var heading: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(chapter.title).font(CrestTypography.display(34))
                Text(chapter.introduction).font(CrestTypography.sans(14)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private var masthead: some View {
            HStack(spacing: 9) {
                CrestStartPageMark().frame(width: 24, height: 28)
                Text("Getting Started").font(CrestTypography.sans(13, weight: .semibold))
                Spacer()
                Button("Reset practice", systemImage: "arrow.counterclockwise") {
                    practice.reset()
                    lesson = .pin
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }

        private var chapterPicker: some View {
            HStack(spacing: 8) {
                ForEach(BrowserGettingStartedChapter.all) { option in
                    chapterButton(option)
                }
            }
        }

        private func chapterButton(_ option: BrowserGettingStartedChapter) -> some View {
            Button {
                selectChapter(option)
            } label: {
                HStack(spacing: 7) {
                    Text(verbatim: String(format: "%02d", option.number)).font(.caption.monospacedDigit()).opacity(0.6)
                    Text(option.pickerTitle).font(CrestTypography.sans(13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(chapter == option ? CrestBrandPalette.ink : .primary)
                .background(
                    chapter == option ? CrestBrandPalette.butter : .primary.opacity(0.04), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(chapter == option ? .isSelected : [])
        }

        private var tabLesson: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("TRY IT").font(CrestTypography.sans(10, weight: .bold)).tracking(1.5).foregroundStyle(
                        .secondary)
                    Spacer()
                    Text("\(lesson.number) / \(BrowserGettingStartedLesson.all.count)").font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(lesson.title).font(CrestTypography.display(25))
                Text(lesson.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        lessonActions
                        Spacer()
                        nextLesson
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        lessonActions
                        nextLesson
                    }
                }
            }

        }

        @ViewBuilder private var lessonActions: some View {
            switch lesson.kind {
            case .pin:
                BrowserGettingStartedPinAction(practice: practice)
            case .save:
                BrowserGettingStartedSaveAction(
                    practice: practice, title: "Save this tab", systemImage: "bookmark.fill")
            case .folders:
                HStack { BrowserGettingStartedFolderActions(practice: practice) }
            case .clear:
                BrowserGettingStartedClearHint()
            }
        }

        private var nextLesson: some View {
            Button(lesson.next == nil ? "Try Split View" : "Next", systemImage: "arrow.right") {
                if let next = lesson.next {
                    lesson = next
                } else {
                    selectChapter(.splitView)
                }
            }.buttonStyle(.crestSecondary)
        }

        private func selectChapter(_ next: BrowserGettingStartedChapter) {
            if next.showsSplit && chapter != next { practice.reset() }
            chapter = next
        }

        private var footer: some View {
            HStack {
                Text("Practice changes affect only this example Space.").font(CrestTypography.sans(12)).foregroundStyle(
                    .secondary)
                Spacer()
                if let next = chapter.next {
                    Button("Next chapter", systemImage: "arrow.right") { selectChapter(next) }.buttonStyle(.plain)
                } else {
                    Text("This guide stays in your Saved tabs.").font(CrestTypography.sans(12, weight: .semibold))
                }
            }
        }
    }

#endif
