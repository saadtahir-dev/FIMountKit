//
//  ImageType.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public enum ImageType: String, Sendable, Equatable {
    case dmg
    case sparseImage
    case sparseBundle
    case raw
    case ewf
    case splitRaw
    case vmdk
    case vhd
    case aff4
    case mountedVolume
}
