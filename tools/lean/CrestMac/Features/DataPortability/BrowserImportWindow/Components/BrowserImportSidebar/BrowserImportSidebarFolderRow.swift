import SwiftUI

struct BrowserImportSidebarFolderRow: View {
    let folder: FolderStateModel

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 10)
                .foregroundStyle(.secondary)
            Image(systemName: "folder.fill")
                .frame(width: 18)
                .foregroundStyle(.tint)
            Text(folder.title)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.leading, 17)
        .padding(.trailing, 17)
        .frame(height: 40)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserImportSidebarFolderRow(
            folder: SpaceModel.detached(
                SpaceState.Seed(name: "Research", folders: [FolderState.Seed(title: "Research")], tabs: [])
            ).folders.models[0]
        ).padding().frame(
            width: 300)
    }
#endif
