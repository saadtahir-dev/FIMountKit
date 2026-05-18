//
//  MountOptions.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public struct MountOptions: Sendable {
    public static let `default` = MountOptions()

    /// Directory used for intermediate processing
    /// (EWF FUSE mount, split RAW merge output, etc.)
    public let workspaceDirectory: URL?

    /// Final mount location (`hdiutil -mountpoint`)
    public let volumeMountPoint: URL?

    public init(
        workspaceDirectory: URL? = nil,
        volumeMountPoint: URL? = nil
    ) {
        self.workspaceDirectory = workspaceDirectory
        self.volumeMountPoint = volumeMountPoint
    }
}
