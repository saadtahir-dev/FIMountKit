//
//  VMDKMountHandle.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public struct VMDKMountHandle: Sendable, Equatable {
    public let mountPoint: URL
    public let rawFile: URL
    public let isTemporary: Bool

    public init(mountPoint: URL, rawFile: URL, isTemporary: Bool) {
        self.mountPoint = mountPoint
        self.rawFile = rawFile
        self.isTemporary = isTemporary
    }
}
