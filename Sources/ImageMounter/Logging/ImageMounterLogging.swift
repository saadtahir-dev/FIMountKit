//
//  ImageMounterLogging.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public typealias ImageMounterLogHandler = (
    _ message: String,
    _ level: ImageMounterLogLevel,
    _ component: ImageMounterComponent
) -> Void

public enum ImageMounterComponent: String {
    case service            = "ImageMountingService"
    case dmgMounter         = "DMGImageMounter"
    case rawMounter         = "RawImageMounter"
    case aff4Mounter        = "AFF4ImageMounter"
    case ewfMounter         = "EWFImageMounter"
    case ewfManager         = "EWFMountManager"
    case vmdkMounter        = "VMDKImageMounter"
    case vmdkManager        = "VMDKMountManager"
    case vhdiMounter        = "VHDIImageMounter"
    case vhdiManager        = "VHDIMountManager"
    case splitRawMounter    = "SplitRawImageMounter"
    case splitRawMerger     = "SplitRawMerger"
    case parser             = "HDIUtilPlistParser"
    case process            = "ProcessRunner"
}

public enum ImageMounterLogLevel: String {
    case debug
    case info
    case warning
    case error
}

enum Logger {
    @inline(__always)
    static func log(
        _ handler: ImageMounterLogHandler?,
        _ message: String,
        level: ImageMounterLogLevel = .info,
        component: ImageMounterComponent
    ) {
        handler?(message, level, component)
    }
}
