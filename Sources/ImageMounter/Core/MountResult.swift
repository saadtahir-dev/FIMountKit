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
