//
//  SplitRawMergerTests.swift
//  FIMountKit
//
//  Created by Saad Tahir on 17/08/2026.
//   -- GitHub : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation
import Testing
@testable import FIMountKit

private enum SplitRawTestSupport {
    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("split-raw-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func writePart(
        in directory: URL,
        baseName: String,
        index: Int,
        marker: UInt8
    ) throws {
        let fileName = "\(baseName).\(String(format: "%03d", index))"
        let data = Data(repeating: marker, count: 4)
        guard FileManager.default.createFile(
            atPath: directory.appendingPathComponent(fileName).path,
            contents: data
        ) else {
            throw NSError(domain: "SplitRawMergerTests", code: 1)
        }
    }

    static func mergedData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
}

@Test func splitRawMerger_merges001StartSet() throws {
    let directory = try SplitRawTestSupport.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 1, marker: 0xA1)
    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 2, marker: 0xA2)

    let output = directory.appendingPathComponent("merged.raw")
    let handle = try SplitRawMerger().merge(
        directory.appendingPathComponent("foo.001"),
        output: output,
        log: nil
    )

    let merged = try SplitRawTestSupport.mergedData(at: handle.mergedFile)
    #expect(merged.count == 8)
    #expect(merged.starts(with: Data(repeating: 0xA1, count: 4)))
    #expect(merged.suffix(4) == Data(repeating: 0xA2, count: 4))
}

@Test func splitRawMerger_merges000StartSet() throws {
    let directory = try SplitRawTestSupport.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 0, marker: 0xB0)
    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 1, marker: 0xB1)

    let output = directory.appendingPathComponent("merged.raw")
    let handle = try SplitRawMerger().merge(
        directory.appendingPathComponent("foo.000"),
        output: output,
        log: nil
    )

    let merged = try SplitRawTestSupport.mergedData(at: handle.mergedFile)
    #expect(merged.count == 8)
    #expect(merged.starts(with: Data(repeating: 0xB0, count: 4)))
    #expect(merged.suffix(4) == Data(repeating: 0xB1, count: 4))
}

@Test func splitRawMerger_startsAt001When000SiblingExists() throws {
    let directory = try SplitRawTestSupport.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 0, marker: 0xC0)
    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 1, marker: 0xC1)
    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 2, marker: 0xC2)

    let output = directory.appendingPathComponent("merged.raw")
    let handle = try SplitRawMerger().merge(
        directory.appendingPathComponent("foo.001"),
        output: output,
        log: nil
    )

    let merged = try SplitRawTestSupport.mergedData(at: handle.mergedFile)
    #expect(merged.count == 8)
    #expect(merged.starts(with: Data(repeating: 0xC1, count: 4)))
    #expect(merged.suffix(4) == Data(repeating: 0xC2, count: 4))
}

@Test func splitRawMerger_mergesSinglePartSet() throws {
    let directory = try SplitRawTestSupport.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 1, marker: 0xD1)

    let original = directory.appendingPathComponent("foo.001")
    let output = directory.appendingPathComponent("merged.raw")
    let handle = try SplitRawMerger().merge(original, output: output, log: nil)

    #expect(handle.mergedFile.path == original.path)
    #expect(handle.isTemporary == false)
    #expect(try SplitRawTestSupport.mergedData(at: original) == Data(repeating: 0xD1, count: 4))
    #expect(FileManager.default.fileExists(atPath: output.path) == false)
}

@Test func splitRawMerger_rejectsGap() throws {
    let directory = try SplitRawTestSupport.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 0, marker: 0xE0)
    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 2, marker: 0xE2)

    #expect(throws: MountError.self) {
        _ = try SplitRawMerger().merge(directory.appendingPathComponent("foo.000"), log: nil)
    }
}

@Test func splitRawMerger_rejectsInvalidStartSegment() throws {
    let directory = try SplitRawTestSupport.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 2, marker: 0xF2)

    #expect(throws: MountError.self) {
        _ = try SplitRawMerger().merge(directory.appendingPathComponent("foo.002"), log: nil)
    }
}

