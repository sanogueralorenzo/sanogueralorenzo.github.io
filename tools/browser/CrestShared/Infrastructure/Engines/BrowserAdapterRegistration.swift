import Foundation

/// What one engine's integration offers: the engine it is, how far it vouches
/// for each capability, and the page archive it writes. The core hears only
/// the capabilities it supports, when the engine's binding registers.
struct BrowserAdapterRegistration: Sendable {

    // MARK: - Variables

    let kind: EngineKind
    let capabilities: [EngineCapability: CapabilityStatus]
    let implementationId: BrowserEngineImplementation
    /// The page archive this engine writes and reads. It follows the engine, not
    /// the platform, so callers that have no page yet can still name the format
    /// without asking a compile-time condition.
    let archiveFormat: BrowserPageArchiveFormat

    // MARK: - Initializers

    init(
        kind: EngineKind, implementation: BrowserEngineImplementation, supported: [EngineCapability],
        unverified: [EngineCapability] = [], unavailable: [EngineCapability] = [],
        archiveFormat: BrowserPageArchiveFormat
    ) {
        self.kind = kind
        implementationId = implementation
        self.archiveFormat = archiveFormat
        var values: [EngineCapability: CapabilityStatus] = [:]
        for (status, declared) in [
            (CapabilityStatus.supported, supported), (.unverified, unverified), (.unavailable, unavailable),
        ] {
            for capability in declared {
                precondition(values[capability] == nil, "Duplicate engine capability: \(capability.name)")
                values[capability] = status
            }
        }
        capabilities = values
    }

    // MARK: - Actions - Capabilities

    func supports(_ capability: EngineCapability) -> Bool {
        capabilities[capability]?.isAvailable == true
    }

    /// What the engine's binding registers with the core: the capabilities it
    /// supports, in the core's order.
    func registration(isDefault: Bool) -> EngineRegistration {
        EngineRegistration(kind: kind, capabilities: EngineCapability.all.filter(supports), isDefault: isDefault)
    }
}
