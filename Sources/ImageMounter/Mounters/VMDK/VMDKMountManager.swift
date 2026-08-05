//
//  VMDKMountManager.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation
import LibVMDK

public final class VMDKMountManager: @unchecked Sendable {
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
    ) async throws -> VMDKMountHandle {
        let defaultTempRoot = URL(fileURLWithPath: "/tmp/image-mounter", isDirectory: true)
        let baseDir = workspaceDirectory ?? defaultTempRoot
        let resolvedMountPoint = baseDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let isTemporary = (workspaceDirectory == nil)

        Logger.log(
            log,
            "VMDK mount resolved: workspace = \(workspaceDirectory?.path ?? "default"), baseDir = \(baseDir.path), mountDir = \(resolvedMountPoint.path), temporary = \(isTemporary)",
            component: .vmdkManager
        )

        Logger.log(
            log,
            "Resolved mount point: \(resolvedMountPoint.path) (temporary = \(isTemporary))",
            component: .vmdkManager
        )

        try fileManager.createDirectory(at: resolvedMountPoint, withIntermediateDirectories: true)

        let contents = try fileManager.contentsOfDirectory(atPath: resolvedMountPoint.path)
        guard contents.isEmpty else {
            Logger.log(log, "Mount point is not empty: \(resolvedMountPoint.path)", level: .error, component: .vmdkManager)
            throw MountError.mountFailed(reason: "Mount point is not empty")
        }

        Logger.log(log, "Mounting VMDK at \(resolvedMountPoint.path)", component: .vmdkManager)

        let vmdkmountPath = VMDKToolLocator.vmdkmount ?? SystemToolLocator.path(for: "vmdkmount", log: log)

        do {
            let mountResult = try await executor.run(
                executable: vmdkmountPath,
                arguments: [url.path, resolvedMountPoint.path],
                throwOnNonZeroExit: true,
                log: log
            )

            Logger.log(
                log,
                "vmdkmount completed. stdout size = \(mountResult.stdout.utf8.count) stderr size = \(mountResult.stderr.utf8.count)",
                component: .vmdkManager
            )
        } catch {
            Logger.log(log, "vmdkmount failed: \(error)", level: .error, component: .vmdkManager)

            if isTemporary {
                try? fileManager.removeItem(at: resolvedMountPoint)
            }

            throw error
        }

        let rawFile = resolvedMountPoint.appendingPathComponent("vmdk1", isDirectory: false)
        let rawFileAppeared = await FuseMountWaiter.waitForFile(at: rawFile.path, fileManager: fileManager)
        
        guard rawFileAppeared else {
            Logger.log(log, "Missing expected raw file: \(rawFile.path)", level: .error, component: .vmdkManager)

            let handle = VMDKMountHandle(mountPoint: resolvedMountPoint, rawFile: rawFile, isTemporary: isTemporary)
            await unmount(handle, log: log)

            throw MountError.mountFailed(reason: "vmdkmount did not create expected raw file at \(rawFile.path)")
        }

        Logger.log(log, "VMDK mount ready. rawFile=\(rawFile.path)", component: .vmdkManager)

        return VMDKMountHandle(mountPoint: resolvedMountPoint, rawFile: rawFile, isTemporary: isTemporary)
    }

    public func unmount(_ handle: VMDKMountHandle, log: ImageMounterLogHandler? = nil) async {
        Logger.log(
            log,
            "Unmounting FUSE mount: \(handle.mountPoint.path) (temporary=\(handle.isTemporary))",
            component: .vmdkManager
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
        Logger.log(log, "Temporary mount point removed: \(handle.mountPoint.path)", component: .vmdkManager)
    }
}
