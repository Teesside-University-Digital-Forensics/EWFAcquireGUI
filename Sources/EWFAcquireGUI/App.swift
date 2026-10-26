import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lets the executable show a window and take focus even when run
        // directly from `swift run` instead of from an .app bundle.
        NSApp.setActivationPolicy(.regular)

        if let data = Data(base64Encoded: AppIconData.base64),
           let icon = NSImage(data: data) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct EWFAcquireGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("\(AppInfo.name) \(AppInfo.displayVersion)") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 800)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppInfo.name)") { AppInfo.showAboutPanel() }
            }
            CommandGroup(replacing: .help) {
                Button("\(AppInfo.name) on GitHub") { AppInfo.openRepository() }
            }
        }
    }
}
