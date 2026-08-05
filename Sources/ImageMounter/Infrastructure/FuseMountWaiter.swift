//
//  FuseMountWaiter.swift
//  FIMountKit
//
//  Created by Saad Tahir on 05/08/2026.
//   -- GitHub   : https://github.com/saadtahir-dev
//   -- LinkedIn : https://www.linkedin.com/in/saadtahir-dev
//

import Foundation

///  Polls for the raw file a FUSE mount tool (ewfmount/vhdimount/vmdkmount)
///  is expected to expose once it has finished mounting.
///
///  The mount tools return control to the caller (process exit 0) as soon as
///  they've forked/daemonized the FUSE filesystem, not once macFUSE has
///  finished registering the mount and the virtual file is actually visible
///  through the mount point. That registration is asynchronous and can take
///  anywhere from under 100ms to a couple of seconds depending on system
///  load. A single immediate `fileExists` check right after the process
///  returns is a race — it can and does lose, reporting a mount failure for
///  a mount that succeeds a moment later.
public enum FuseMountWaiter {
    /// Polls `fileManager` for `path` to exist, checking every `interval`
    /// up to `timeout` total. Returns as soon as the file appears; does not
    /// wait out the full timeout on success.
    public static func waitForFile(
        at path: String,
        fileManager: FileManager,
        timeout: TimeInterval = 5.0,
        interval: TimeInterval = 0.15
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if fileManager.fileExists(atPath: path) {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }

        // One last check right at the deadline, in case the file appeared
        // between the last sleep and now.
        return fileManager.fileExists(atPath: path)
    }
}
