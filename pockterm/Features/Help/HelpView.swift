import SwiftUI

/// A block of help content within a topic.
///
/// These are `LocalizedStringResource` rather than `String` so that Xcode
/// extracts them into the String Catalog. The previous renderer built a
/// `LocalizedStringKey` from a runtime `String`, which does look the value up
/// at runtime but is invisible to the build-time extractor — so the entire
/// user guide silently stayed English in every language.
enum HelpBlock {
    case paragraph(LocalizedStringResource)
    case heading(LocalizedStringResource)
    case bullets([LocalizedStringResource])
}

/// One help topic, rendered as its own detail page.
struct HelpTopic: Identifiable {
    let id = UUID()
    let title: LocalizedStringResource
    /// SF Symbol name — an asset identifier, never localized.
    let icon: String
    let summary: LocalizedStringResource
    let blocks: [HelpBlock]
}

/// Help prose is authored with inline markdown emphasis (`**bold**`, backticks).
/// Resolve the translation first, then parse the markdown of whichever language
/// came back — emphasis markers are part of the translated text.
func helpMarkdown(_ resource: LocalizedStringResource) -> AttributedString {
    let localized = String(localized: resource)
    let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: localized, options: options))
        ?? AttributedString(localized)
}

/// The in-app user guide. Presented as a sheet from the Hosts screen's Help
/// button. Topics are task-focused and organized into sections, following
/// Apple's guidance for onscreen help.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(HelpContent.sections) { section in
                    Section {
                        ForEach(section.topics) { topic in
                            NavigationLink {
                                HelpTopicView(topic: topic)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(topic.title)
                                        Text(topic.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: topic.icon)
                                }
                            }
                        }
                    } header: {
                        Text(section.title)
                    }
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Renders a single topic's blocks.
struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .paragraph(let text):
                        Text(helpMarkdown(text))
                            .fixedSize(horizontal: false, vertical: true)
                    case .heading(let text):
                        Text(text)
                            .font(.headline)
                            .padding(.top, 4)
                    case .bullets(let items):
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(helpMarkdown(item))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text(topic.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}
