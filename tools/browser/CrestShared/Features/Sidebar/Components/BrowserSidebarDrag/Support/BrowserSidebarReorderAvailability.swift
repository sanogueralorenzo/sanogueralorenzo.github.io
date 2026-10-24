/// Whether sidebar items reorder in place rather than through a platform drag
/// session. Both platforms use the same geometry and commit path; they differ
/// only in how the lift is armed — pointer drag on macOS, press-and-hold on iOS,
/// where a plain drag belongs to the scroll view.
enum BrowserSidebarReorderAvailability {
    static let isEnabled = true
}
