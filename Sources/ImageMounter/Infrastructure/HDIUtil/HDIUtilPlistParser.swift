//
//  HDIUtilPlistParser.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public struct HDIUtilMountInfo: Sendable, Equatable {
    public let deviceIdentifiers: [String]
    public let mountPoints: [URL]

    public init(deviceIdentifiers: [String], mountPoints: [URL]) {
        self.deviceIdentifiers = deviceIdentifiers
        self.mountPoints = mountPoints
    }
}

public struct HDIUtilPlistParser: Sendable {
    public init() {}

    public func parseMountInfo(
        plistData: Data,
        log: ImageMounterLogHandler? = nil
    ) throws -> (info: HDIUtilMountInfo, metadata: [String: Any]) {
        Logger.log(log, "Parsing hdiutil plist (size: \(plistData.count) bytes)", component: .parser)

        let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
        guard let dict = plist as? [String: Any] else {
            throw MountError.invalidPlist
        }

        Logger.log(log, "Top-level keys: \(dict.keys)", component: .parser)

        guard let systemEntities = dict["system-entities"] as? [[String: Any]] else {
            throw MountError.parsingFailed
        }

        var deviceIdentifiers: [String] = []
        var mountPoints: [URL] = []

        for entity in systemEntities {
            Logger.log(log, "Processing entity: \(entity)", component: .parser)
            if let devEntry = entity["dev-entry"] as? String {
                let identifier = devEntry.replacingOccurrences(of: "/dev/", with: "")
                Logger.log(log, "Found device: \(identifier)", component: .parser)
                deviceIdentifiers.append(identifier)
            }

            if let mountPoint = entity["mount-point"] as? String {
                Logger.log(log, "Found mount point: \(mountPoint)", component: .parser)
                mountPoints.append(URL(fileURLWithPath: mountPoint))
            }
        }

        Logger.log(log, "Parsed devices: \(deviceIdentifiers)", component: .parser)
        Logger.log(log, "Parsed mountPoints: \(mountPoints)", component: .parser)

        guard !mountPoints.isEmpty else {
            Logger.log(log, "No mountable volumes found in plist", level: .error, component: .parser)
            throw MountError.mountFailed(reason: "No mountable volumes found")
        }

        return (HDIUtilMountInfo(deviceIdentifiers: deviceIdentifiers, mountPoints: mountPoints), dict)
    }
}
