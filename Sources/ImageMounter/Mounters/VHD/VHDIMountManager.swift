//
//  VHDIMountManager.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation
import LibVHDI

public final class VHDIMountManager: @unchecked Sendable {
    private let executor: ProcessExecutor
    private let fileManager: FileManager

    public init(
        executor: ProcessExecutor = ProcessExecutor(),
        fileManager: FileManager = .default
    ) {
        self.executor = executor
        self.fileManager = fileManager
    }

    public func mount(
        _ url: URL,
        workspaceDirectory: URL?,
        log: ImageMounterLogHandler? = nil
    ) async throws -> VHDIMountHandle {
        let defaultTempRoot = URL(fileURLWithPath: "/tmp/image-mounter", isDirectory: true)
        let baseDir = workspaceDirectory ?? defaultTempRoot
        let resolvedMountPoint = baseDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let isTemporary = (workspaceDirectory == nil)

        Logger.log(
            log,
            "VHDI mount resolved: workspace = \(workspaceDirectory?.path ?? "default"), baseDir = \(baseDir.path), mountDir = \(resolvedMountPoint.path), temporary = \(isTemporary)",
            component: .vhdiManager
        )

        Logger.log(
            log,
            "Resolved mount point: \(resolvedMountPoint.path) (temporary = \(isTemporary))",
            component: .vhdiManager
        )

        try fileManager.createDirectory(at: resolvedMountPoint, withIntermediateDirectories: true)

        let contents = try fileManager.contentsOfDirectory(atPath: resolvedMountPoint.path)
        guard contents.isEmpty else {
            Logger.log(log, "Mount point is not empty: \(resolvedMountPoint.path)", level: .error, component: .vhdiManager)
            throw MountError.mountFailed(reason: "Mount point is not empty")
        }

        Logger.log(log, "Mounting VHDI at \(resolvedMountPoint.path)", component: .vhdiManager)

        let vhdimountPath = VHDIToolLocator.vhdimount ?? SystemToolLocator.path(for: "vhdimount", log: log)

        do {
            let mountResult = try await executor.run(
                executable: vhdimountPath,
                arguments: [url.path, resolvedMountPoint.path],
                throwOnNonZeroExit: true,
                log: log
            )

            Logger.log(
                log,
                "vhdimount completed. stdout size = \(mountResult.stdout.utf8.count) stderr size = \(mountResult.stderr.utf8.count)",
                component: .vhdiManager
            )
        } catch {
            Logger.log(log, "vhdimount failed: \(error)", level: .error, component: .vhdiManager)

            if isTemporary {
                try? fileManager.removeItem(at: resolvedMountPoint)
            }

            throw error
        }

        let rawFile = resolvedMountPoint.appendingPathComponent("vhdi1", isDirectory: false)
        guard fileManager.fileExists(atPath: rawFile.path) else {
            Logger.log(log, "Missing expected raw file: \(rawFile.path)", level: .error, component: .vhdiManager)

            let handle = VHDIMountHandle(mountPoint: resolvedMountPoint, rawFile: rawFile, isTemporary: isTemporary)
            await unmount(handle, log: log)

            throw MountError.mountFailed(reason: "vhdimount did not create expected raw file at \(rawFile.path)")
        }

        Logger.log(log, "VHDI mount ready. rawFile=\(rawFile.path)", component: .vhdiManager)

        return VHDIMountHandle(mountPoint: resolvedMountPoint, rawFile: rawFile, isTemporary: isTemporary)
    }

    public func unmount(_ handle: VHDIMountHandle, log: ImageMounterLogHandler? = nil) async {
        Logger.log(
            log,
            "Unmounting FUSE mount: \(handle.mountPoint.path) (temporary=\(handle.isTemporary))",
            component: .vhdiManager
        )
        let umountPath = SystemToolLocator.path(for: "umount", log: log)
        let diskutilPath = SystemToolLocator.path(for: "diskutil", log: log)

        _ = try? await executor.run(
            executable: umountPath,
            arguments: [handle.mountPoint.path],
            throwOnNonZeroExit: false,
            log: log
        )

        _ = try? await executor.run(
            executable: diskutilPath,
            arguments: ["unmount", handle.mountPoint.path],
            throwOnNonZeroExit: false,
            log: log
        )

        guard handle.isTemporary else { return }
        try? fileManager.removeItem(at: handle.mountPoint)
        Logger.log(log, "Temporary mount point removed: \(handle.mountPoint.path)", component: .vhdiManager)
    }
}
