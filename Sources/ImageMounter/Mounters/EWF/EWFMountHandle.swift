//
//  EWFMountHandle.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation
import libewf

public struct EWFMountHandle: Sendable, Equatable {
    public let mountPoint: URL
    public let rawFile: URL
    public let isTemporary: Bool

    public init(mountPoint: URL, rawFile: URL, isTemporary: Bool) {
        self.mountPoint = mountPoint
        self.rawFile = rawFile
        self.isTemporary = isTemporary
    }
}

public final class EWFMountManager: @unchecked Sendable {
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
    ) async throws -> EWFMountHandle {
        let defaultTempRoot = URL(fileURLWithPath: "/tmp/image-mounter", isDirectory: true)
        let baseDir = workspaceDirectory ?? defaultTempRoot
        let resolvedMountPoint = baseDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let isTemporary = (workspaceDirectory == nil)

        Logger.log(
            log,
            "EWF mount resolved: workspace = \(workspaceDirectory?.path ?? "default"), baseDir = \(baseDir.path), mountDir = \(resolvedMountPoint.path), temporary = \(isTemporary)",
            component: .ewfManager
        )
        
        Logger.log(
            log,
            "Resolved mount point: \(resolvedMountPoint.path) (temporary = \(isTemporary))",
            component: .ewfManager
        )
        
        try fileManager.createDirectory(at: resolvedMountPoint, withIntermediateDirectories: true)

        let contents = try fileManager.contentsOfDirectory(atPath: resolvedMountPoint.path)
        guard contents.isEmpty else {
            Logger.log(log, "Mount point is not empty: \(resolvedMountPoint.path)", level: .error, component: .ewfManager)
            throw MountError.mountFailed(reason: "Mount point is not empty")
        }

        Logger.log(log, "Mounting EWF at \(resolvedMountPoint.path)", component: .ewfManager)

        let ewfmountPath = EWFToolLocator.bundledToolPath("ewfmount") ?? SystemToolLocator.path(for: "ewfmount", log: log)

        do {
            let mountResult = try await executor.run(
                executable: ewfmountPath,
                arguments: [url.path, resolvedMountPoint.path],
                throwOnNonZeroExit: true,
                log: log
            )
            
            Logger.log(
                log,
                "ewfmount completed. stdout size = \(mountResult.stdout.utf8.count) stderr size = \(mountResult.stderr.utf8.count)",
                component: .ewfManager
            )
        } catch {
            Logger.log(log, "ewfmount failed: \(error)", level: .error, component: .ewfManager)
            
            if isTemporary {
                try? fileManager.removeItem(at: resolvedMountPoint)
            }
            
            throw error
        }

        let rawFile = resolvedMountPoint.appendingPathComponent("ewf1", isDirectory: false)
        let rawFileAppeared = await FuseMountWaiter.waitForFile(at: rawFile.path, fileManager: fileManager)
        
        guard rawFileAppeared else {
            Logger.log(log, "Missing expected raw file: \(rawFile.path)", level: .error, component: .ewfManager)
            
            let handle = EWFMountHandle(mountPoint: resolvedMountPoint, rawFile: rawFile, isTemporary: isTemporary)
            await unmount(handle, log: log)
            
            throw MountError.mountFailed(reason: "ewfmount did not create expected raw file at \(rawFile.path)")
        }

        Logger.log(log, "EWF mount ready. rawFile=\(rawFile.path)", component: .ewfManager)
        
        return EWFMountHandle(mountPoint: resolvedMountPoint, rawFile: rawFile, isTemporary: isTemporary)
    }

    public func unmount(_ handle: EWFMountHandle, log: ImageMounterLogHandler? = nil) async {
        Logger.log(
            log,
            "Unmounting FUSE mount: \(handle.mountPoint.path) (temporary=\(handle.isTemporary))",
            component: .ewfManager
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
        Logger.log(log, "Temporary mount point removed: \(handle.mountPoint.path)", component: .ewfManager)
    }
}
