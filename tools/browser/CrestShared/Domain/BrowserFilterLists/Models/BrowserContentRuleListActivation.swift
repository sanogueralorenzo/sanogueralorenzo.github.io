/// When a rule-list change becomes visible in a page.
///
/// WebKit applies a user-content-controller rule-list change to that web
/// view's next navigation; the document already on screen keeps the rules it
/// loaded with. There is no way to re-evaluate a live document, and no public
/// API reports whether a document holds uncommitted user input, so reloading is
/// the only way to make a change visible at once — and a reload throws away
/// whatever the person was typing.
enum BrowserContentRuleListActivation {
    /// Swap the rule lists and leave the document alone. WebKit picks the new
    /// lists up on the page's next navigation.
    case onNextNavigation

    /// Swap the rule lists and reload, so the change shows immediately. Reserved
    /// for the page whose protection level the user just changed.
    case immediately
}
