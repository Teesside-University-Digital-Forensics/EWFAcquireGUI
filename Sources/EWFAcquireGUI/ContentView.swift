import SwiftUI
import AppKit

struct EnumPicker<T: TitledOption>: View where T.AllCases: RandomAccessCollection {
    @Binding var selection: T
    var body: some View {
        Picker("", selection: $selection) {
            ForEach(T.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
    }
}

struct ContentView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 12) {
            toolBar
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) { sourceBox; destinationBox }
                VStack(spacing: 12) { caseBox; optionsBox }
            }
            .disabled(m.isBusy)
            progressBox
        }
        .padding(14)
        .alert("EWF Acquire GUI",
               isPresented: Binding(get: { m.alertMessage != nil },
                                    set: { if !$0 { m.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(m.alertMessage ?? "")
        }
        .confirmationDialog("Start acquisition?", isPresented: $m.showConfirm,
                            titleVisibility: .visible) {
            Button("Start Acquisition") { m.begin() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(m.confirmSummary)
        }
    }

    // MARK: Tool

    private var toolBar: some View {
        GroupBox {
            HStack(spacing: 10) {
                Image(systemName: m.toolReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(m.toolReady ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.toolReady ? m.toolVersion : "ewfacquire not found")
                    Text(m.toolPath.isEmpty ? "Install with: brew install libewf" : m.toolPath)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(AppInfo.displayVersion)
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Locate…") { m.chooseTool() }
            }
            .padding(4)
        }
    }

    // MARK: Source

    private var diskSelection: Binding<String?> {
        Binding(
            get: { m.disks.first { $0.devicePath == m.settings.sourcePath }?.id },
            set: { id in
                if let d = m.disks.first(where: { $0.id == id }) { m.selectDisk(d) }
            })
    }

    private func diskRow(_ d: DiskInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: d.isInternal ? "internaldrive" : "externaldrive")
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(d.name) · \(d.sizeString)")
                Text(d.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var sourceBox: some View {
        GroupBox("1 · Source") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Disks").font(.headline)
                    Spacer()
                    if m.isScanning { ProgressView().controlSize(.small) }
                    Button { m.refreshDisks() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                List(m.disks, selection: diskSelection) { d in diskRow(d) }
                    .frame(height: 170)
                HStack {
                    TextField("/dev/rdiskN or image file", text: $m.settings.sourcePath)
                    Button("Choose File…") { m.chooseSourceFile() }
                }
                Toggle("Unmount the disk’s volumes before imaging", isOn: $m.settings.unmountSource)
                    .disabled(m.settings.sourceWholeDisk == nil)
            }
            .padding(6)
        }
    }

    // MARK: Destination

    private var destinationBox: some View {
        GroupBox("2 · Destination") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Destination folder", text: $m.settings.targetDirectory)
                    Button("Choose…") { m.chooseDestination() }
                }
                TextField("Image name (without extension)", text: $m.settings.imageName)
                Text(m.settings.imageName.isEmpty || m.settings.targetDirectory.isEmpty
                     ? "The image will be written as <name>.\(m.settings.format.fileExtension), .E02, …"
                     : "\(m.settings.targetBase).\(m.settings.format.fileExtension)")
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            .padding(6)
        }
    }

    // MARK: Case info

    private var caseBox: some View {
        GroupBox("3 · Case information") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Case number")
                    TextField("", text: $m.settings.caseNumber)
                }
                GridRow {
                    Text("Evidence number")
                    TextField("", text: $m.settings.evidenceNumber)
                }
                GridRow {
                    Text("Examiner")
                    TextField("", text: $m.settings.examiner)
                }
                GridRow {
                    Text("Description")
                    TextField("", text: $m.settings.description)
                }
                GridRow {
                    Text("Notes")
                    TextField("", text: $m.settings.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .padding(6)
        }
    }

    // MARK: Options

    private var optionsBox: some View {
        GroupBox("4 · Image options") {
            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow { Text("Format"); EnumPicker(selection: $m.settings.format) }
                    GridRow { Text("Compression"); EnumPicker(selection: $m.settings.compression) }
                    GridRow { Text("Hashes"); EnumPicker(selection: $m.settings.digest) }
                    GridRow { Text("Media type"); EnumPicker(selection: $m.settings.mediaType) }
                    GridRow { Text("Media flags"); EnumPicker(selection: $m.settings.mediaFlag) }
                }
                DisclosureGroup("Advanced") {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow { Text("Segment size"); EnumPicker(selection: $m.settings.segment) }
                        GridRow {
                            Text("Sectors per chunk")
                            Picker("", selection: $m.settings.sectorsPerChunk) {
                                ForEach([16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768],
                                        id: \.self) { Text("\($0)").tag($0) }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("Error granularity")
                            Picker("", selection: $m.settings.errorGranularity) {
                                ForEach([1, 2, 4, 8, 16, 32, 64, 128, 256, 512], id: \.self) {
                                    Text("\($0) sectors").tag($0)
                                }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("Read retries")
                            Stepper(value: $m.settings.readRetries, in: 0...10) {
                                Text("\(m.settings.readRetries)")
                            }
                        }
                    }
                    .padding(.top, 6)
                    Toggle("Zero-fill unreadable sectors (-w)", isOn: $m.settings.zeroOnError)
                    Toggle("Resume interrupted acquisition (-R)", isOn: $m.settings.resume)
                    Toggle("Write ewfacquire log next to the image", isOn: $m.settings.writeLog)
                }

                HStack {
                    Menu("Defaults") {
                        Button("Save Current Options as Defaults") { m.saveCurrentAsDefaults() }
                        Button("Revert to Saved Defaults") { m.revertToSavedDefaults() }
                        Divider()
                        Button("Restore Factory Defaults") { m.restoreFactoryDefaults() }
                    }
                    .fixedSize()
                    Text(m.hasCustomDefaults ? "Custom defaults saved" : "Using factory defaults")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(6)
        }
    }

    // MARK: Progress

    private var statusColor: Color {
        switch m.phase {
        case .succeeded: return .green
        case .failed: return .red
        default: return .secondary
        }
    }

    private var progressBox: some View {
        GroupBox("5 · Acquire") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ProgressView(value: m.progress)
                    Text("\(Int(m.progress * 100))%")
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                    if m.isBusy {
                        Button("Cancel", role: .destructive) { m.cancel() }
                            .disabled(m.phase == .cancelling)
                    } else {
                        Button("Start Acquisition") { m.requestStart() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }

                if case .failed(let message) = m.phase {
                    Text(message).foregroundStyle(statusColor)
                } else if !m.statusText.isEmpty {
                    Text(m.statusText).font(.callout).foregroundStyle(statusColor)
                }

                if m.permissionHint, !m.isBusy {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("macOS privacy protection blocked ewfacquire. Grant Full Disk Access to the app you launched this from (EWF Acquire GUI, or Terminal/iTerm if you used swift run), then quit and reopen it. Folders such as Downloads, Desktop and Documents are protected, so for the source and destination you can also use an unprotected location like /Users/Shared.")
                            .font(.callout)
                        Button("Open Full Disk Access Settings…") { m.openFullDiskAccessSettings() }
                    }
                }

                if !m.hashes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(m.hashes.enumerated()), id: \.offset) { _, h in
                            Text("\(h.name): \(h.value)")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(m.logLines.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(6)
                    }
                    .frame(height: 130)
                    .background(Color.black.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onChange(of: m.logLines.count) { _ in proxy.scrollTo("end") }
                }

                DisclosureGroup("Command preview") {
                    HStack(alignment: .top) {
                        Text(m.commandPreview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(m.commandPreview, forType: .string)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(6)
        }
    }
}
