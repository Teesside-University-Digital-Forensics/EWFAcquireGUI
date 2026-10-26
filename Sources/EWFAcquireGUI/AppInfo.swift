import AppKit

/// Single source of truth for version information.
/// build_app.sh reads `version` and `build` from this file for Info.plist.
enum AppInfo {
    static let version = "0.1"
    static let build = "20261027"
    static let displayVersion = "v\(version) (\(build))"

    static let name = "EWF Acquire GUI"
    static let repoURL = URL(string: "https://github.com/Teesside-University-Digital-Forensics/EWFAcquireGUI")!

    static func openRepository() {
        NSWorkspace.shared.open(repoURL)
    }

    static func showAboutPanel() {
        let font = NSFont.systemFont(ofSize: 11)
        let credits = NSMutableAttributedString(
            string: "A graphical front end for ewfacquire (libewf).\n",
            attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        credits.append(NSAttributedString(
            string: repoURL.absoluteString,
            attributes: [.font: font, .link: repoURL]))

        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: name,
            .applicationVersion: version,   // shown as "Version 0.1 (20261027)"
            .version: build,
            .credits: credits
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }
}
