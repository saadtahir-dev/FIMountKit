//
//  ImageMounterTests.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation
import Testing
@testable import FIMountKit

@Test func hdiutil_attachArguments_forceReadOnly() {
    let raw = HDIUtilHelper.attachArguments(
        imagePath: "/tmp/disk.dd",
        extra: ["-imagekey", "diskimage-class=CRawDiskImage"]
    )
    let dmg = HDIUtilHelper.attachArguments(imagePath: "/tmp/disk.dmg")
    let withMountPoint = HDIUtilHelper.attachArguments(
        imagePath: "/tmp/disk.dmg",
        mountPoint: URL(fileURLWithPath: "/Volumes/Evidence")
    )

    for arguments in [raw, dmg, withMountPoint] {
        #expect(arguments.contains("-readonly"))
        #expect(!arguments.contains("-shadow"))
        #expect(!arguments.contains("-readwrite"))
        #expect(arguments.first == "attach")
    }

    #expect(withMountPoint.contains("-mountpoint"))
    #expect(withMountPoint.contains("/Volumes/Evidence"))
}

@Test func imageFormatDetector_extensionMapping() throws {
    let detector = ImageFormatDetector()

    #expect(try detector.detect(URL(fileURLWithPath: "/tmp/foo.dmg"), log: nil) == .dmg)
    #expect(try detector.detect(URL(fileURLWithPath: "/tmp/foo.sparseimage"), log: nil) == .sparseImage)
    #expect(try detector.detect(URL(fileURLWithPath: "/tmp/foo.sparsebundle"), log: nil) == .sparseBundle)
    #expect(try detector.detect(URL(fileURLWithPath: "/tmp/foo.raw"), log: nil) == .raw)
    #expect(try detector.detect(URL(fileURLWithPath: "/tmp/foo.dd"), log: nil) == .raw)
    #expect(try detector.detect(URL(fileURLWithPath: "/tmp/foo.e01"), log: nil) == .ewf)
    #expect(try detector.detect(URL(fileURLWithPath: "/tmp/foo.ex01"), log: nil) == .ewf)
    #expect(try detector.detect(URL(fileURLWithPath: "/tmp/foo.s01"), log: nil) == .ewf)
    #expect(try detector.detect(URL(fileURLWithPath: "/tmp/foo.001"), log: nil) == .splitRaw)
    #expect(try detector.detect(URL(fileURLWithPath: "/tmp/foo.000"), log: nil) == .splitRaw)
    #expect(throws: MountError.detectionFailed) { try detector.detect(URL(fileURLWithPath: "/tmp/foo.unknownext"), log: nil) }
}

@Test func service_selectsMounterByDetectedType() async throws {
    final class StubDetector: ImageFormatDetecting {
        let type: ImageType
        init(type: ImageType) { self.type = type }
        func detect(_ url: URL, log: ImageMounterLogHandler? = nil) throws -> ImageType { type }
    }

    final class RecordingMounter: ImageMounter, @unchecked Sendable {
        let supportedTypes: [ImageType]
        private(set) var mountCalls: [URL] = []

        init(supportedTypes: [ImageType]) {
            self.supportedTypes = supportedTypes
        }

        func mount(url: URL, options: MountOptions, log: ImageMounterLogHandler? = nil) async throws -> MountResult {
            mountCalls.append(url)
            return MountResult(
                sourceURL: url,
                type: supportedTypes[0],
                deviceIdentifiers: [],
                mountPointURLs: [],
                temporaryResources: [],
                metadata: [:]
            )
        }

        func unmount(_ result: MountResult, log: ImageMounterLogHandler? = nil) async throws {}
    }

    let targetURL = URL(fileURLWithPath: "/tmp/foo.e01")
    let ewfMounter = RecordingMounter(supportedTypes: [.ewf])
    let rawMounter = RecordingMounter(supportedTypes: [.raw])

    let service = ImageMountingService(
        detector: StubDetector(type: .ewf),
        mounters: [rawMounter, ewfMounter]
    )

    _ = try await service.mount(url: targetURL)

    #expect(rawMounter.mountCalls.isEmpty)
    #expect(ewfMounter.mountCalls == [targetURL])
}

@Test func service_throwsUnsupportedTypeWhenNoMounterMatches() async {
    final class StubDetector: ImageFormatDetecting {
        let type: ImageType
        init(type: ImageType) { self.type = type }
        func detect(_ url: URL, log: ImageMounterLogHandler? = nil) throws -> ImageType { type }
    }

    struct NoopMounter: ImageMounter {
        let supportedTypes: [ImageType]
        func mount(url: URL, options: MountOptions, log: ImageMounterLogHandler? = nil) async throws -> MountResult {
            throw MountError.mountFailed(reason: "should not be called")
        }
        func unmount(_ result: MountResult, log: ImageMounterLogHandler? = nil) async throws {}
    }

    let service = ImageMountingService(
        detector: StubDetector(type: .ewf),
        mounters: [NoopMounter(supportedTypes: [.raw])]
    )

    await #expect(throws: MountError.unsupportedType) {
        _ = try await service.mount(url: URL(fileURLWithPath: "/tmp/foo.e01"))
    }
}
