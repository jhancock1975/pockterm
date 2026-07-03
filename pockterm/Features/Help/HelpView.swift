import SwiftUI

/// A block of help content within a topic.
enum HelpBlock {
    case paragraph(String)
    case heading(String)
    case bullets([String])
}

/// One help topic, rendered as its own detail page.
struct HelpTopic: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let summary: String
    let blocks: [HelpBlock]
}

/// The in-app user guide. Presented as a sheet from the Hosts screen's Help
/// button. Topics are task-focused and organized into sections, following
/// Apple's guidance for onscreen help.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(HelpContent.sections, id: \.title) { section in
                    Section(section.title) {
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
                        Text(.init(text))
                            .fixedSize(horizontal: false, vertical: true)
                    case .heading(let text):
                        Text(text)
                            .font(.headline)
                            .padding(.top, 4)
                    case .bullets(let items):
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(items, id: \.self) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(.init(item))
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
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
