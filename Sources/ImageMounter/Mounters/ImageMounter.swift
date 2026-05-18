//
//  ImageMounter.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public protocol ImageMounter {
    var supportedTypes: [ImageType] { get }

    func mount(url: URL, options: MountOptions, log: ImageMounterLogHandler?) async throws -> MountResult
    func unmount(_ result: MountResult, log: ImageMounterLogHandler?) async throws
}
