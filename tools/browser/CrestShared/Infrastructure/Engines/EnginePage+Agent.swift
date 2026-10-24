import Foundation

#if os(macOS)
    /// What an agent the person allowed asks of one page's engine: scripts in
    /// the agent's own world or the page's, input, the page's console and
    /// network activity, and rendering while no window shows the page. Like
    /// the rest of the direct path, none of it changes browser state.
    extension EnginePage {
        // MARK: - Actions - Scripts

        /// Runs `source`, the body of an async function, in the page's main
        /// frame in `world`, and answers how it settled, or nil when the page
        /// has no document, went away, or took longer than `timeout`.
        func evaluate(
            _ source: String, in world: PageScriptWorld, timeout: Duration
        ) async -> PageScriptEvaluated? {
            let evaluationID = UUID()
            return await withCheckedContinuation { continuation in
                agentWaits.wait(forEvaluation: evaluationID, continuation)
                guard !closed,
                    pages.request(
                        EvaluatePageScript(pageID: id, evaluationID: evaluationID, source: source, world: world))
                else {
                    agentWaits.expire(evaluationID)
                    return
                }
                expire(evaluationID, after: timeout)
            }
        }

        // MARK: - Actions - Input

        /// Delivers `input` to the page, and answers how it went, or nil when
        /// the engine refused it, the page went away, or it took longer than
        /// `timeout`.
        func deliver(_ input: EnginePageInput, timeout: Duration) async -> PageInputDelivered? {
            let inputID = UUID()
            return await withCheckedContinuation { continuation in
                agentWaits.wait(forInput: inputID, continuation)
                guard !closed, input.send(to: pages, pageID: id, inputID: inputID) else {
                    agentWaits.expire(inputID)
                    return
                }
                expire(inputID, after: timeout)
            }
        }

        // MARK: - Actions - Activity

        /// Starts or stops keeping the page's console messages and network
        /// requests. Stopping forgets what the page kept.
        @discardableResult
        func observeActivity(_ observing: Bool) -> Bool {
            !closed && pages.request(ObservePageActivity(pageID: id, observing: observing))
        }

        /// The console messages the page kept after sequence `after`.
        func console(after: Int64) -> PageConsoleLog {
            closed ? PageConsoleLog(messages: [], dropped: 0) : pages.request(ReadPageConsole(pageID: id, after: after))
        }

        /// The network requests the page kept after sequence `after`.
        func network(after: Int64) -> PageNetworkLog {
            closed ? PageNetworkLog(requests: [], dropped: 0) : pages.request(ReadPageNetwork(pageID: id, after: after))
        }

        // MARK: - Actions - Rendering

        /// Keeps the page rendering at `size` while no window shows it, or
        /// lets it rest.
        @discardableResult
        func holdRendering(_ held: Bool, size: CGSize) -> Bool {
            !closed
                && pages.request(
                    HoldPageRendering(pageID: id, held: held, width: size.width, height: size.height))
        }

        // MARK: - Mutators

        private func expire(_ id: UUID, after timeout: Duration) {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.agentWaits.expire(id)
            }
        }
    }
#endif
