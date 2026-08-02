import SwiftUI

struct AccountConnectionView: View {
    @ObservedObject var model: AppModel
    @State private var confirmsDisconnect = false

    var body: some View {
        SettingsCard(title: .marvelSnapPro, systemImage: "link.circle.fill", tint: .purple) {
            HStack {
                VStack(alignment: .leading) {
                    Label {
                        Text(model.isLinked ? .accountLinked : .accountNotLinked)
                    } icon: {
                        Image(systemName: model.isLinked ? "checkmark.seal.fill" : "person.crop.circle.badge.questionmark")
                    }
                    .font(.headline)

                    Text(model.isLinked ? .accountLinkedDetail : .accountNotLinkedDetail)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isConnecting {
                    ProgressView()
                        .controlSize(.small)
                }

                if model.isLinked {
                    Button(role: .destructive, action: requestDisconnect) {
                        Text(.disconnect)
                    }
                    .disabled(model.isConnecting || model.isSyncing)
                    .confirmationDialog(
                        String(localized: .disconnectTitle),
                        isPresented: $confirmsDisconnect,
                        titleVisibility: .visible
                    ) {
                        Button(role: .destructive, action: model.disconnect) { Text(.disconnect) }
                        Button(role: .cancel, action: {}) { Text(.cancel) }
                    } message: {
                        Text(.disconnectMessage)
                    }
                } else {
                    Button(action: connect) {
                        Label(.connectAccount, systemImage: "link")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(model.canConnect == false || model.isConnecting || model.isSyncing)
                }
            }
        }
    }

    private func connect() {
        Task { await model.connect() }
    }

    private func requestDisconnect() {
        confirmsDisconnect = true
    }
}
