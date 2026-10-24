import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct BrowserDragSessionToken: Equatable, Sendable {
    let rawValue: UUID

    init(generation: UInt64) {
        let value = generation.bigEndian
        rawValue = withUnsafeBytes(of: value) { bytes in
            UUID(
                uuid: (
                    0x43, 0x52, 0x45, 0x53, 0x54, 0x44, 0x52, 0x41,
                    bytes[0], bytes[1], bytes[2], bytes[3],
                    bytes[4], bytes[5], bytes[6], bytes[7]
                )
            )
        }
    }
}

enum BrowserTabDragSessionLifecyclePhase: Equatable, Sendable {
    case active
    case ended
    case dataTransferCompleted

    // MARK: - Static Variables

    /// iOS 27 finally exposes the native drag session's terminal phase to
    /// SwiftUI. It is the source-side completion signal that still fires when
    /// a drag is cancelled or released outside every DropDelegate.
    static let nativeCompletionRuntimeMajorVersion = 27

    // MARK: - Variables

    /// Whether the drag session is over once it reaches this phase.
    var endsSession: Bool {
        self == .ended || self == .dataTransferCompleted
    }

    // MARK: - Actions - Runtime

    static func usesNativeCompletion(runtimeMajorVersion: Int) -> Bool {
        runtimeMajorVersion >= nativeCompletionRuntimeMajorVersion
    }
}

struct BrowserFolderDragItem: Codable, Equatable, Transferable, Sendable {
    let folderID: UUID
    let spaceID: UUID
    let profileID: UUID
    /// Snapshot of the whole subtree; detects membership changes during a lift.
    var memberTabIDs: [UUID]? = nil
    var selection: BrowserCapturedSelection? = nil

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }

    /// The selection a lift captures stays with the lift; the payload names
    /// only the folder.
    private enum CodingKeys: String, CodingKey {
        case folderID, spaceID, profileID, memberTabIDs
    }
}

/// A split group lifted from the sidebar. The whole run travels as one block, so
/// the payload carries the group's identity plus the members it stood for when
/// the lift began — the commit re-reads the live run, and the captured IDs are
/// what let a guard notice the group changed under the drag.
///
/// `Transferable` for the same reason `BrowserTabDragItem` is: iOS lifts a row
/// through drag-and-drop, and a drag session needs something to carry. The
/// payload still never leaves Crest — nothing outside the sidebar's own drop
/// delegate reads it.
struct BrowserSplitGroupDragItem: Codable, Equatable, Transferable, Sendable {
    let groupID: UUID
    let spaceID: UUID
    let profileID: UUID
    let memberTabIDs: [UUID]
    var selection: BrowserCapturedSelection? = nil

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
    }

    static var transferRepresentation: some TransferRepresentation {
        // JSON avoids advertising a document type for an internal sidebar
        // reordering gesture, exactly as the tab payload does.
        CodableRepresentation(contentType: .json)
    }

    /// The selection a lift captures stays with the lift; the payload names
    /// only the split and its members.
    private enum CodingKeys: String, CodingKey {
        case groupID, spaceID, profileID, memberTabIDs
    }
}

struct BrowserTabDragItem: Codable, Equatable, Transferable, Sendable {
    let tabID: UUID
    let spaceID: UUID
    let profileID: UUID
    var selection: BrowserCapturedSelection? = nil

    var runtimeAssignment: BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: tabID,
            spaceID: spaceID,
            profileID: profileID
        )
    }

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
    }

    static var transferRepresentation: some TransferRepresentation {
        // This payload never leaves Crest. JSON avoids advertising a document
        // type for an internal sidebar-reordering gesture.
        CodableRepresentation(contentType: .json)
    }

    /// The selection a lift captures stays with the lift; the payload names
    /// only the tab.
    private enum CodingKeys: String, CodingKey {
        case tabID, spaceID, profileID
    }
}
