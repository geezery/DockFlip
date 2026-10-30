import SwiftUI

/// The apps Clean Up never suggests, each with a way back. Opened from the
/// "Kept Apps" button at the bottom of Clean Up.
struct KeptAppsView: View {
    @ObservedObject var model: CleanupModel
    let controller: CleanupController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kept apps").font(.system(size: 13, weight: .semibold))
            Text("Clean Up never suggests these apps or their windows.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.kept) { app in
                        HStack(spacing: 8) {
                            AppIconView(icon: app.icon, size: 20)
                            Text(verbatim: app.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Remove") { controller.suggestAgain(app.id) }
                                .buttonStyle(.borderless)
                                .font(.system(size: 12))
                                .help(Text("Suggest this app again"))
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 300)
    }
}
