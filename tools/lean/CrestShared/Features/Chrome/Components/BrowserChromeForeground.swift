import SwiftUI

extension EnvironmentValues {
    @Entry var spaceChromeAccent: Color? = nil
    @Entry var spaceChromeForeground: Color? = nil
}

struct BrowserChromeForeground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(CrestBrandTheme.textDisplay)
            .environment(\.spaceChromeAccent, CrestBrandTheme.accent)
            .environment(\.spaceChromeForeground, CrestBrandTheme.textDisplay)
    }
}
