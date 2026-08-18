//
//  MountError.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public enum MountError: Error, Sendable, Equatable {
    case unsupportedType
    case detectionFailed

    case mountFailed(reason: String)
    case unmountFailed(reason: String)

    case parsingFailed
    case invalidPlist

    case exposeFailed(reason: String)

    case insufficientSpace(required: Int64, available: Int64)
}

extension MountError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return "Unsupported image type"
            
        case .detectionFailed:
            return "Failed to detect image type"
            
        case .mountFailed(let reason):
            return reason
            
        case .unmountFailed(let reason):
            return reason
            
        case .parsingFailed:
            return "Failed to parse mount information"
        
        case .invalidPlist:
            return "Invalid plist output"
        
        case .exposeFailed(let reason):
            return reason

        case .insufficientSpace(let required, let available):
            return "Not enough space to merge split RAW: need \(required) bytes, have \(available) bytes"
        }
    }
}
