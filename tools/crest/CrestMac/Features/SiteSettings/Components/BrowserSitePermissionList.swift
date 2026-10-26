import SwiftUI

struct BrowserSitePermissionList: View {
    let origin: SiteOrigin
    let spaceID: UUID
    let permissionCenter: BrowserSitePermissionCenter

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Text("Permissions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(SitePermission.all, id: \.self) { permission in
                BrowserSitePermissionRow(
                    permission: permission,
                    origin: origin,
                    spaceID: spaceID,
                    permissionCenter: permissionCenter
                )
            }
        }
    }
}