@Test func splitRawMerger_ignoresNonThreeDigitSibling() throws {
    let directory = try SplitRawTestSupport.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 1, marker: 0x11)
    let typoPath = directory.appendingPathComponent("foo.02")
    guard FileManager.default.createFile(atPath: typoPath.path, contents: Data(repeating: 0x99, count: 4)) else {
        throw NSError(domain: "SplitRawMergerTests", code: 2)
    }

    let output = directory.appendingPathComponent("merged.raw")
    let handle = try SplitRawMerger().merge(
        directory.appendingPathComponent("foo.001"),
        output: output,
        log: nil
    )

    let merged = try SplitRawTestSupport.mergedData(at: handle.mergedFile)
    #expect(merged == Data(repeating: 0x11, count: 4))
}

@Test func splitRawMerger_rejects1000When999IsLastSupportedSegment() throws {
    let directory = try SplitRawTestSupport.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 999, marker: 0x99)
    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 1000, marker: 0xAA)

    #expect(throws: MountError.self) {
        _ = try SplitRawMerger().merge(directory.appendingPathComponent("foo.999"), log: nil)
    }
}

@Test func splitRawMerger_throwsInsufficientSpaceBeforeWrite() throws {
    let directory = try SplitRawTestSupport.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 0, marker: 0x01)
    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 1, marker: 0x02)

    let output = directory.appendingPathComponent("merged.raw")
    let merger = SplitRawMerger(availableBytes: { _ in 0 })

    #expect(throws: MountError.insufficientSpace(required: 8, available: 0)) {
        _ = try merger.merge(
            directory.appendingPathComponent("foo.000"),
            output: output,
            log: nil
        )
    }
    #expect(FileManager.default.fileExists(atPath: output.path) == false)
}

@Test func splitRawMerger_mergesWhenAvailableEqualsTotalSize() throws {
    let directory = try SplitRawTestSupport.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 0, marker: 0x01)
    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 1, marker: 0x02)

    let output = directory.appendingPathComponent("merged.raw")
    let merger = SplitRawMerger(availableBytes: { _ in 8 })
    let handle = try merger.merge(
        directory.appendingPathComponent("foo.000"),
        output: output,
        log: nil
    )

    let merged = try SplitRawTestSupport.mergedData(at: handle.mergedFile)
    #expect(merged.count == 8)
    #expect(FileManager.default.fileExists(atPath: output.path))
}

@Test func splitRawMerger_reusesCompleteExistingOutput() throws {
    let directory = try SplitRawTestSupport.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 0, marker: 0x01)
    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 1, marker: 0x02)

    let output = directory.appendingPathComponent("merged.raw")
    _ = try SplitRawMerger().merge(
        directory.appendingPathComponent("foo.000"),
        output: output,
        log: nil
    )

    try Data(repeating: 0xEE, count: 8).write(to: output)
    let handle = try SplitRawMerger().merge(
        directory.appendingPathComponent("foo.000"),
        output: output,
        log: nil
    )

    #expect(handle.mergedFile.path == output.path)
    #expect(try SplitRawTestSupport.mergedData(at: output) == Data(repeating: 0xEE, count: 8))
}

@Test func splitRawImageMounter_singlePartMountFailure_doesNotDeleteOriginal() async throws {
    let directory = try SplitRawTestSupport.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try SplitRawTestSupport.writePart(in: directory, baseName: "foo", index: 0, marker: 0xD1)
    let original = directory.appendingPathComponent("foo.000")

    let workspace = directory.appendingPathComponent("workspace", isDirectory: true)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

    struct ThrowingImageMounter: ImageMounter {
        let supportedTypes: [ImageType] = [.raw]
        func mount(url: URL, options: MountOptions, log: ImageMounterLogHandler?) async throws -> MountResult {
            throw MountError.mountFailed(reason: "forced attach failure")
        }
        func unmount(_ result: MountResult, log: ImageMounterLogHandler?) async throws {}
    }

    let mounter = SplitRawImageMounter(rawMounter: ThrowingImageMounter())
    let options = MountOptions(workspaceDirectory: workspace)

    await #expect(throws: MountError.self) {
        _ = try await mounter.mount(url: original, options: options, log: nil)
    }

    #expect(FileManager.default.fileExists(atPath: original.path))
    #expect(try SplitRawTestSupport.mergedData(at: original) == Data(repeating: 0xD1, count: 4))

    let leftovers = try FileManager.default.contentsOfDirectory(
        at: workspace,
        includingPropertiesForKeys: nil
    )
    #expect(leftovers.filter { $0.pathExtension == "raw" }.isEmpty)
}
