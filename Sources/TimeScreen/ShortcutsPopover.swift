import SwiftUI

struct ShortcutsPopover: View {
    private struct Row: Identifiable {
        let id = UUID()
        let keys: String
        let action: LocalizedStringKey
    }

    private struct Section: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let rows: [Row]
    }

    private let sections = [
        Section(title: "Move", rows: [
            Row(keys: "← →", action: "Previous or next screenshot"),
            Row(keys: "⇧← ⇧→", action: "Ten screenshots at a time"),
            Row(keys: "⌥← ⌥→", action: "Previous or next app switch"),
            Row(keys: "⌘← ⌘→", action: "First or last screenshot (also Home and End)"),
        ]),
        Section(title: "Search", rows: [
            Row(keys: "⌘F  /", action: "Search"),
            Row(keys: "↑ ↓", action: "Step through results"),
            Row(keys: "↩", action: "Back to the timeline"),
        ]),
        Section(title: "Screenshot", rows: [
            Row(keys: "S", action: "Star or unstar"),
            Row(keys: "T", action: "Show or hide the text panel"),
            Row(keys: "⌘C", action: "Copy the selected text, or all of it"),
            Row(keys: "⌘+  ⌘−  ⌘0", action: "Zoom in, zoom out, reset"),
            Row(keys: "⎋", action: "Close the timeline"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title).font(.headline)
                    ForEach(section.rows) { row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.keys).font(.body.monospaced()).frame(width: 110, alignment: .leading)
                            Text(row.action).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
    }
}
