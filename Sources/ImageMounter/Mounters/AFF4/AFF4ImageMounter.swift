//
//  AFF4ImageMounter.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation
import Libcaff4

public final class AFF4ImageMounter: ImageMounter, @unchecked Sendable {
    public let supportedTypes: [ImageType] = [.aff4]

    private let rawMounter: RawImageMounter
    private let chunkSize: Int = 4 * 1024 * 1024

    public init(rawMounter: RawImageMounter = RawImageMounter()) {
        self.rawMounter = rawMounter
    }

    public func mount(url: URL, options: MountOptions, log: ImageMounterLogHandler?) async throws -> MountResult {
        Logger.log(log, "Mounting AFF4: \(url.path)", component: .aff4Mounter)

        let image = try AFF4Image(path: url.path)
        let totalSize = image.size

        let tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".img")

        var wroteTempFile = false
        do {
            FileManager.default.createFile(atPath: tempFileURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: tempFileURL)
            wroteTempFile = true
            defer { try? handle.close() }
            defer { image.close() }

            var offset: UInt64 = 0
            while offset < totalSize {
                let remaining = totalSize - offset
                let readLen = Int(min(UInt64(chunkSize), remaining))
                let data = try image.read(offset: offset, length: readLen)
                try handle.write(contentsOf: data)
                offset += UInt64(data.count)
            }

            Logger.log(log, "Delegating mount to RawImageMounter: \(tempFileURL.path)", component: .aff4Mounter)
            var result = try await rawMounter.mount(url: tempFileURL, options: options, log: log)

            result = MountResult(
                sourceURL: url,
                type: .aff4,
                deviceIdentifiers: result.deviceIdentifiers,
                mountPointURLs: result.mountPointURLs,
                temporaryResources: [
                    TemporaryResource(
                        url: tempFileURL,
                        isTemporary: true,
                        kind: .ewfMount
                    )
                ],
                metadata: result.metadata
            )

            Logger.log(log, "Mount successful. Mount points: \(result.mountPointURLs)", component: .aff4Mounter)
            return result
        } catch {
            Logger.log(log, "Mount failed: \(error)", level: .error, component: .aff4Mounter)
            image.close()

            if wroteTempFile {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
            throw error
        }
    }

    public func unmount(_ result: MountResult, log: ImageMounterLogHandler?) async throws {
        Logger.log(log, "Unmounting AFF4", component: .aff4Mounter)
        try await rawMounter.unmount(result, log: log)

        for resource in result.temporaryResources.reversed() {
            if resource.isTemporary {
                try? FileManager.default.removeItem(at: resource.url)
            }
        }

        Logger.log(log, "Unmount complete", component: .aff4Mounter)
    }
}

