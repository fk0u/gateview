import SwiftUI

struct NotesWidget: View {
    let expanded: Bool
    @ObservedObject var store: NotesStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Notes", systemImage: "note.text")
                .font(.caption.weight(.semibold))
                .opacity(0.7)
            if expanded {
                TextEditor(text: $store.text)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(height: 220)
                    .padding(8)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onAppear { focused = true }
                Text("Tersimpan otomatis · ~/.config/gateview/notes.md").font(.caption2).opacity(0.45)
            } else {
                let preview = store.text.split(separator: "\n", omittingEmptySubsequences: false).prefix(4).joined(separator: "\n")
                Text(preview.isEmpty ? "Klik untuk menulis…" : preview)
                    .font(.callout)
                    .opacity(preview.isEmpty ? 0.45 : 0.9)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
