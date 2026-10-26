import SwiftUI

struct CrestSpaceChipCommands: ViewModifier {
    let commands: [CrestSpaceChipCommand]

    @ViewBuilder
    func body(content: Content) -> some View {
        if commands.isEmpty {
            content
        } else {
            content.contextMenu {
                ForEach(commands) { command in
                    Button(
                        command.title,
                        systemImage: command.systemImage,
                        role: command.isDestructive ? .destructive : nil,
                        action: command.perform
                    )
                }
                .crestMenuActionLabelStyle()
            }
        }
    }
}
