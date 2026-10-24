import CoreGraphics
import Foundation

struct BrowserFolderDropLocation: Equatable, Sendable {
    let parentID: UUID?
    let beforeSiblingID: UUID?
}

struct BrowserTabDropLocation: Equatable, Sendable {
    let placement: TabPlacement
    let folderID: UUID?
    let beforeTabID: UUID?
    var destinationAssignment: BrowserSpaceRuntimeAssignment? = nil
}
