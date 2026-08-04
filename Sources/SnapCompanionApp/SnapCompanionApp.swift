import SwiftUI

@main
struct SnapCompanionApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window(String(localized: .appTitle), id: "dashboard") {
            DashboardView(model: model)
                .task { model.load() }
        }
        // MenuBarExtra shortcuts only fire while its menu is open; the same
        // buttons as window commands make the shortcuts work from the app too.
        .commands {
            CommandGroup(after: .toolbar) {
                SyncCommands(model: model)
            }
        }

        MenuBarExtra(String(localized: .appTitle), systemImage: "arrow.triangle.2.circlepath") {
            MenuBarContentView(model: model)
        }
    }
}
