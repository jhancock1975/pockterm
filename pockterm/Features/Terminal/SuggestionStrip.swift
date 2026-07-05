import SwiftUI

/// A horizontal row of command-completion chips shown above the keyboard while
/// the user is typing. Hidden when there are no suggestions.
struct SuggestionStrip: View {
    let suggestions: [Suggestion]
    let onTap: (Suggestion) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.text) { suggestion in
                        Button { onTap(suggestion) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: icon(for: suggestion.kind))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(suggestion.text)
                                    .font(.system(.footnote, design: .monospaced))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.25), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .background(.black)
        }
    }

    private func icon(for kind: Suggestion.Kind) -> String {
        switch kind {
        case .history: return "clock"
        case .snippet: return "text.badge.plus"
        case .common: return "terminal"
        }
    }
}
