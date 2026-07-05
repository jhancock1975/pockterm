import SwiftUI

/// A Termius-style command dropdown that floats over the terminal. Shows up to
/// three recent commands (most recent first); tapping a row inserts the next
/// part of that command.
struct SuggestionDropdown: View {
    let commands: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(commands.enumerated()), id: \.offset) { index, command in
                Button { onTap(command) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(command)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < commands.count - 1 {
                    Divider().overlay(Color.white.opacity(0.12))
                }
            }
        }
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
        .frame(maxWidth: 420)
        .padding(.horizontal, 12)
    }
}
