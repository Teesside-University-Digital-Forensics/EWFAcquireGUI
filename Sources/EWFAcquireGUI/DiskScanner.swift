import Foundation

enum DiskScanner {
    private static let diskutil = "/usr/sbin/diskutil"

    private static func plist(_ args: [String]) -> [String: Any]? {
        let data = Shell.runData(diskutil, args)
        guard !data.isEmpty else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    /// Lists whole disks (physical, external, virtual and disk images).
    static func scan() -> [DiskInfo] {
        guard let list = plist(["list", "-plist"]),
              let wholeDisks = list["WholeDisks"] as? [String] else { return [] }
        let tree = list["AllDisksAndPartitions"] as? [[String: Any]] ?? []

        var result: [DiskInfo] = []
        for id in wholeDisks {
            guard let info = plist(["info", "-plist", id]) else { continue }

            let size = (info["TotalSize"] as? NSNumber)?.int64Value
                ?? (info["Size"] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else { continue }

            var name = (info["MediaName"] as? String) ?? ""
            if name.isEmpty { name = (info["IORegistryEntryName"] as? String) ?? id }

            var volumes: [String] = []
            if let entry = tree.first(where: { ($0["DeviceIdentifier"] as? String) == id }) {
                for key in ["Partitions", "APFSVolumes"] {
                    for part in entry[key] as? [[String: Any]] ?? [] {
                        if let v = part["VolumeName"] as? String, !v.isEmpty {
                            volumes.append(v)
                        } else if let c = part["Content"] as? String, !c.isEmpty {
                            volumes.append(c)
                        }
                    }
                }
            }

            result.append(DiskInfo(
                id: id,
                name: name,
                sizeBytes: size,
                isInternal: (info["Internal"] as? Bool) ?? false,
                isRemovable: (info["RemovableMediaOrExternalDevice"] as? Bool)
                    ?? (info["RemovableMedia"] as? Bool) ?? false,
                isVirtual: (info["VirtualOrPhysical"] as? String) == "Virtual",
                bus: (info["BusProtocol"] as? String) ?? "",
                volumes: volumes
            ))
        }

        func number(_ s: String) -> Int { Int(s.dropFirst(4)) ?? 0 }
        return result.sorted { number($0.id) < number($1.id) }
    }

    /// Whole-disk identifiers that back the volume containing `path`
    /// (includes APFS physical stores). Used to refuse writing the image
    /// onto the disk that is being acquired.
    static func wholeDiskIDs(containing path: String) -> Set<String> {
        guard let info = plist(["info", "-plist", path]) else { return [] }
        var ids = Set<String>()
        if let parent = info["ParentWholeDisk"] as? String { ids.insert(parent) }
        if let stores = info["APFSPhysicalStores"] as? [[String: Any]] {
            for store in stores {
                if let dev = store["APFSPhysicalStore"] as? String,
                   let whole = regexGroups(#"^(disk\d+)"#, in: dev)?.first {
                    ids.insert(whole)
                }
            }
        }
        return ids
    }
}
