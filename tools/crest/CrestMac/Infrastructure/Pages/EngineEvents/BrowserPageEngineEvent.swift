/// Something the engine observed about its page that the page presents or
/// acts on. Each event carries what follows from it, so the page's whole
/// dispatcher is `event.apply(to: self)`, and a new event is a new type with
/// its own `apply`. What the page shows, such as its address, title, loading
/// and security, reaches the core through the adapter's `reporter` instead.
@MainActor
protocol BrowserPageEngineEvent {
    func apply(to page: BrowserPage)
}
