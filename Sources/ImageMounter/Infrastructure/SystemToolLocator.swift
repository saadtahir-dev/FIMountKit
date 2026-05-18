//
//  SystemToolLocator.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

enum SystemToolLocator {
    static func path(for tool: String, log: ImageMounterLogHandler? = nil) -> String {
        let fileManager = FileManager.default

        let candidates = [
            "/usr/bin/\(tool)",
            "/usr/local/bin/\(tool)",
            "/opt/homebrew/bin/\(tool)",
        ]

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            Logger.log(log, "Resolved system tool: \(tool) -> \(path)", component: .process)
            return path
        }

        Logger.log(log, "System tool not found, falling back to PATH: \(tool)", component: .process)
        return tool
    }
}
