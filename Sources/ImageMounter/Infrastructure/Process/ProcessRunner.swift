//
//  ProcessRunner.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public struct ProcessRunner: Sendable {
    public init() {}

    public func run(
        executableURL: URL,
        arguments: [String],
        log: ImageMounterLogHandler? = nil
    ) async throws -> ProcessResult {
        Logger.log(
            log,
            "Starting process: \(executableURL.path) \(arguments.joined(separator: " "))",
            component: .process
        )

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        Logger.log(
            log,
            "Process exit: \(process.terminationStatus)",
            component: .process
        )

        return ProcessResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}
