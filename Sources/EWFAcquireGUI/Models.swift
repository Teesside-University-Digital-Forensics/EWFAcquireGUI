import Foundation

// MARK: - Helpers

enum Shell {
    /// Runs a command, returns stdout+stderr as raw data.
    static func runData(_ path: String, _ args: [String]) -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return Data() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }

    static func run(_ path: String, _ args: [String]) -> String {
        String(decoding: runData(path, args), as: UTF8.self)
    }

    /// POSIX single-quote escaping.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Returns the capture groups (1...) of the first match, or nil.
func regexGroups(_ pattern: String, in s: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern),
          let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
    var groups: [String] = []
    if m.numberOfRanges > 1 {
        for i in 1..<m.numberOfRanges {
            if let r = Range(m.range(at: i), in: s) { groups.append(String(s[r])) }
        }
    }
    return groups
}

// MARK: - Disk model

struct DiskInfo: Identifiable, Hashable, Sendable {
    let id: String              // "disk4"
    var name: String
    var sizeBytes: Int64
    var isInternal: Bool
    var isRemovable: Bool
    var isVirtual: Bool
    var bus: String
    var volumes: [String]

    /// Raw device node: much faster than the buffered /dev/diskN.
    var devicePath: String { "/dev/r\(id)" }

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var subtitle: String {
        var parts = ["/dev/\(id)"]
        if !bus.isEmpty { parts.append(bus) }
        parts.append(isInternal ? "Internal" : "External")
        if isVirtual { parts.append("Virtual") }
        if !volumes.isEmpty { parts.append(volumes.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - ewfacquire options

protocol TitledOption: CaseIterable, Identifiable, Hashable {
    var title: String { get }
}

enum EWFFormat: String, TitledOption, Codable {
    case ewf, ewfx, smart
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ewf:   return "EWF (.e01)"
        case .ewfx:  return "EWFX (.e01)"
        case .smart: return "S01 / SMART (.s01)"
        }
    }
    var fileExtension: String {
        switch self {
        case .smart: return "s01"
        case .ewf, .ewfx: return "e01"
        }
    }
}

enum CompressionLevel: String, TitledOption, Codable {
    case none, emptyBlock = "empty-block", fast, best
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None"
        case .emptyBlock: return "Empty-block only"
        case .fast: return "Fast"
        case .best: return "Best"
        }
    }
}

enum DigestType: String, TitledOption, Codable {
    case none, sha1, sha256
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "MD5 only"
        case .sha1: return "MD5 + SHA-1"
        case .sha256: return "MD5 + SHA-256"
        }
    }
}

enum MediaType: String, TitledOption, Codable {
    case fixed, removable, optical, memory
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum MediaFlag: String, TitledOption, Codable {
    case physical, logical
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum SegmentSize: String, TitledOption, Codable {
    case standard, mib650, gib2, gib4, gib8, gib16, gib64
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "Default (1.4 GiB)"
        case .mib650: return "650 MiB (CD)"
        case .gib2: return "2 GiB"
        case .gib4: return "4 GiB"
        case .gib8: return "8 GiB"
        case .gib16: return "16 GiB"
        case .gib64: return "64 GiB"
        }
    }
    var bytes: UInt64? {
        let gib: UInt64 = 1_073_741_824
        switch self {
        case .standard: return nil
        case .mib650: return 650 * 1_048_576
        case .gib2: return 2 * gib
        case .gib4: return 4 * gib
        case .gib8: return 8 * gib
        case .gib16: return 16 * gib
        case .gib64: return 64 * gib
        }
    }
}

// MARK: - Settings

struct AcquireSettings {
    var sourcePath = ""
    var unmountSource = true

    var targetDirectory = ""
    var imageName = ""

    var format = EWFFormat.ewf
    var compression = CompressionLevel.fast
    var digest = DigestType.sha256
    var mediaType = MediaType.fixed
    var mediaFlag = MediaFlag.physical

    var segment = SegmentSize.standard
    var sectorsPerChunk = 64
    var errorGranularity = 64
    var readRetries = 2
    var zeroOnError = true
    var writeLog = true

    var caseNumber = ""
    var evidenceNumber = ""
    var examiner = ""
    var description = ""
    var notes = ""

    /// Image path without extension (ewfacquire appends .E01 etc.).
    var targetBase: String {
        (targetDirectory as NSString).appendingPathComponent(imageName)
    }

    /// "disk4" for /dev/rdisk4, /dev/disk4 or /dev/disk4s2; nil for regular files.
    var sourceWholeDisk: String? {
        guard sourcePath.hasPrefix("/dev/") else { return nil }
        let node = (sourcePath as NSString).lastPathComponent
        return regexGroups(#"^r?(disk\d+)"#, in: node)?.first
    }

    /// `newCompressionSyntax`: libewf >= 2014 expects "method:level" (e.g. deflate:fast).
    func arguments(newCompressionSyntax: Bool, logPath: String? = nil) -> [String] {
        var a = ["-u",                                   // unattended: never prompt
                 "-t", targetBase,
                 "-f", format.rawValue,
                 "-m", mediaType.rawValue,
                 "-M", mediaFlag.rawValue,
                 "-b", String(sectorsPerChunk),
                 "-g", String(min(errorGranularity, sectorsPerChunk))]
        // 2 is ewfacquire's own default; older libewf builds print a warning if it is passed explicitly.
        if readRetries != 2 { a += ["-r", String(readRetries)] }
        a += ["-c", newCompressionSyntax ? "deflate:\(compression.rawValue)" : compression.rawValue]
        if digest != .none { a += ["-d", digest.rawValue] }
        if let bytes = segment.bytes { a += ["-S", String(bytes)] }
        if zeroOnError { a.append("-w") }
        if writeLog { a += ["-l", logPath ?? (targetBase + ".log")] }

        let meta: [(String, String)] = [("-C", caseNumber), ("-E", evidenceNumber),
                                        ("-e", examiner), ("-D", description), ("-N", notes)]
        for (flag, value) in meta {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { a += [flag, v] }
        }
        a.append(sourcePath.isEmpty ? "<source>" : sourcePath)
        return a
    }
}

// MARK: - Saved defaults for section 4 (Image options)

/// The options a user can store as their personal defaults.
struct ImageDefaults: Codable, Equatable {
    var format = EWFFormat.ewf
    var compression = CompressionLevel.fast
    var digest = DigestType.sha256
    var mediaType = MediaType.fixed
    var mediaFlag = MediaFlag.physical
    var segment = SegmentSize.standard
    var sectorsPerChunk = 64
    var errorGranularity = 64
    var readRetries = 2
    var zeroOnError = true
    var writeLog = true
}

extension AcquireSettings {
    var imageDefaults: ImageDefaults {
        ImageDefaults(format: format, compression: compression, digest: digest,
                      mediaType: mediaType, mediaFlag: mediaFlag, segment: segment,
                      sectorsPerChunk: sectorsPerChunk, errorGranularity: errorGranularity,
                      readRetries: readRetries, zeroOnError: zeroOnError, writeLog: writeLog)
    }

    mutating func apply(_ d: ImageDefaults) {
        format = d.format
        compression = d.compression
        digest = d.digest
        mediaType = d.mediaType
        mediaFlag = d.mediaFlag
        segment = d.segment
        sectorsPerChunk = d.sectorsPerChunk
        errorGranularity = d.errorGranularity
        readRetries = d.readRetries
        zeroOnError = d.zeroOnError
        writeLog = d.writeLog
    }
}
