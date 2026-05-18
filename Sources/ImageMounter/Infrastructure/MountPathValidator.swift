//
//  MountPathValidator.swift
//  ImageMounter
//
//  Created by Saad Tahir on 15/05/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

enum MountPathValidator {

    static func validateWorkspace(_ url: URL) throws {
        let fm = FileManager.default

        guard !url.path.isEmpty else {
            throw MountError.mountFailed(
                reason: "[WorkspaceValidation] Empty path is not allowed"
            )
        }

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            guard isDir.boolValue else {
                throw MountError.mountFailed(
                    reason: "[WorkspaceValidation] workspaceDirectory is not a directory: \(url.path)"
                )
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }

        guard fm.isWritableFile(atPath: url.path) else {
            throw MountError.mountFailed(
                reason: "[WorkspaceValidation] workspaceDirectory is not writable: \(url.path)"
            )
        }
    }

    static func validateMountPoint(_ url: URL) throws {
        let fm = FileManager.default

        guard !url.path.isEmpty else {
            throw MountError.mountFailed(
                reason: "[MountPointValidation] Empty path is not allowed"
            )
        }

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            guard isDir.boolValue else {
                throw MountError.mountFailed(
                    reason: "[MountPointValidation] mountPoint is not a directory: \(url.path)"
                )
            }

            let contents = try fm.contentsOfDirectory(atPath: url.path)
            guard contents.isEmpty else {
                throw MountError.mountFailed(
                    reason: "[MountPointValidation] Directory must be empty to be used as mount point: \(url.path)"
                )
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }

        guard fm.isWritableFile(atPath: url.path) else {
            throw MountError.mountFailed(
                reason: "[MountPointValidation] Not writable: \(url.path)"
            )
        }
    }
}

