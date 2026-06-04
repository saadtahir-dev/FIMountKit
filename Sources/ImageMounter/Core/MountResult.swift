//
//  MountResult.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public struct TemporaryResource: Sendable {
    public enum Kind: String, Sendable {
        case ewfMount
        case vmdkMount
        case vhdiMount
        // future: case mergedRaw, cache, etc.
    }
    
    public let url: URL
    public let isTemporary: Bool
    public let kind: Kind
    
    public init(url: URL, isTemporary: Bool, kind: Kind = .ewfMount) {
        self.url = url
        self.isTemporary = isTemporary
        self.kind = kind
    }
}

public struct MountResult: Sendable {
    public let sourceURL: URL
    public let type: ImageType
    
    /// Stable identifiers (e.g. "disk4", "disk5s1")
    public let deviceIdentifiers: [String]
    
    /// One or more mount points
    public let mountPointURLs: [URL]
    
    /// Temp artifacts (EWF raw, merged splits, etc.)
    public let temporaryResources: [TemporaryResource]
    
    /// Raw plist/debug metadata
    public let metadata: [String: Any]
    
    public init(
        sourceURL: URL,
        type: ImageType,
        deviceIdentifiers: [String],
        mountPointURLs: [URL],
        temporaryResources: [TemporaryResource],
        metadata: [String: Any]
    ) {
        self.sourceURL = sourceURL
        self.type = type
        self.deviceIdentifiers = deviceIdentifiers
        self.mountPointURLs = mountPointURLs
        self.temporaryResources = temporaryResources
        self.metadata = metadata
    }
}

public extension MountResult {
    static func mountedVolume(from mountPointURL: URL) throws -> MountResult {
        func string<T>(from tuple: inout T) -> String {
            withUnsafePointer(to: &tuple) {
                $0.withMemoryRebound(
                    to: CChar.self,
                    capacity: MemoryLayout<T>.size
                ) {
                    String(cString: $0)
                }
            }
        }
        var stat = statfs()
        
        guard statfs(mountPointURL.path, &stat) == 0 else {
            throw MountError.mountFailed(
                reason: "Failed to inspect mount point: \(mountPointURL.path)"
            )
        }
        
        let actualMountPoint = string(from: &stat.f_mntonname)
        let devicePath = string(from: &stat.f_mntfromname)
        let filesystemType = string(from: &stat.f_fstypename)
        
        guard actualMountPoint == mountPointURL.path else {
            throw MountError.mountFailed(
                reason: "\(mountPointURL.path) is not a mount point"
            )
        }
        
        guard devicePath.hasPrefix("/dev/") else {
            throw MountError.mountFailed(
                reason: "\(mountPointURL.path) is not backed by a local block device"
            )
        }
        
        let diskIdentifier = URL(fileURLWithPath: devicePath)
            .lastPathComponent
        
        return MountResult(
            sourceURL: mountPointURL,
            type: .mountedVolume,
            deviceIdentifiers: [diskIdentifier],
            mountPointURLs: [URL(fileURLWithPath: actualMountPoint)],
            temporaryResources: [],
            metadata: [
                "devicePath": devicePath,
                "filesystemType": filesystemType
            ]
        )
    }
}
