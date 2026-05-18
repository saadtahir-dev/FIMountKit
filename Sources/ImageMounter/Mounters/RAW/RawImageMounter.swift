//
//  RawImageMounter.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public final class RawImageMounter: ImageMounter, @unchecked Sendable {
    public let supportedTypes: [ImageType] = [.raw]

    private let processExecutor: ProcessExecutor
    private let plistParser: HDIUtilPlistParser

    public init(processExecutor: ProcessExecutor = ProcessExecutor(), plistParser: HDIUtilPlistParser = HDIUtilPlistParser()) {
        self.processExecutor = processExecutor
        self.plistParser = plistParser
    }

    private func rootDevice(from device: String) -> String {
        if let range = device.range(of: #"^disk\d+"#, options: .regularExpression) {
            return String(device[range])
        }
        return device
    }

    public func mount(url: URL, options: MountOptions = .default, log: ImageMounterLogHandler? = nil) async throws -> MountResult {
        Logger.log(log, "Mounting RAW image at \(url.path)", component: .rawMounter)

        let hdiutil = SystemToolLocator.path(for: "hdiutil", log: log)
        let devicesBefore = try await HDIUtilHelper.fetchAttachedDevices(using: processExecutor, log: log)
        var parsedForCleanup: HDIUtilMountInfo?

        do {
            var arguments: [String] = [
                "attach",
                url.path,
                "-imagekey",
                "diskimage-class=CRawDiskImage",
                "-nobrowse",
                "-noverify",
                "-plist"
            ]
            
            if let mountPoint = options.volumeMountPoint {
                arguments += ["-mountpoint", mountPoint.path]
            }

            Logger.log(
                log,
                "Mounting with hdiutil. mountPoint = \(options.volumeMountPoint?.path ?? "system default")",
                component: .rawMounter
            )

            let attachResult = try await processExecutor.run(
                executable: hdiutil,
                arguments: arguments,
                throwOnNonZeroExit: false,
                log: log
            )

            Logger.log(log, "hdiutil attach exit: \(attachResult.exitCode)", component: .rawMounter)
            Logger.log(log, "stdout: \(attachResult.stdout)", component: .rawMounter)
            Logger.log(log, "stderr: \(String(attachResult.stderr.prefix(500)))", component: .rawMounter)

            guard attachResult.exitCode == 0 else {
                throw MountError.mountFailed(
                    reason: "hdiutil attach failed (exit \(attachResult.exitCode)). stderr: \(attachResult.stderr)"
                )
            }

            let stdoutData = Data(attachResult.stdout.utf8)

            let parsed: (info: HDIUtilMountInfo, metadata: [String: Any])
            do {
                parsed = try plistParser.parseMountInfo(plistData: stdoutData, log: log)
            } catch {
                let devicesAfter = (try? await HDIUtilHelper.fetchAttachedDevices(using: processExecutor, log: log)) ?? []
                let newDevices = devicesAfter.subtracting(devicesBefore)
                let rootDevices = Set(newDevices.map { rootDevice(from: $0) })

                for device in rootDevices {
                    _ = try? await processExecutor.run(
                        executable: hdiutil,
                        arguments: ["detach", "/dev/\(device)"],
                        throwOnNonZeroExit: false,
                        log: log
                    )
                }

                throw MountError.mountFailed(
                    reason: "Failed to parse hdiutil output. stderr: \(attachResult.stderr)"
                )
            }
            parsedForCleanup = parsed.info

            Logger.log(log, "Mount successful. Mount points: \(parsed.info.mountPoints)", component: .rawMounter)

            return MountResult(
                sourceURL: url,
                type: .raw,
                deviceIdentifiers: parsed.info.deviceIdentifiers,
                mountPointURLs: parsed.info.mountPoints,
                temporaryResources: [],
                metadata: parsed.metadata
            )
        } catch {
            if let info = parsedForCleanup {
                try? await cleanupDetach(using: info.deviceIdentifiers, log: log)
            } else {
                let devicesAfter = (try? await HDIUtilHelper.fetchAttachedDevices(using: processExecutor, log: log)) ?? []
                let newDevices = devicesAfter.subtracting(devicesBefore)
                let rootDevices = Set(newDevices.map { rootDevice(from: $0) })

                for device in rootDevices {
                    _ = try? await processExecutor.run(
                        executable: hdiutil,
                        arguments: ["detach", "/dev/\(device)"],
                        throwOnNonZeroExit: false,
                        log: log
                    )
                }
            }
            throw error
        }
    }

    public func unmount(_ result: MountResult, log: ImageMounterLogHandler? = nil) async throws {
        let hdiutil = SystemToolLocator.path(for: "hdiutil", log: log)
        let rootDevices = Set(result.deviceIdentifiers.map { rootDevice(from: $0) })
        let identifiers = Array(rootDevices)

        guard !identifiers.isEmpty else {
            throw MountError.unmountFailed(reason: "No device identifiers provided in MountResult")
        }

        var detachedAny = false
        var lastError: String?
        for id in identifiers {
            let detachResult = try await processExecutor.run(
                executable: hdiutil,
                arguments: ["detach", "/dev/\(id)"],
                throwOnNonZeroExit: false,
                log: log
            )

            if detachResult.exitCode == 0 {
                detachedAny = true
                continue
            }

            let stderr = detachResult.stderr.lowercased()
            if stderr.contains("no such file") || stderr.contains("not found") || stderr.contains("not attached") {
                Logger.log(
                    log,
                    "Ignoring detach failure for /dev/\(id) (already detached): \(detachResult.stderr)",
                    component: .rawMounter
                )
                continue
            }

            lastError = "hdiutil detach failed for /dev/\(id) (exit \(detachResult.exitCode)): \(detachResult.stderr)"
        }

        if !detachedAny, let lastError {
            throw MountError.unmountFailed(reason: lastError)
        }
    }

    private func cleanupDetach(using deviceIdentifiers: [String], log: ImageMounterLogHandler?) async throws {
        let hdiutil = SystemToolLocator.path(for: "hdiutil", log: log)
        let rootDevices = Set(deviceIdentifiers.map { rootDevice(from: $0) })
        let identifiers = Array(rootDevices)

        for id in identifiers {
            _ = try? await processExecutor.run(
                executable: hdiutil,
                arguments: ["detach", "/dev/\(id)"],
                throwOnNonZeroExit: false,
                log: log
            )
        }
    }
}
