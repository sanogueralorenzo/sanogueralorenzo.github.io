import Foundation

#if os(macOS)
    /// One piece of input an agent asks a page's engine to deliver, which
    /// knows the request that carries it.
    struct EnginePageInput: Sendable {
        // MARK: - Variables

        private let request: @MainActor @Sendable (any EnginePages, _ pageID: UUID, _ inputID: UUID) -> Bool

        // MARK: - Initializers

        private init(request: @escaping @MainActor @Sendable (any EnginePages, UUID, UUID) -> Bool) {
            self.request = request
        }

        // MARK: - Actions - Input

        /// Presses and releases `button` `count` times at `point`.
        static func click(
            at point: PagePoint, button: PointerButton = .primary, count: Int = 1, modifiers: KeyModifiers = []
        ) -> Self {
            Self { pages, pageID, inputID in
                pages.request(
                    ClickPage(
                        pageID: pageID, inputID: inputID, point: point, button: button, count: count,
                        modifiers: modifiers))
            }
        }

        /// Moves the pointer to `point`.
        static func hover(at point: PagePoint) -> Self {
            Self { pages, pageID, inputID in
                pages.request(HoverPage(pageID: pageID, inputID: inputID, point: point))
            }
        }

        /// Scrolls `deltaX` and `deltaY` CSS pixels at `point`.
        static func scroll(at point: PagePoint, deltaX: Double, deltaY: Double) -> Self {
            Self { pages, pageID, inputID in
                pages.request(
                    ScrollPage(pageID: pageID, inputID: inputID, point: point, deltaX: deltaX, deltaY: deltaY))
            }
        }

        /// Types `text` into whatever the page has focused.
        static func type(_ text: String) -> Self {
            Self { pages, pageID, inputID in
                pages.request(TypeInPage(pageID: pageID, inputID: inputID, text: text))
            }
        }

        /// Presses and releases `key` with `modifiers` held.
        static func press(_ key: PageKey, modifiers: KeyModifiers = []) -> Self {
            Self { pages, pageID, inputID in
                pages.request(PressKeyInPage(pageID: pageID, inputID: inputID, key: key, modifiers: modifiers))
            }
        }

        /// Asks `pages` to deliver the input to page `pageID` as `inputID`;
        /// false when the engine refused it.
        @MainActor func send(to pages: any EnginePages, pageID: UUID, inputID: UUID) -> Bool {
            request(pages, pageID, inputID)
        }
    }
#endif
