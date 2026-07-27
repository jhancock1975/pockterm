import SwiftUI

/// A one-line preview of a theme + font: a sample shell prompt drawn with the
/// theme's background/foreground and the chosen monospaced font.
struct ThemePreviewRow: View {
    let themeID: String
    let fontID: String

    var body: some View {
        let theme = TerminalTheme.theme(id: themeID)
        let fontName = TerminalFont.font(id: fontID).id
        Text("user@host:~$ ls")
            .font(Font(UIFont(name: fontName, size: 14)
                       ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)))
            .foregroundStyle(Color(TerminalTheme.uiColor(theme.foreground)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(TerminalTheme.uiColor(theme.background)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
