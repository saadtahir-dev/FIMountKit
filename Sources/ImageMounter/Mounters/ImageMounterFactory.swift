//
//  ImageMounterFactory.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public enum ImageMounterFactory {
    public static func makeDefaultMounters() -> [ImageMounter] {
        [
            DMGImageMounter(),
            RawImageMounter(),
            AFF4ImageMounter(),
            EWFImageMounter(),
            VMDKImageMounter(),
            VHDIImageMounter(),
            SplitRawImageMounter()
        ]
    }
}
