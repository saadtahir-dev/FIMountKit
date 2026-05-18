//
//  ImageFormatDetector.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public protocol ImageFormatDetecting {
    func detect(_ url: URL, log: ImageMounterLogHandler?) throws -> ImageType
}

public struct ImageFormatDetector: ImageFormatDetecting {
    public init() {}

    public func detect(_ url: URL, log: ImageMounterLogHandler? = nil) throws -> ImageType {
        let ext = url.pathExtension.lowercased()
        Logger.log(
            log,
            "Detecting image type for extension: \(ext)",
            component: .service
        )

        let type: ImageType
        switch ext {
        case "dmg":                     type = .dmg
        case "sparseimage":             type = .sparseImage
        case "sparsebundle":            type = .sparseBundle
        case "raw", "dd":               type = .raw
        case "e01", "ex01", "s01":      type = .ewf
        case "000", "001", "00001":     type = .splitRaw
        case "vmdk":                    type = .vmdk
        case "vhd":                     type = .vhd
        case "aff4":                    type = .aff4
        default:                        throw MountError.detectionFailed
        }

        Logger.log(
            log,
            "Detected type: \(type.rawValue)",
            component: .service
        )

        return type
    }
}
