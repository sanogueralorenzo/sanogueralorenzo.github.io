extension InspectorPanel {
    /// The function on Web Inspector's frontend that shows the panel.
    var webInspectorFunctionName: String {
        switch self {
        case .network:
            "showNetworkTab"
        case .elements:
            "showElementsTab"
        case .console:
            "showConsoleTab"
        }
    }
}
