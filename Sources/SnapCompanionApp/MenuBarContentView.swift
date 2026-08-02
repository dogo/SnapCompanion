import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(model.statusText, systemImage: statusImage)

        Divider()

        Button(action: synchronize) {
            Label {
                Text(model.isSyncing ? .statusSyncing : .syncNow)
            } icon: {
                if model.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
        }
        .keyboardShortcut("r")
        .disabled(model.canSync == false || model.isSyncing || model.isConnecting)

        Toggle(isOn: $model.automaticSyncEnabled) {
            Text(.automaticSync)
        }
        .keyboardShortcut("a", modifiers: [.command, .shift])

        Button {
            model.toggleOverlay()
        } label: {
            Text(model.isOverlayVisible ? .overlayHide : .overlayShow)
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
        .disabled(model.canConnect == false)

        Button(action: openDashboard) {
            Text(.openWindow)
        }
        .keyboardShortcut("o")

        Divider()

        // Activates the transparent-proxy system extension for live tracking.
        Button {
            model.proxy.activate()
        } label: {
            Text(.liveTracking(model.proxy.status))
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])

        // Trusts the per-install MITM CA (one admin prompt). Auto-runs on enable
        // too; here as an explicit re-trigger.
        Button {
            DispatchQueue.global(qos: .userInitiated).async { CATrust.ensureTrusted() }
        } label: {
            Text(.trustCertificate)
        }

        Divider()

        Button(action: quit) {
            Text(.quit)
        }
        .keyboardShortcut("q")
    }

    private var statusImage: String {
        if model.isSyncing || model.isConnecting {
            "arrow.triangle.2.circlepath"
        } else if model.hasError {
            "exclamationmark.triangle"
        } else {
            "checkmark.circle"
        }
    }

    private func synchronize() {
        Task { await model.synchronize() }
    }

    private func openDashboard() {
        openWindow(id: "dashboard")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
