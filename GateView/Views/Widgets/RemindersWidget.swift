import SwiftUI

/// Compact: next 4 open reminders with tappable checkmarks. Expanded: full list + a field to add one.
struct RemindersWidget: View {
    let expanded: Bool
    @ObservedObject var service: RemindersService
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Reminders", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .opacity(0.7)
            if service.authorized {
                if expanded {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                        TextField(L10n.tr(lang, "Tambah reminder…", "Add a reminder…"), text: $draft)
                            .focused($focused)
                            .onSubmit(add)
                    }
                    .padding(8)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onAppear { focused = true }
                }
                let shown = expanded ? service.items : Array(service.items.prefix(4))
                if shown.isEmpty {
                    Text(L10n.tr(lang, "Semua beres ✓", "All done ✓")).font(.callout).opacity(0.45)
                }
                ForEach(shown) { item in
                    HStack(spacing: 10) {
                        Button {
                            service.toggle(item)
                        } label: {
                            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.completed ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.45)))
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).lineLimit(1).strikethrough(item.completed).opacity(item.completed ? 0.5 : 1)
                            if let due = item.due {
                                Text(due.formatted(.dateTime.weekday(.abbreviated).day().hour().minute()))
                                    .font(.caption2.monospacedDigit()).opacity(0.5)
                            }
                        }
                    }
                    .font(.callout)
                }
            } else {
                Text(L10n.tr(lang, "Izinkan akses Reminders di System Settings → Privacy & Security.",
                             "Allow Reminders access in System Settings → Privacy & Security."))
                    .font(.caption).opacity(0.5)
            }
        }
    }

    private var lang: String { ThemeStore.shared.theme.displayLanguage }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        service.add(title: title)
        draft = ""
        focused = true
    }
}
