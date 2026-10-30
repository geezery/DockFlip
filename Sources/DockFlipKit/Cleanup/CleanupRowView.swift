import SwiftUI

/// One suggestion in Clean Up: its checkbox, icon, when it was last used and its Keep button.
struct CleanupRowView: View {
    let row: CleanupRow
    @ObservedObject var model: CleanupModel
    let controller: CleanupController

    private var detail: String {
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        var parts = [String(format: L("used %@"), relative.localizedString(for: row.lastUsed, relativeTo: Date()))]
        if let bytes = row.memoryBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory))
        }
        if case .window = row.id { parts.insert(row.appName, at: 0) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { MainActor.assumeIsolated { model.selected.contains(row.id) } },
                set: { _ in MainActor.assumeIsolated { controller.toggle(row.id) } }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            AppIconView(icon: row.icon, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title).font(.system(size: 13)).lineLimit(1)
                Text(verbatim: detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            keepButton
                .buttonStyle(.borderless)
                .font(.system(size: 12))
                .help(Text(keepHelp))
        }
        .padding(.vertical, 2)
    }

    private var keepHelp: String {
        if case .window = row.id {
            return L("Keep this window for now. It is suggested again after three more unused days.")
        }
        return L("Keep this app running for now. It is suggested again after another unused day.")
    }

    /// "Keep" is for this row only; banning the whole app sits one click further, in its menu.
    @ViewBuilder private var keepButton: some View {
        if row.bundleID != nil {
            Menu {
                Button("Never suggest this app again") { controller.neverSuggest(row) }
            } label: {
                Text("Keep")
            } primaryAction: {
                controller.keepForNow(row)
            }
            .menuStyle(.button)
            .fixedSize()
        } else {
            Button("Keep") { controller.keepForNow(row) }
        }
    }
}
