//
//  VMDKImageMounter.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public final class VMDKImageMounter: ImageMounter, @unchecked Sendable {
    public let supportedTypes: [ImageType] = [.vmdk]

    private let vmdkManager: VMDKMountManager
    private let rawMounter: RawImageMounter

    public init(
        vmdkManager: VMDKMountManager = VMDKMountManager(),
        rawMounter: RawImageMounter = RawImageMounter()
    ) {
        self.vmdkManager = vmdkManager
        self.rawMounter = rawMounter
    }

    public func mount(url: URL, options: MountOptions = .default, log: ImageMounterLogHandler? = nil) async throws -> MountResult {
        Logger.log(log, "Mounting VMDK: \(url.path)", component: .vmdkMounter)
        let handle = try await vmdkManager.mount(url, workspaceDirectory: options.workspaceDirectory, log: log)
        Logger.log(log, "VMDK raw file: \(handle.rawFile.path)", component: .vmdkMounter)

        do {
            var result = try await rawMounter.mount(url: handle.rawFile, options: options, log: log)

            result = MountResult(
                sourceURL: url,
                type: .vmdk,
                deviceIdentifiers: result.deviceIdentifiers,
                mountPointURLs: result.mountPointURLs,
                temporaryResources: [
                    TemporaryResource(
                        url: handle.mountPoint,
                        isTemporary: handle.isTemporary,
                        kind: .vmdkMount
                    )
                ],
                metadata: result.metadata
            )

            Logger.log(log, "Mount points: \(result.mountPointURLs)", component: .vmdkMounter)
            return result
        } catch {
            await vmdkManager.unmount(handle, log: log)
            throw error
        }
    }

    public func unmount(_ result: MountResult, log: ImageMounterLogHandler? = nil) async throws {
        Logger.log(log, "Unmounting VMDK", component: .vmdkMounter)
        try await rawMounter.unmount(result, log: log)

        for resource in result.temporaryResources.reversed() {
            let handle = VMDKMountHandle(
                mountPoint: resource.url,
                rawFile: resource.url.appendingPathComponent("vmdk1", isDirectory: false),
                isTemporary: resource.isTemporary
            )
            await vmdkManager.unmount(handle, log: log)
        }
        Logger.log(log, "Unmount complete", component: .vmdkMounter)
    }
}
