import SwiftUI

/// In-session theme picker: the curated presets with live previews plus a
/// "Default (inherit)" option. Tapping a row applies the theme to the live
/// terminal and persists it to the host via `TerminalSession.setTheme(id:)`.
/// Stays open after a tap so themes can be compared; the checkmark tracks the
/// host's stored selection.
struct ThemePickerSheet: View {
    let session: TerminalSession

    var body: some View {
        // The session's resolved font, so each swatch matches the real terminal.
        let fontID = EffectiveHostSettings.resolve(host: session.host).fontID
        let selected = session.host.themeID   // nil = inherit

        NavigationStack {
            List {
                Button {
                    session.setTheme(id: nil)
                } label: {
                    row(title: "Default (inherit)", checked: selected == nil, preview: nil)
                }
                .buttonStyle(.plain)

                ForEach(TerminalTheme.all) { theme in
                    Button {
                        session.setTheme(id: theme.id)
                    } label: {
                        row(title: theme.name,
                            checked: selected == theme.id,
                            preview: ThemePreviewRow(themeID: theme.id, fontID: fontID))
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func row(title: String, checked: Bool, preview: ThemePreviewRow?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if checked {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            preview
        }
        .contentShape(Rectangle())
    }
}
