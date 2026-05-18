//
//  HDIUtilHelper.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

enum HDIUtilHelper {
    static func fetchAttachedDevices(
        using executor: ProcessExecutor,
        log: ImageMounterLogHandler? = nil
    ) async throws -> Set<String> {
        Logger.log(
            log,
            "Fetching attached devices via hdiutil info -plist",
            component: .process
        )

        let hdiutil = SystemToolLocator.path(for: "hdiutil", log: log)
        let infoResult = try await executor.run(
            executable: hdiutil,
            arguments: ["info", "-plist"],
            throwOnNonZeroExit: false,
            log: log
        )

        guard infoResult.exitCode == 0 else {
        Logger.log(
            log,
            "hdiutil info -plist failed (exit \(infoResult.exitCode))",
            level: .error,
            component: .process
        )

            throw MountError.mountFailed(
                reason: "hdiutil info -plist failed (exit \(infoResult.exitCode)): \(infoResult.stderr)"
            )
        }

        let data = Data(infoResult.stdout.utf8)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        guard let dict = plist as? [String: Any] else {
            throw MountError.invalidPlist
        }

        guard let images = dict["images"] as? [[String: Any]] else {
            return []
        }

        var devices: Set<String> = []

        for image in images {
            guard let systemEntities = image["system-entities"] as? [[String: Any]] else { continue }

            for entity in systemEntities {
                guard let devEntry = entity["dev-entry"] as? String, !devEntry.isEmpty else { continue }

                let identifier = devEntry.hasPrefix("/dev/")
                    ? String(devEntry.dropFirst("/dev/".count))
                    : devEntry

                devices.insert(identifier)
            }
        }

        Logger.log(
            log,
            "Found \(devices.count) attached devices",
            component: .process
        )
        return devices
    }
}
