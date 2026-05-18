//
//  ProcessExecutor.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

public protocol ProcessExecuting {
    func run(_ command: String, log: ImageMounterLogHandler?) async throws -> ProcessResult
}

public struct ProcessExecutor: ProcessExecuting, Sendable {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func run(_ command: String, log: ImageMounterLogHandler? = nil) async throws -> ProcessResult {
        let parts = try splitCommand(command)
        guard let executable = parts.first, !executable.isEmpty else {
            throw MountError.detectionFailed
        }

        return try await run(executable: executable, arguments: Array(parts.dropFirst()), log: log)
    }

    public func run(
        executable: String,
        arguments: [String],
        throwOnNonZeroExit: Bool = true,
        log: ImageMounterLogHandler? = nil
    ) async throws -> ProcessResult {
        let resolved = executable
        Logger.log(log, "Resolved path: \(resolved)", component: .process)

        if resolved.hasPrefix("/") {
            Logger.log(
                log,
                "Running: \(resolved) \(arguments.joined(separator: " "))",
                component: .process
            )
        } else {
            Logger.log(
                log,
                "Running via env: \(resolved) \(arguments.joined(separator: " "))",
                component: .process
            )
        }

        let executableURL: URL
        let args: [String]

        if resolved.hasPrefix("/") {
            executableURL = URL(fileURLWithPath: resolved)
            args = arguments
        } else {
            executableURL = URL(fileURLWithPath: "/usr/bin/env")
            args = [resolved] + arguments
        }

        let result = try await runner.run(executableURL: executableURL, arguments: args, log: log)

        guard !throwOnNonZeroExit || result.exitCode == 0 else {
            let maxLen = 8_000
            let isStdoutTruncated = result.stdout.count > maxLen
            let isStderrTruncated = result.stderr.count > maxLen

            let stdout = String(result.stdout.prefix(maxLen)) + (isStdoutTruncated ? "…[truncated]" : "")
            let stderr = String(result.stderr.prefix(maxLen)) + (isStderrTruncated ? "…[truncated]" : "")

            Logger.log(
                log,
                """
                Command failed: \(resolved)
                exit=\(result.exitCode)
                stdout=\(stdout)
                stderr=\(stderr)
                """,
                level: .error,
                component: .process
            )

            let reason =
                """
                Command failed (exit \(result.exitCode)): \(resolved) \(arguments.joined(separator: " "))
                stdout: \(stdout)
                stderr: \(stderr)
                """
            throw MountError.mountFailed(reason: reason)
        }

        return result
    }

    private func splitCommand(_ command: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaping = false

        for ch in command {
            if isEscaping {
                current.append(ch)
                isEscaping = false
                continue
            }

            if ch == "\\" && !inSingleQuote {
                isEscaping = true
                continue
            }

            if ch == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }

            if ch == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }

            if ch.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(ch)
        }

        if isEscaping || inSingleQuote || inDoubleQuote {
            throw MountError.detectionFailed
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
