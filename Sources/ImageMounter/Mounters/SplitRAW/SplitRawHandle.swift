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
    private let availableBytes: (URL) throws -> Int64

    public init(
        fileManager: FileManager = .default,
        chunkSize: Int = 4 * 1024 * 1024,
        availableBytes: ((URL) throws -> Int64)? = nil
    ) {
        self.fileManager = fileManager
        self.chunkSize = chunkSize
        self.availableBytes = availableBytes ?? Self.volumeAvailableBytes
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

        if parts.count == 1 {
            let unusedOutput = output.map(\.path) ?? "nil"
            Logger.log(
                log,
                "Single-part split RAW: using original file (no merge). output path unused: \(unusedOutput)",
                component: .splitRawMerger
            )
            return SplitRawHandle(mergedFile: firstPart, isTemporary: false)
        }

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
            let parent = mergedURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )

            let totalSize = try totalSize(of: parts)

            if fileManager.fileExists(atPath: mergedURL.path) {
                let existingSize = (try fileManager.attributesOfItem(atPath: mergedURL.path)[.size] as? Int64) ?? 0
                if existingSize == totalSize {
                    Logger.log(log, "Reusing existing merged file: \(mergedURL.path)", component: .splitRawMerger)
                    return SplitRawHandle(mergedFile: mergedURL, isTemporary: isTemporary)
                }
                Logger.log(log, "Removing incomplete merged file: \(mergedURL.path)", component: .splitRawMerger)
                try fileManager.removeItem(at: mergedURL)
            }

            // dest volume only — does not check the evidence volume; case-vs-source mismatch can still fail on read.
            let available = try availableBytes(parent)
            if available < totalSize {
                throw MountError.insufficientSpace(required: totalSize, available: available)
            }

            Logger.log(log, "Preallocating merged file size: \(totalSize) bytes", component: .splitRawMerger)

            guard fileManager.createFile(atPath: mergedURL.path, contents: nil) else {
                throw MountError.mountFailed(reason: "Failed to create merged file at \(mergedURL.path)")
            }
            created = true

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
                do {
                    let readHandle = try FileHandle(forReadingFrom: part)
                    defer { try? readHandle.close() }

                    while true {
                        if Task.isCancelled {
                            throw CancellationError()
                        }

                        var reachedEOF = false
                        autoreleasepool {
                            // per-chunk drain required; wrapping the whole part reintroduces unbounded RAM.
                            do {
                                let data = try readHandle.read(upToCount: chunkSize) ?? Data()
                                if data.isEmpty {
                                    reachedEOF = true
                                    return
                                }

                                try writeHandle.write(contentsOf: data)
                                written += Int64(data.count)

                                if written >= nextLog {
                                    Logger.log(log, "Merged \(written / (1024 * 1024)) MB...", component: .splitRawMerger)
                                    nextLog += 50 * 1024 * 1024
                                }
                            } catch {
                                partError = error
                            }
                        }
                        if reachedEOF { break }
                        if let partError { throw partError }
                    }
                } catch {
                    partError = error
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

    /// Bytes that would be copied onto the destination volume for this split set.
    /// `nil` when no copy runs (not a `.000`/`.001` start, or a single-part set).
    public func requiredCopySize(for firstPart: URL) throws -> Int64? {
        let ext = firstPart.pathExtension
        guard ext.count == 3, let startIndex = Int(ext), startIndex == 0 || startIndex == 1 else {
            return nil
        }

        let directory = firstPart.deletingLastPathComponent()
        let baseName = firstPart.deletingPathExtension().lastPathComponent
        let parts = try discoverParts(in: directory, baseName: baseName, startIndex: startIndex)
        guard parts.count > 1 else { return nil }
        return try totalSize(of: parts)
    }

    public func availableBytes(onVolumeContaining url: URL) throws -> Int64 {
        try Self.volumeAvailableBytes(at: url)
    }

    private func totalSize(of parts: [URL]) throws -> Int64 {
        try parts.reduce(0 as Int64) { acc, url in
            let attrs = try fileManager.attributesOfItem(atPath: url.path)
            return acc + (attrs[.size] as? Int64 ?? 0)
        }
    }

    private static func volumeAvailableBytes(at url: URL) throws -> Int64 {
        var stats = statfs()
        let result = url.path.withCString { statfs($0, &stats) }
        guard result == 0 else {
            throw MountError.mountFailed(reason: "Failed to inspect free space at \(url.path)")
        }
        return Int64(stats.f_bavail) * Int64(stats.f_bsize)
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
