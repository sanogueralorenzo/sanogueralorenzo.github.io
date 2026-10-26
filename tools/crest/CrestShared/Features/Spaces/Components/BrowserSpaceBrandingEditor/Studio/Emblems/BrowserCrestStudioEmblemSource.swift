import Foundation

/// One source of a crest's emblem in the studio: the charge its fields make,
/// and what it takes back from a charge. `CrestChargeKind.studioSource` names
/// each kind's source, so a kind the core adds fails to compile until the
/// studio offers a source for it. The controls that edit a source are views
/// ``BrowserCrestStudioEmblem`` chooses by the kind.
@MainActor
protocol BrowserCrestStudioEmblemSource {
    /// The charge the emblem's fields make for this source.
    func charge(in emblem: BrowserCrestStudioEmblem) -> CrestCharge

    /// Takes the fields this source edits from `charge`.
    func load(_ charge: CrestCharge, into emblem: BrowserCrestStudioEmblem)
}
