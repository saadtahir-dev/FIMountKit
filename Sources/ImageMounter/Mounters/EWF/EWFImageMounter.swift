//
//  EWFImageMounter.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public final class EWFImageMounter: ImageMounter, @unchecked Sendable {
    public let supportedTypes: [ImageType] = [.ewf]

    private let ewfManager: EWFMountManager
    private let rawMounter: RawImageMounter

    public init(
        ewfManager: EWFMountManager = EWFMountManager(),
        rawMounter: RawImageMounter = RawImageMounter()
    ) {
        self.ewfManager = ewfManager
        self.rawMounter = rawMounter
    }

    public func mount(url: URL, options: MountOptions = .default, log: ImageMounterLogHandler? = nil) async throws -> MountResult {
        Logger.log(log, "Mounting EWF: \(url.path)", component: .ewfMounter)
        let handle = try await ewfManager.mount(url, workspaceDirectory: options.workspaceDirectory, log: log)
        Logger.log(log, "EWF raw file: \(handle.rawFile.path)", component: .ewfMounter)

        do {
            var result = try await rawMounter.mount(url: handle.rawFile, options: options, log: log)

            result = MountResult(
                sourceURL: url,
                type: .ewf,
                deviceIdentifiers: result.deviceIdentifiers,
                mountPointURLs: result.mountPointURLs,
                temporaryResources: [
                    TemporaryResource(
                        url: handle.mountPoint,
                        isTemporary: handle.isTemporary
                    )
                ],
                metadata: result.metadata
            )

            Logger.log(log, "Mount points: \(result.mountPointURLs)", component: .ewfMounter)
            return result
        } catch {
            await ewfManager.unmount(handle, log: log)
            throw error
        }
    }

    public func unmount(_ result: MountResult, log: ImageMounterLogHandler? = nil) async throws {
        Logger.log(log, "Unmounting EWF", component: .ewfMounter)
        try await rawMounter.unmount(result, log: log)

        for resource in result.temporaryResources.reversed() {
            let handle = EWFMountHandle(
                mountPoint: resource.url,
                rawFile: resource.url.appendingPathComponent("ewf1"),
                isTemporary: resource.isTemporary
            )
            await ewfManager.unmount(handle, log: log)
        }
        Logger.log(log, "Unmount complete", component: .ewfMounter)
    }
}
