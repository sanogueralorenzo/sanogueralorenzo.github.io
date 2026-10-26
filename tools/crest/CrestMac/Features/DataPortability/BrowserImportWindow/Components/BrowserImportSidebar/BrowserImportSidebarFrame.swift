import SwiftUI

struct BrowserImportSidebarFrame<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: Content

    init(

        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { CrestBrandTheme.surface }
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
            }
            .environment(
                \.colorScheme,
                colorScheme
            )
    }
}
