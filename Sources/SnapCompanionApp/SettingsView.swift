import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsHeaderView()

                SettingsCard(title: .syncSettingsTitle, systemImage: "bolt.horizontal.circle.fill", tint: .blue) {
                    Toggle(isOn: $model.automaticSyncEnabled) {
                        Text(.syncAutomaticallyOnChanges)
                    }
                    .toggleStyle(.switch)

                    Text(.syncAutomaticallyDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

                    Label(.snapFolder, systemImage: "folder.fill")
                        .font(.headline)

                    Text(model.sourcePath)
                        .font(.callout.monospaced())
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.quaternary, in: .rect(cornerRadius: 10))

                    HStack {
                        Label {
                            Text(model.canConnect ? .activeDataSource : .folderNotConfigured)
                        } icon: {
                            Image(systemName: model.canConnect ? "checkmark.circle.fill" : "exclamationmark.circle")
                        }
                        .foregroundStyle(.secondary)

                        Spacer()

                        Button(action: model.chooseFolder) {
                            Label {
                                Text(model.canConnect ? .changeFolder : .chooseFolder)
                            } icon: {
                                Image(systemName: "folder.badge.gearshape")
                            }
                        }
                        .disabled(model.isSyncing || model.isConnecting)
                    }
                }

                AccountConnectionView(model: model)
                PrivacyNoticeView()
                LocalDataView(model: model)
            }
            .padding()
        }
        .background {
            LinearGradient(
                colors: [.blue.opacity(0.06), .purple.opacity(0.05), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .navigationTitle(Text(.sectionSettings))
    }
}
