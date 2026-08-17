//
//  SplitRawHandle.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation
import Darwin

public struct SplitRawHandle: Sendable, Equatable {
    public let mergedFile: URL
    public let isTemporary: Bool

    public init(mergedFile: URL, isTemporary: Bool) {
        self.mergedFile = mergedFile
        self.isTemporary = isTemporary
    }
}

public final class SplitRawMerger: @unchecked Sendable {
    private let fileManager: FileManager
    private let chunkSize: Int

    public init(fileManager: FileManager = .default, chunkSize: Int = 4 * 1024 * 1024) {
        self.fileManager = fileManager
        self.chunkSize = chunkSize
    }

    public func merge(_ firstPart: URL, output: URL? = nil, log: ImageMounterLogHandler? = nil) throws -> SplitRawHandle {
        Logger.log(log, "Starting merge for first part: \(firstPart.path)", component: .splitRawMerger)
        let ext = firstPart.pathExtension
        guard ext.count == 3, let startIndex = Int(ext), startIndex == 0 || startIndex == 1 else {
            Logger.log(
                log,
                "Split RAW must start at .000 or .001 (got .\(ext))",
                level: .error,
                component: .splitRawMerger
            )
            throw MountError.mountFailed(reason: "Split RAW must start at .000 or .001 (got .\(ext))")
        }

        let directory = firstPart.deletingLastPathComponent()
        let baseName = firstPart.deletingPathExtension().lastPathComponent

        let parts = try discoverParts(in: directory, baseName: baseName, startIndex: startIndex)
        Logger.log(
            log,
            "Discovered \(parts.count) split parts starting at .\(String(format: "%03d", startIndex))",
            component: .splitRawMerger
        )

        let mergedURL: URL
        let isTemporary: Bool
        if let output {
            mergedURL = output
            isTemporary = false
        } else {
            let dir = URL(fileURLWithPath: "/tmp/image-mounter", isDirectory: true)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            mergedURL = dir.appendingPathComponent("\(UUID().uuidString).raw", isDirectory: false)
            isTemporary = true
        }
        Logger.log(log, "Merging into: \(mergedURL.path) (temporary=\(isTemporary))", component: .splitRawMerger)

        var created = false
        do {
            if fileManager.fileExists(atPath: mergedURL.path) {
                throw MountError.mountFailed(reason: "Output file already exists at \(mergedURL.path)")
            }

            try fileManager.createDirectory(
                at: mergedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            guard fileManager.createFile(atPath: mergedURL.path, contents: nil) else {
                throw MountError.mountFailed(reason: "Failed to create merged file at \(mergedURL.path)")
            }
            created = true

            let totalSize = try parts.reduce(0 as Int64) { acc, url in
                let attrs = try fileManager.attributesOfItem(atPath: url.path)
                return acc + (attrs[.size] as? Int64 ?? 0)
            }
            Logger.log(log, "Preallocating merged file size: \(totalSize) bytes", component: .splitRawMerger)

            let fd = open(mergedURL.path, O_RDWR | O_CLOEXEC)
            if fd >= 0 {
                defer { close(fd) }
                if ftruncate(fd, totalSize) != 0 {
                    let err = String(cString: strerror(errno))
                    Logger.log(log, "ftruncate(\(totalSize)) failed: \(err)", component: .splitRawMerger)
                }
            }

            let writeHandle = try FileHandle(forWritingTo: mergedURL)
            defer { try? writeHandle.close() }

            var written: Int64 = 0
            var nextLog: Int64 = 50 * 1024 * 1024

            for part in parts {
                guard fileManager.fileExists(atPath: part.path) else {
                    throw MountError.mountFailed(reason: "Missing split part: \(part.lastPathComponent)")
                }
            }

            for part in parts {
                if Task.isCancelled {
                    throw CancellationError()
                }

                var partError: Error?
                autoreleasepool {
                    do {
                        let readHandle = try FileHandle(forReadingFrom: part)
                        defer { try? readHandle.close() }

                        while true {
                            if Task.isCancelled {
                                throw CancellationError()
                            }

                            let data = try readHandle.read(upToCount: chunkSize) ?? Data()
                            if data.isEmpty { break }

                            try writeHandle.write(contentsOf: data)
                            written += Int64(data.count)

                            if written >= nextLog {
                                Logger.log(log, "Merged \(written / (1024 * 1024)) MB...", component: .splitRawMerger)
                                nextLog += 50 * 1024 * 1024
                            }
                        }
                    } catch {
                        partError = error
                    }
                }
                if let partError {
                    throw partError
                }
            }

            try writeHandle.synchronize()
            let writeFD = writeHandle.fileDescriptor
            _ = fsync(writeFD)
            Logger.log(log, "Merge complete: \(mergedURL.path)", component: .splitRawMerger)
            return SplitRawHandle(mergedFile: mergedURL, isTemporary: isTemporary)
        } catch {
            Logger.log(log, "Merge failed: \(error)", level: .error, component: .splitRawMerger)
            if created {
                try? fileManager.removeItem(at: mergedURL)
            }
            throw error
        }
    }

    private func discoverParts(in directory: URL, baseName: String, startIndex: Int) throws -> [URL] {
        let entries = try fileManager.contentsOfDirectory(atPath: directory.path)

        var numbers: [Int] = []
        for name in entries {
            guard name.hasPrefix("\(baseName).") else { continue }
            let ext = String(name.dropFirst(baseName.count + 1))
            guard ext.count == 3, let n = Int(ext) else { continue }
            numbers.append(n)
        }

        let available = Set(numbers)
        guard available.contains(startIndex) else {
            let selected = String(format: "%03d", startIndex)
            throw MountError.mountFailed(reason: "Missing selected split part: \(baseName).\(selected)")
        }

        let candidates = available.filter { $0 >= startIndex }.sorted()
        for (offset, n) in candidates.enumerated() {
            if n != startIndex + offset {
                throw MountError.mountFailed(reason: "Split RAW parts are not contiguous (gap detected)")
            }
        }

        if candidates.last == 999 {
            let nextSegment = "\(baseName).1000"
            if entries.contains(nextSegment) {
                // ponytail: TODO 4-digit suffix support if needed
                throw MountError.mountFailed(reason: "Split RAW exceeds 3-digit segment limit (.1000 present)")
            }
        }

        return candidates.map { n in
            let ext = String(format: "%03d", n)
            return directory.appendingPathComponent("\(baseName).\(ext)", isDirectory: false)
        }
    }
}
