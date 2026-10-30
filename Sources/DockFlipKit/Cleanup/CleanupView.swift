import SwiftUI

/// The Clean Up window: idle windows and apps in two sections, Close Selected and Kept Apps below.
struct CleanupView: View {
    @ObservedObject var model: CleanupModel
    let controller: CleanupController

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Clean Up").font(.system(size: 22, weight: .bold))
                Text("Windows you have not used for three days and apps left running without windows. Nothing is closed without you, and apps still ask to save your work.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            if model.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 32)).foregroundStyle(Color.accentColor)
                    Text("Nothing to clean up").font(.system(size: 15, weight: .semibold))
                    Text("Everything open has been used recently.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !model.windows.isEmpty {
                        Section("Unused windows") {
                            ForEach(model.windows) { row in
                                CleanupRowView(row: row, model: model, controller: controller)
                            }
                        }
                    }
                    if !model.apps.isEmpty {
                        Section("Apps without windows") {
                            ForEach(model.apps) { row in
                                CleanupRowView(row: row, model: model, controller: controller)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Text(String(format: L("%ld selected"), model.selected.count))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if !model.kept.isEmpty {
                    Button(String(format: L("Kept Apps (%ld)"), model.kept.count)) { model.showsKept = true }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                        .help(Text("Apps Clean Up never suggests"))
                        .popover(isPresented: $model.showsKept) {
                            KeptAppsView(model: model, controller: controller)
                        }
                        .padding(.leading, 8)
                }
                Spacer()
                Button("Close Selected") { controller.closeSelected() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.selected.isEmpty)
            }
            .padding(16)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}
