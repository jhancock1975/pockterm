import SwiftUI
import UIKit

/// One key's public half, in full, with visible Copy and Share buttons so it
/// can go into a server's authorized_keys.
struct KeyDetailView: View {
    let key: SSHKeyRecord
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Label", value: key.label)
                LabeledContent("Type", value: key.keyType)
            }
            Section {
                PublicKeyText(text: key.publicKeyOpenSSH)
            } header: {
                Text("Public Key")
            } footer: {
                Text("Add this line to the server's `~/.ssh/authorized_keys` file.")
            }
            Section {
                Button {
                    UIPasteboard.general.string = key.publicKeyOpenSSH
                    copied = true
                } label: {
                    if copied {
                        Label("Copied", systemImage: "checkmark")
                    } else {
                        Label("Copy Public Key", systemImage: "doc.on.doc")
                    }
                }
                ShareLink(item: key.publicKeyOpenSSH) {
                    Label("Share Public Key", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle(key.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// SwiftUI's Text hyphenates the base64 body where it wraps, drawing a "-"
/// that is not part of the key. A selectable UITextView wraps on characters
/// and never adds one, so what is on screen is exactly what the key is.
private struct PublicKeyText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byCharWrapping
        view.font = UIFont.monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.accessibilityIdentifier = "publicKeyText"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        view.accessibilityLabel = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fit.height)
    }
}
