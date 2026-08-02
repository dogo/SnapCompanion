import SwiftUI

struct LocalDataView: View {
    @ObservedObject var model: AppModel
    @State private var confirmsClear = false

    var body: some View {
        SettingsCard(title: .localDataTitle, systemImage: "externaldrive.fill.badge.xmark", tint: .red) {
            HStack {
                VStack(alignment: .leading) {
                    Text(.localDataResetTitle)
                        .font(.headline)
                    Text(.localDataDetail)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive, action: requestClear) {
                    Text(.clearLocalData)
                }
                .disabled(model.isConnecting || model.isSyncing)
                .confirmationDialog(
                    String(localized: .clearLocalDataTitle),
                    isPresented: $confirmsClear,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive, action: model.clearLocalData) { Text(.clearLocalData) }
                    Button(role: .cancel, action: {}) { Text(.cancel) }
                } message: {
                    Text(.clearLocalDataMessage)
                }
            }
        }
    }

    private func requestClear() {
        confirmsClear = true
    }
}
