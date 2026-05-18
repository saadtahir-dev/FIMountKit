//
//  SplitRawImageMounter.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public final class SplitRawImageMounter: ImageMounter, @unchecked Sendable {
    public let supportedTypes: [ImageType] = [.splitRaw]

    private let merger: SplitRawMerger
    private let rawMounter: RawImageMounter

    public init(
        merger: SplitRawMerger = SplitRawMerger(),
        rawMounter: RawImageMounter = RawImageMounter()
    ) {
        self.merger = merger
        self.rawMounter = rawMounter
    }

    public func mount(url: URL, options: MountOptions = .default, log: ImageMounterLogHandler? = nil) async throws -> MountResult {
        Logger.log(log, "Mounting split RAW starting at: \(url.path)", component: .splitRawMounter)
        let output = options.workspaceDirectory?
            .appendingPathComponent("\(UUID().uuidString).raw")
        let handle = try merger.merge(url, output: output, log: log)
        Logger.log(log, "Merged file: \(handle.mergedFile.path) (temporary=\(handle.isTemporary))", component: .splitRawMounter)

        do {
            Logger.log(log, "Delegating mount to RawImageMounter", component: .splitRawMounter)
            var result = try await rawMounter.mount(url: handle.mergedFile, options: options, log: log)

            result = MountResult(
                sourceURL: url,
                type: .splitRaw,
                deviceIdentifiers: result.deviceIdentifiers,
                mountPointURLs: result.mountPointURLs,
                temporaryResources: [
                    TemporaryResource(
                        url: handle.mergedFile,
                        isTemporary: handle.isTemporary
                    )
                ],
                metadata: result.metadata
            )

            Logger.log(log, "Mount successful. Mount points: \(result.mountPointURLs)", component: .splitRawMounter)
            return result
        } catch {
            Logger.log(log, "Mount failed after merge: \(error)", level: .error, component: .splitRawMounter)
            if handle.isTemporary {
                try? FileManager.default.removeItem(at: handle.mergedFile)
            }
            throw error
        }
    }

    public func unmount(_ result: MountResult, log: ImageMounterLogHandler? = nil) async throws {
        Logger.log(log, "Unmounting split RAW", component: .splitRawMounter)
        try await rawMounter.unmount(result, log: log)

        for resource in result.temporaryResources.reversed() {
            if resource.isTemporary {
                try? FileManager.default.removeItem(at: resource.url)
            }
        }
        Logger.log(log, "Unmount complete", component: .splitRawMounter)
    }
}
