//
//  ImageMountingService.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public protocol ImageMountingServiceType {
    func mount(url: URL, options: MountOptions) async throws -> MountResult
    func unmount(_ result: MountResult) async throws
}

extension ImageMountingServiceType {
    public func mount(url: URL) async throws -> MountResult {
        try await mount(url: url, options: MountOptions.default)
    }
}

public final class ImageMountingService: ImageMountingServiceType, @unchecked Sendable {
    private let detector: ImageFormatDetecting
    private let mounters: [ImageMounter]
    private let log: ImageMounterLogHandler?

    public init(
        detector: ImageFormatDetecting = ImageFormatDetector(),
        mounters: [ImageMounter] = ImageMounterFactory.makeDefaultMounters(),
        log: ImageMounterLogHandler? = nil
    ) {
        self.detector = detector
        self.mounters = mounters
        self.log = log
    }

    public func mount(url: URL, options: MountOptions = .default) async throws -> MountResult {
        let mountID = UUID().uuidString
        let scopedLog: ImageMounterLogHandler? = log.map { baseLog in
            return { message, level, component in
                baseLog("[\(mountID)] \(message)", level, component)
            }
        }

        Logger.log(scopedLog, "Mount requested: \(url.path)", component: .service)

        let normalizedWorkspace = options.workspaceDirectory?
            .standardizedFileURL
            .resolvingSymlinksInPath()

        let normalizedMountPoint = options.volumeMountPoint?
            .standardizedFileURL
            .resolvingSymlinksInPath()

        if let original = options.workspaceDirectory,
           original.path != normalizedWorkspace?.path {
            Logger.log(
                scopedLog,
                "Normalized workspaceDirectory: \(original.path) -> \(normalizedWorkspace!.path)",
                component: .service
            )
        }

        if let original = options.volumeMountPoint,
           original.path != normalizedMountPoint?.path {
            Logger.log(
                scopedLog,
                "Normalized volumeMountPoint: \(original.path) -> \(normalizedMountPoint!.path)",
                component: .service
            )
        }

        let effectiveOptions = MountOptions(
            workspaceDirectory: normalizedWorkspace,
            volumeMountPoint: normalizedMountPoint
        )

        let workspace = effectiveOptions.workspaceDirectory?.path ?? "default(/tmp/image-mounter/*)"
        let mountPoint = effectiveOptions.volumeMountPoint?.path ?? "system default (/Volumes)"

        Logger.log(
            scopedLog,
            """
            MountOptions resolved:
            workspaceDirectory=\(workspace)
            volumeMountPoint=\(mountPoint)
            """,
            component: .service
        )

        if let workspace = effectiveOptions.workspaceDirectory {
            try MountPathValidator.validateWorkspace(workspace)
        }

        if let mountPoint = effectiveOptions.volumeMountPoint {
            try MountPathValidator.validateMountPoint(mountPoint)
        }

        let type = try detector.detect(url, log: scopedLog)

        guard let mounter = mounters.first(where: { $0.supportedTypes.contains(type) }) else {
            Logger.log(scopedLog, "No mounter found for type: \(type)", level: .error, component: .service)
            throw MountError.unsupportedType
        }

        Logger.log(scopedLog, "Selected mounter: \(String(describing: Swift.type(of: mounter)))", component: .service)
        return try await mounter.mount(url: url, options: effectiveOptions, log: scopedLog)
    }

    public func unmount(_ result: MountResult) async throws {
        let mountID = UUID().uuidString
        let scopedLog: ImageMounterLogHandler? = log.map { baseLog in
            return { message, level, component in
                baseLog("[\(mountID)] \(message)", level, component)
            }
        }

        Logger.log(scopedLog, "Unmount requested for type: \(result.type)", component: .service)
        guard let mounter = mounters.first(where: { $0.supportedTypes.contains(result.type) }) else {
            Logger.log(scopedLog, "No mounter found for type: \(result.type)", level: .error, component: .service)
            throw MountError.unsupportedType
        }

        Logger.log(scopedLog, "Selected mounter: \(String(describing: Swift.type(of: mounter)))", component: .service)
        try await mounter.unmount(result, log: scopedLog)
    }
}
