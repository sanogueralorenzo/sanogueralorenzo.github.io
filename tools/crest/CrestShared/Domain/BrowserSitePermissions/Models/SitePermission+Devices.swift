import Foundation

extension SitePermission {
    // MARK: - Variables

    /// The capabilities that stand alone and that this one asks for: its
    /// components, or itself.
    var devices: [SitePermission] {
        components.isEmpty ? [self] : components
    }

    /// The combined capabilities whose decisions also answer this one.
    var combinations: [SitePermission] {
        Self.all.filter { combination in combination.components.contains(where: devices.contains) }
    }

    // MARK: - Actions - Presentation

    /// What the settings call `decision` for this capability. Ask reads as
    /// what the site gets before the person answers.
    func title(for decision: SitePermissionDecision) -> LocalizedStringResource {
        decision.verdict == .ask ? askTitle : decision.title
    }
}
