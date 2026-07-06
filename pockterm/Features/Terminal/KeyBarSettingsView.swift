import SwiftUI

/// Customizes the terminal key bar: reorder or remove the keys on it, and add
/// any key from the catalogue. Changes apply to open sessions immediately.
struct KeyBarSettingsView: View {
    @State private var keys: [KeyBarKey] = KeyBarConfig.load()

    private var availableKeys: [KeyBarKey] {
        KeyBarKey.allCases.filter { !keys.contains($0) }
    }

    var body: some View {
        List {
            Section {
                ForEach(keys) { key in
                    Text(key.displayName)
                }
                .onMove { from, to in
                    keys.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { offsets in
                    keys.remove(atOffsets: offsets)
                }
            } header: {
                Text("On the Key Bar")
            } footer: {
                Text("Drag to reorder; swipe to remove. The bar scrolls horizontally in the terminal.")
            }

            if !availableKeys.isEmpty {
                Section("Available Keys") {
                    ForEach(availableKeys) { key in
                        Button {
                            keys.append(key)
                        } label: {
                            HStack {
                                Text(key.displayName).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Reset to Default") {
                    keys = KeyBarConfig.defaultKeys
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Key Bar")
        .onChange(of: keys) { KeyBarConfig.save(keys) }
    }
}
