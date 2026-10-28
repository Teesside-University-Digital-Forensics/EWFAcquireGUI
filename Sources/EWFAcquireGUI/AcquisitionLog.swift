import Foundation

/// Builds the descriptive header written at the top of each acquisition log (<image>.log).
/// The run details (start/end time, result) and ewfacquire's own output are appended
/// afterwards by the privileged wrapper script in AppModel, so the log is still completed
/// if the app is closed while an acquisition is running.
enum AcquisitionLog {
    static func header(settings s: AcquireSettings,
                       toolPath: String,
                       toolVersion: String,
                       command: String,
                       sourceDescription: String?) -> String {
        let rule = String(repeating: "=", count: 78)
        let labelWidth = 26
        let indent = String(repeating: " ", count: labelWidth)

        func row(_ label: String, _ value: String) -> String {
            (label + ":").padding(toLength: labelWidth, withPad: " ", startingAt: 0) + value
        }
        func text(_ value: String) -> String {
            let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return "(not set)" }
            return t.replacingOccurrences(of: "\n", with: "\n" + indent)
        }
        func yesNo(_ b: Bool) -> String { b ? "Yes" : "No" }
        func section(_ title: String) -> [String] {
            ["", title, String(repeating: "-", count: title.count)]
        }

        var out: [String] = []
        out.append(rule)
        out.append(" ACQUISITION LOG")
        out.append(rule)
        out.append("This acquisition was produced using \(AppInfo.name) \(AppInfo.displayVersion).")
        out.append(AppInfo.repoURL.absoluteString)

        out += section("Tools and system")
        out.append(row("Application", "\(AppInfo.name) \(AppInfo.displayVersion)"))
        out.append(row("ewfacquire version", toolVersion.isEmpty ? "(unknown)" : toolVersion))
        out.append(row("ewfacquire executable", toolPath))
        out.append(row("Operating system", "macOS " + ProcessInfo.processInfo.operatingSystemVersionString))

        out += section("Source and destination")
        out.append(row("Source", s.sourcePath))
        if let d = sourceDescription { out.append(row("Source device", d)) }
        if s.sourceWholeDisk != nil {
            out.append(row("Unmount volumes first", yesNo(s.unmountSource)))
        }
        out.append(row("Image (base name)", s.targetBase))
        out.append(row("Image file", "\(s.targetBase).\(s.format.fileExtension) (plus further segments)"))

        out += section("Case information")
        out.append(row("Case number", text(s.caseNumber)))
        out.append(row("Evidence number", text(s.evidenceNumber)))
        out.append(row("Examiner", text(s.examiner)))
        out.append(row("Description", text(s.description)))
        out.append(row("Notes", text(s.notes)))

        out += section("Image options")
        out.append(row("Format", "\(s.format.title)  [-f \(s.format.rawValue)]"))
        out.append(row("Compression", s.compression.title))
        out.append(row("Hashes", s.digest.title))
        out.append(row("Media type", s.mediaType.title))
        out.append(row("Media flags", s.mediaFlag.title))
        out.append(row("Segment size", s.segment.title))
        out.append(row("Sectors per chunk", String(s.sectorsPerChunk)))
        out.append(row("Error granularity",
                       "\(min(s.errorGranularity, s.sectorsPerChunk)) sectors"))
        out.append(row("Read retries",
                       s.readRetries == 2 ? "2 (ewfacquire default)" : String(s.readRetries)))
        out.append(row("Zero-fill unreadable", yesNo(s.zeroOnError)))

        out += section("ewfacquire command (as shown in the Command preview)")
        out.append(command)
        out.append("")
        out.append("Note: ewfacquire's own log (-l) is written to a temporary file while it runs")
        out.append("and is merged into this file below.")

        return out.joined(separator: "\n") + "\n"
    }
}
