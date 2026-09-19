// CineSchedFolder.swift
// The CineSched folder: the iCloud Documents container the iOS, iPadOS and visionOS
// builds own (#12, ADR 0006), which iCloud Drive shows as "CineSched" on every device
// signed into the account. Those builds reach it through their entitlement (the document
// browser and the launch screen open there by default). The Mac has no iCloud
// entitlement, on purpose, so it cannot ask `FileManager` for the container; what it can
// do is derive where iCloud Drive keeps the folder on disk and point its Open and Save
// panels there (`MacAppDelegate`). Pure: the path is a function of the home directory.

import Foundation

nonisolated enum CineSchedFolder {

    /// The container identifier, exactly as in Config/CineSched-iOS.entitlements and the
    /// `NSUbiquitousContainers` entry of Config/Info.plist.
    static let containerIdentifier = "iCloud.com.lsvr.LSVR-CineSched"

    /// The user-visible folder name (`NSUbiquitousContainerName`).
    static let displayName = "CineSched"

    /// Where iCloud Drive materializes the container's Documents folder under `home` on a
    /// Mac: `~/Library/Mobile Documents/<identifier with "~" for ".">/Documents`. Exists
    /// only once the account has the container, i.e. after the first project was saved
    /// there from an iPad, iPhone or Vision Pro and iCloud Drive synced it down.
    static func macDocumentsURL(home: URL) -> URL {
        let containerFolder = containerIdentifier.replacingOccurrences(of: ".", with: "~")
        return home
            .appending(path: "Library/Mobile Documents", directoryHint: .isDirectory)
            .appending(path: containerFolder, directoryHint: .isDirectory)
            .appending(path: "Documents", directoryHint: .isDirectory)
    }

    /// The account's real home directory. In a sandboxed app `NSHomeDirectory()` and
    /// `FileManager.homeDirectoryForCurrentUser` are the app's container, so the answer
    /// comes from the password database instead.
    static var realHomeDirectory: URL? {
        guard let record = getpwuid(getuid()), let directory = record.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }
}
