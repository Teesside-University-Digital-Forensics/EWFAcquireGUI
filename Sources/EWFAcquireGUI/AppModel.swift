import SwiftUI
import AppKit

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle, running, cancelling, succeeded, cancelled, failed(String)
    }

    // Configuration
    @Published var settings = AcquireSettings()
    @Published var disks: [DiskInfo] = []
    @Published var isScanning = false

    // Tool
    @Published var toolPath = ""
    @Published var toolVersion = ""
    @Published var toolReady = false
    @Published var newCompressionSyntax = false

    // Run state
    @Published var phase: Phase = .idle
    @Published var progress = 0.0
    @Published var statusText = ""
    @Published var logLines: [String] = []
    @Published var hashes: [(name: String, value: String)] = []

    // Dialogs
    @Published var alertMessage: String?
    @Published var hasCustomDefaults = false
    @Published var permissionHint = false
    @Published var showConfirm = false
    @Published var confirmSummary = ""

    private var runDir: URL?
    private var logPath = ""
    private var cancelPath = ""
    private var logOffset: UInt64 = 0
    private var pending = ""
    private var pollTask: Task<Void, Never>?
    private var finalLogPath: String?
    private var toolVerdict: String?   // ewfacquire's own final line: SUCCESS / FAILURE / ABORTED

    /// Files used to assemble the enhanced <image>.log.
    private struct ReportPaths {
        let header: String   // header written by the app before the run
        let ewfLog: String   // ewfacquire's own -l log (temporary)
        let final: String    // <image>.log
    }

    var isBusy: Bool { phase == .running || phase == .cancelling }

    // MARK: Saved defaults (section 4)

    private static let defaultsKey = "imageOptionDefaults"

    private static func loadSavedDefaults() -> ImageDefaults? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        if let decoded = try? JSONDecoder().decode(ImageDefaults.self, from: data) { return decoded }
        // Saved with an older version (e.g. a format that has since been removed): discard it.
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        return nil
    }

    func saveCurrentAsDefaults() {
        guard let data = try? JSONEncoder().encode(settings.imageDefaults) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        hasCustomDefaults = true
    }

    func revertToSavedDefaults() {
        settings.apply(Self.loadSavedDefaults() ?? ImageDefaults())
    }

    func restoreFactoryDefaults() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        hasCustomDefaults = false
        settings.apply(ImageDefaults())
    }

    var commandPreview: String {
        let tool = toolPath.isEmpty ? "ewfacquire" : toolPath
        return ([tool] + settings.arguments(newCompressionSyntax: newCompressionSyntax))
            .map(Shell.quote).joined(separator: " ")
    }

    // MARK: Init / tool

    init() {
        let saved = UserDefaults.standard.string(forKey: "toolPath") ?? ""
        let candidates = [saved,
                          "/opt/homebrew/bin/ewfacquire",
                          "/usr/local/bin/ewfacquire",
                          "/opt/local/bin/ewfacquire"]
        toolPath = candidates.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) } ?? saved
        if let saved = Self.loadSavedDefaults() {
            settings.apply(saved)
            hasCustomDefaults = true
        }
        refreshToolInfo()
        refreshDisks()
    }

    func refreshToolInfo() {
        let path = toolPath
        Task {
            let info = await Task.detached { () -> (String, Bool)? in
                guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
                let version = Shell.run(path, ["-V"])
                    .split(separator: "\n").first.map(String.init) ?? "ewfacquire"
                let help = Shell.run(path, ["-h"])
                return (version, help.contains("compression_method") || help.contains("deflate"))
            }.value
            if let (version, newSyntax) = info {
                toolVersion = version
                newCompressionSyntax = newSyntax
                toolReady = true
            } else {
                toolVersion = ""
                toolReady = false
            }
        }
    }

    func chooseTool() {
        let panel = NSOpenPanel()
        panel.message = "Select the ewfacquire executable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            toolPath = url.path
            UserDefaults.standard.set(toolPath, forKey: "toolPath")
            refreshToolInfo()
        }
    }

    // MARK: Disks / paths

    func refreshDisks() {
        isScanning = true
        Task {
            let found = await Task.detached { DiskScanner.scan() }.value
            disks = found
            isScanning = false
        }
    }

    func selectDisk(_ d: DiskInfo) {
        settings.sourcePath = d.devicePath
        settings.mediaType = d.isRemovable ? .removable : .fixed
        if settings.imageName.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmm"
            settings.imageName = "\(d.id)-\(f.string(from: Date()))"
        }
    }

    func chooseSourceFile() {
        let panel = NSOpenPanel()
        panel.message = "Select a file or device image to acquire"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.sourcePath = url.path
        }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.message = "Choose where to save the evidence file"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.targetDirectory = url.path
        }
    }

    // MARK: Start

    func requestStart() {
        let fm = FileManager.default
        var s = settings

        guard toolReady else {
            alertMessage = "ewfacquire was not found. Install it with “brew install libewf” or use Locate…"
            return
        }
        guard !s.sourcePath.isEmpty else {
            alertMessage = "Choose a source disk or file."
            return
        }
        if !s.sourcePath.hasPrefix("/dev/"), !fm.fileExists(atPath: s.sourcePath) {
            alertMessage = "The source file does not exist."
            return
        }
        let ext = (s.sourcePath as NSString).pathExtension.lowercased()
        if !s.sourcePath.hasPrefix("/dev/"), regexGroups(#"^(?:e|ex|s|l|lx)\d{2}$"#, in: ext) != nil {
            alertMessage = "“\((s.sourcePath as NSString).lastPathComponent)” is already an EWF evidence file. ewfacquire reads raw sources (disks or raw images such as .dd/.raw) and would treat an E01 as plain bytes. To convert or re-export an existing E01, use ewfexport instead."
            return
        }
        var isDir: ObjCBool = false
        guard !s.targetDirectory.isEmpty,
              fm.fileExists(atPath: s.targetDirectory, isDirectory: &isDir),
              isDir.boolValue,
              fm.isWritableFile(atPath: s.targetDirectory) else {
            alertMessage = "Choose a writable destination folder."
            return
        }
        let name = s.imageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else {
            alertMessage = "Enter an image name (no slashes)."
            return
        }
        s.imageName = name
        settings.imageName = name

        for ext in ["E01", "e01", "s01", "Ex01"] where fm.fileExists(atPath: s.targetBase + "." + ext) {
            alertMessage = "An image named “\(name)” already exists in that folder. Choose another name."
            return
        }

        let dir = s.targetDirectory
        let sourceDisk = s.sourceWholeDisk
        Task {
            let ids = await Task.detached { DiskScanner.wholeDiskIDs(containing: dir) }.value
            if let sourceDisk, ids.contains(sourceDisk) {
                alertMessage = "The destination folder is on the disk you are acquiring (\(sourceDisk)). Choose a different destination disk."
                return
            }
            prepareConfirmation()
        }
    }

    private func prepareConfirmation() {
        let s = settings
        var lines: [String] = []
        if let d = disks.first(where: { $0.devicePath == s.sourcePath }) {
            lines.append("Source: \(d.name) (\(d.sizeString)) at \(s.sourcePath)")
            if d.isInternal { lines.append("⚠︎ This is an internal disk.") }
        } else {
            lines.append("Source: \(s.sourcePath)")
        }
        lines.append("Image: \(s.targetBase).\(s.format.fileExtension)")
        lines.append("")
        lines.append("macOS will ask for an administrator password because raw disk access needs root.")
        if s.unmountSource, let id = s.sourceWholeDisk {
            lines.append("The volumes of \(id) will be unmounted first.")
        }
        confirmSummary = lines.joined(separator: "\n")
        showConfirm = true
    }

    func begin() {
        let s = settings
        let fm = FileManager.default

        let dir = fm.temporaryDirectory.appendingPathComponent("ewfacquire-gui-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: false,
                                   attributes: [.posixPermissions: 0o700])
        } catch {
            alertMessage = "Could not create a temporary folder: \(error.localizedDescription)"
            return
        }
        runDir = dir
        logPath = dir.appendingPathComponent("run.log").path
        cancelPath = dir.appendingPathComponent("cancel").path
        fm.createFile(atPath: logPath, contents: nil, attributes: [.posixPermissions: 0o644])

        logOffset = 0
        pending = ""
        progress = 0
        statusText = "Waiting for administrator authorization…"
        logLines = []
        hashes = []
        permissionHint = false
        toolVerdict = nil
        phase = .running

        // Enhanced acquisition log: ewfacquire's own -l log goes to a temporary file, and the
        // wrapper script merges header + run details + ewfacquire output into <image>.log.
        var report: ReportPaths?
        var ewfLogOverride: String?
        finalLogPath = nil
        if s.writeLog {
            let headerPath = dir.appendingPathComponent("header.txt").path
            let ewfLog = dir.appendingPathComponent("ewfacquire.log").path
            let disk = disks.first { $0.devicePath == s.sourcePath }
            let header = AcquisitionLog.header(
                settings: s, toolPath: toolPath, toolVersion: toolVersion,
                command: commandPreview,
                sourceDescription: disk.map { "\($0.name), \($0.sizeString)" })
            try? header.write(toFile: headerPath, atomically: true, encoding: .utf8)
            let final = s.targetBase + ".log"
            report = ReportPaths(header: headerPath, ewfLog: ewfLog, final: final)
            ewfLogOverride = ewfLog
            finalLogPath = final
        }

        let command = ([toolPath] + s.arguments(newCompressionSyntax: newCompressionSyntax,
                                                logPath: ewfLogOverride))
            .map(Shell.quote).joined(separator: " ")
        let outer = Self.privilegedScript(command: command, log: logPath, cancel: cancelPath,
                                          unmountDisk: s.unmountSource ? s.sourceWholeDisk : nil,
                                          report: report)

        Task.detached { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "on run argv",
                           "-e", "do shell script (item 1 of argv) with administrator privileges",
                           "-e", "end run",
                           outer]
            let err = Pipe()
            p.standardError = err
            p.standardOutput = Pipe()
            do { try p.run() } catch {
                await self?.launchFailed("Could not start osascript: \(error.localizedDescription)")
                return
            }
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                let msg = String(decoding: errData, as: UTF8.self)
                await self?.launchFailed(msg)
            }
        }

        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                self?.poll()
            }
        }
    }

    /// Runs as root in the background. Output goes to a user-owned log file;
    /// creating the cancel flag file (also user-owned) makes it stop ewfacquire.
    /// When `report` is set, the final <image>.log is assembled here (not in the app) so it
    /// is completed even if the app is closed during the acquisition.
    private static func privilegedScript(command: String, log: String, cancel: String,
                                         unmountDisk: String?, report: ReportPaths?) -> String {
        let q = Shell.quote
        var l = ["LOG=\(q(log))", "CANCEL=\(q(cancel))"]
        if let r = report {
            l += ["HEADER=\(q(r.header))", "EWFLOG=\(q(r.ewfLog))", "FINAL=\(q(r.final))"]
        }
        l.append("START_LOCAL=$(date '+%Y-%m-%d %H:%M:%S %Z')")
        l.append("START_UTC=$(date -u '+%Y-%m-%d %H:%M:%S UTC')")

        if let disk = unmountDisk {
            l.append("if /usr/sbin/diskutil unmountDisk /dev/\(disk) >>\"$LOG\" 2>&1; then")
        } else {
            l.append("if true; then")
        }
        l.append("\(command) >>\"$LOG\" 2>&1 </dev/null &")
        l.append("P=$!")
        // Cancel: ask ewfacquire to stop (SIGTERM); if it is stuck (e.g. a hung USB read), force it after 15 s.
        l += [
            "while kill -0 $P 2>/dev/null; do",
            "if [ -e \"$CANCEL\" ]; then",
            "kill -TERM $P; N=0",
            "while kill -0 $P 2>/dev/null && [ $N -lt 15 ]; do sleep 1; N=$((N+1)); done",
            "if kill -0 $P 2>/dev/null; then kill -KILL $P; fi",
            "break",
            "fi",
            "sleep 1",
            "done",
        ]
        l.append("wait $P; RC=$?")
        l.append("else RC=99; fi")

        if report != nil {
            l += [
                "END_LOCAL=$(date '+%Y-%m-%d %H:%M:%S %Z')",
                "END_UTC=$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
                "if [ $RC -eq 0 ]; then RESULT='Completed successfully'",
                "elif [ -e \"$CANCEL\" ]; then RESULT='Cancelled by the user (partial image left in place)'",
                "elif [ $RC -eq 99 ]; then RESULT='Failed: the source volumes could not be unmounted'",
                "else RESULT='Failed'; fi",
                "{",
                "cat \"$HEADER\"",
                "echo",
                "echo 'Run details'",
                "echo '-----------'",
                "echo \"Acquisition started:   $START_LOCAL ($START_UTC)\"",
                "echo \"Acquisition finished:  $END_LOCAL ($END_UTC)\"",
                "echo \"Result:                $RESULT (ewfacquire exit code $RC)\"",
                "echo",
                "echo 'ewfacquire log (written by ewfacquire via -l)'",
                "echo '---------------------------------------------'",
                "cat \"$EWFLOG\" 2>/dev/null || echo '(ewfacquire did not produce a log)'",
                "echo",
                "echo 'ewfacquire console output (progress lines removed)'",
                "echo '--------------------------------------------------'",
                "tr '\\r' '\\n' <\"$LOG\" | grep -Ev '^[[:space:]]*(Status: at|acquired|completion in)|^[[:space:]]*$'",
                "echo",
                "echo",
                "} >>\"$FINAL\" 2>/dev/null",
                "/usr/sbin/chown \(getuid()) \"$FINAL\" 2>/dev/null",
            ]
        }
        // Written last: the app treats this line as "finished" and then deletes its temp files.
        l.append("echo \"EXIT_CODE=$RC\" >>\"$LOG\"")

        let inner = l.joined(separator: "\n")
        return "/bin/sh -c \(q(inner)) >/dev/null 2>&1 &"
    }

    private func launchFailed(_ message: String) {
        guard isBusy else { return }
        pollTask?.cancel()
        let detail = message.contains("-128") ? "Administrator authorization was cancelled."
                                              : message.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .failed(detail)
        statusText = detail
        cleanup()
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Cancel

    func cancel() {
        guard phase == .running else { return }
        FileManager.default.createFile(atPath: cancelPath, contents: Data())
        phase = .cancelling
        statusText = "Cancelling…"
    }

    // MARK: Log polling

    private func poll() {
        guard let fileHandle = FileHandle(forReadingAtPath: logPath) else { return }
        defer { try? fileHandle.close() }
        try? fileHandle.seek(toOffset: logOffset)
        let data = fileHandle.readDataToEndOfFile()
        guard !data.isEmpty else { return }
        logOffset += UInt64(data.count)
        pending += String(decoding: data, as: UTF8.self)

        // ewfacquire redraws progress with carriage returns, so split on both.
        var parts = pending.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
        pending = parts.removeLast()
        for part in parts { handle(line: part) }
    }

    private func handle(line raw: String) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }

        if line.hasPrefix("EXIT_CODE="), let code = Int(line.dropFirst("EXIT_CODE=".count)) {
            finish(code: code)
            return
        }
        if let g = regexGroups(#"Status: at (\d+)%"#, in: line), let pct = Double(g[0]) {
            progress = pct / 100
            return
        }
        if line.hasPrefix("acquired") || line.hasPrefix("completion") {
            statusText = line
            return
        }
        if let g = regexGroups(#"(MD5|SHA1|SHA256) hash calculated over data:\s*([0-9a-fA-F]+)"#, in: line) {
            hashes.append((name: g[0], value: g[1]))
        }
        if line.contains("Operation not permitted") { permissionHint = true }
        if let g = regexGroups(#"^ewfacquire: (SUCCESS|FAILURE|ABORTED)"#, in: line) { toolVerdict = g[0] }
        logLines.append(line)
        if logLines.count > 2000 { logLines.removeFirst(500) }
    }

    private func finish(code: Int) {
        pollTask?.cancel()

        // Never judge by the exit code alone. ewfacquire handles the stop signal itself and
        // exits with status 1 (not 143), so a cancel must also be recognised from the fact that
        // the user asked for it and from ewfacquire's own verdict line.
        let userCancelled = (phase == .cancelling)
        let verdict = toolVerdict   // "SUCCESS", "FAILURE", "ABORTED" or nil

        if code == 0, verdict == nil || verdict == "SUCCESS" {
            progress = 1
            phase = .succeeded
            statusText = "Acquisition completed successfully." + (finalLogPath.map { " Log: \($0)" } ?? "")
        } else if userCancelled || verdict == "ABORTED" || code == 143 || code == 15 {
            phase = .cancelled
            statusText = "Acquisition cancelled. The partial image was left in place."
        } else if code == 99 {
            phase = .failed("The source disk could not be unmounted (is it in use?). Nothing was acquired.")
            statusText = "Unmount failed."
        } else {
            phase = .failed(permissionHint
                ? "macOS blocked access to a file or device (“Operation not permitted”)."
                : "ewfacquire failed (exit code \(code)). See the log for details.")
            statusText = "Failed."
        }
        NSApp.requestUserAttention(.informationalRequest)
        cleanup()
    }

    private func cleanup() {
        if let dir = runDir { try? FileManager.default.removeItem(at: dir) }
        runDir = nil
    }
}
