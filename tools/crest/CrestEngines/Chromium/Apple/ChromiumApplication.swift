#if CREST_CHROMIUM_HOST
    import AppKit
    import ObjectiveC

    /// Crest's application exists before Chromium loads. It implements the
    /// event scope Chromium's AppKit pump requires, without linking that pump.
    @MainActor
    final class ChromiumApplication: NSApplication, CrestEngineApplicationHosting {
        // MARK: - Variables

        private var handlingSendEvent = false
        private var engineEvents: (any CrestEngineApplicationEvents)?

        // MARK: - Actions - Events

        override func conforms(to aProtocol: Protocol) -> Bool {
            let name = NSStringFromProtocol(aProtocol)
            return name == "CrAppProtocol" || name == "CrAppControlProtocol" || super.conforms(to: aProtocol)
        }

        @objc func isHandlingSendEvent() -> Bool { handlingSendEvent }
        @objc func setHandlingSendEvent(_ handling: Bool) { handlingSendEvent = handling }

        func attach(_ events: any CrestEngineApplicationEvents) { engineEvents = events }

        @objc func addNativeEventProcessorObserver(_ observer: UnsafeMutableRawPointer) {
            engineEvents?.add(observer: observer)
        }

        @objc func removeNativeEventProcessorObserver(_ observer: UnsafeMutableRawPointer) {
            engineEvents?.remove(observer: observer)
        }

        override func sendEvent(_ event: NSEvent) {
            let previous = handlingSendEvent
            handlingSendEvent = true
            defer { handlingSendEvent = previous }
            if let engineEvents {
                engineEvents.processEvent(event) { self.forward(event) }
            } else {
                forward(event)
            }
        }

        private func forward(_ event: NSEvent) { super.sendEvent(event) }

        // MARK: - Actions - Accessibility

        override func observeValue(
            forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            let enabled = (change?[.newKey] as? NSNumber)?.boolValue ?? false
            let address = context.map(UInt.init(bitPattern:)) ?? 0
            let handled = MainActor.assumeIsolated {
                engineEvents?.observeKey(
                    keyPath, value: NSNumber(value: enabled), context: UnsafeMutableRawPointer(bitPattern: address))
                    == true
            }
            if handled { return }
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }

        override func accessibilityRole() -> NSAccessibility.Role? {
            engineEvents?.prepareAccessibility()
            return super.accessibilityRole()
        }

        override func accessibilitySetValue(_ value: Any?, forAttribute attribute: NSAccessibility.Attribute) {
            if attribute.rawValue == "AXEnhancedUserInterface" {
                let enabled = (value as? NSNumber)?.boolValue ?? false
                if Thread.isMainThread {
                    MainActor.assumeIsolated { engineEvents?.setEnhancedAccessibility(enabled) }
                } else {
                    Task { @MainActor [weak self] in self?.engineEvents?.setEnhancedAccessibility(enabled) }
                }
            }
            super.accessibilitySetValue(value, forAttribute: attribute)
        }

        override var accessibilityFocusedUIElement: Any? {
            // AppKit invokes this legacy NSObject hook on the application
            // thread. Its Objective-C result stays on that same stack.
            nonisolated(unsafe) var focused: Any?
            MainActor.assumeIsolated { focused = engineEvents?.focusedAccessibilityElement() }
            return focused ?? super.accessibilityFocusedUIElement
        }

        // MARK: - Actions - Quit

        override func terminate(_ sender: Any?) {
            if ChromiumComposition.engineHost != nil {
                _ = ChromiumComposition.deferQuit()
            } else {
                super.terminate(sender)
            }
        }
    }
#endif
