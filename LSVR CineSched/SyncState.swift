// SyncState.swift
// The sync state shown beside the project title (#14, story of #1): whether this copy of
// an iCloud Drive project is up to date, uploading, downloading, waiting for network, or
// just resolved a conflict. The mapping is a pure function of the document URL's
// ubiquitous resource values, the network, and the conflict policy's flag (#15), so every
// state and every precedence choice has a test (`SyncStateTests`). Reading the resource
// values, watching the metadata query, monitoring the network and drawing the indicator
// are the platform scenes' (#12) and are wired on top of this.
//
// Precedence, top wins:
//   1. A file outside iCloud (`isUbiquitousItem == false`) has no sync state: nil, and the
//      indicator draws nothing. A local file and an untitled window both land here.
//   2. `conflictResolved`: the policy just kept one version over another. The notice is
//      the point of the state, so it outranks the transfer that the resolution's own
//      save starts; the caller clears the flag on the next edit (or when the notice is
//      acted on), which is what retires the state.
//   3. No network: waiting for network, whatever the resource values say. A transfer
//      cannot be in progress offline (a stale `isUploading` is not to be believed), and
//      an up-to-date file is still one that cannot learn about edits made elsewhere,
//      which is what the acceptance test asks the indicator to show in airplane mode.
//   4. A transfer in progress: uploading before downloading, since the upload is the
//      user's own edit leaving the device, which is what they are watching for.
//   5. A transfer owed but not started: not uploaded means uploading (iCloud starts it
//      by itself; an upload error only means it retries), a downloading status other than
//      current means downloading (a newer version exists elsewhere).
//   6. Otherwise up to date.
//
// The two error keys are carried in the snapshot for the wiring to surface as detail
// (a tooltip, say) and do not change the state: the owed direction is still the truth.
// `hasUnresolvedConflicts` is likewise carried, not displayed: it is what tells the
// wiring to run `ConflictPolicy`, and nothing is "resolved" until it has.

import Foundation

// MARK: - Sync state

nonisolated enum SyncState: String, CaseIterable, Equatable {
    case upToDate
    case uploading
    case downloading
    case waitingForNetwork
    case conflictResolved

    /// The label for the indicator, in the glossary's words.
    @MainActor var localizedTitle: String {
        switch self {
        case .upToDate:          return L("Up to Date")
        case .uploading:         return L("Uploading")
        case .downloading:       return L("Downloading")
        case .waitingForNetwork: return L("Waiting for Network")
        case .conflictResolved:  return L("Conflict Resolved")
        }
    }

    // MARK: Derivation

    /// The state for `snapshot`, or nil for a file outside iCloud. `networkReachable` is
    /// the platform's reachability (a path monitor on iOS and visionOS); pass `true` when
    /// nothing monitors it and the resource values alone decide. `conflictResolved` is
    /// the session flag `ConflictPolicy`'s notice sets and the next edit clears (#15).
    static func derive(
        from snapshot: UbiquitousResourceSnapshot,
        networkReachable: Bool = true,
        conflictResolved: Bool = false
    ) -> SyncState? {
        guard snapshot.isUbiquitousItem else { return nil }
        if conflictResolved       { return .conflictResolved }
        if !networkReachable      { return .waitingForNetwork }
        if snapshot.isUploading   { return .uploading }
        if snapshot.isDownloading { return .downloading }
        if !snapshot.isUploaded   { return .uploading }
        if snapshot.downloadingStatus != .current { return .downloading }
        return .upToDate
    }
}

// MARK: - Resource snapshot

/// The ubiquitous resource values of a document URL, as plain values so a test needs no
/// file. One field per `URLResourceKey` the mapping reads, in the key's own terms; the
/// `URLResourceValues` initializer is the one-liner for the wiring. A value the system did
/// not report (a key not requested, or not applicable) means no evidence of pending work,
/// so the defaults describe an item that is up to date.
nonisolated struct UbiquitousResourceSnapshot: Equatable {

    /// `ubiquitousItemDownloadingStatusKey`: `current` is up to date, `downloaded` has a
    /// local copy but a newer version to fetch, `notDownloaded` has no local copy.
    enum DownloadingStatus: String, Equatable {
        case current
        case downloaded
        case notDownloaded

        init?(_ status: URLUbiquitousItemDownloadingStatus) {
            switch status {
            case .current:       self = .current
            case .downloaded:    self = .downloaded
            case .notDownloaded: self = .notDownloaded
            default:             return nil
            }
        }
    }

    /// `isUbiquitousItemKey`: the file lives in an iCloud container.
    var isUbiquitousItem: Bool
    /// `ubiquitousItemIsUploadingKey`.
    var isUploading:            Bool = false
    /// `ubiquitousItemIsUploadedKey`: every local change has reached iCloud.
    var isUploaded:             Bool = true
    /// `ubiquitousItemIsDownloadingKey`.
    var isDownloading:          Bool = false
    /// `ubiquitousItemDownloadingStatusKey`.
    var downloadingStatus:      DownloadingStatus = .current
    /// `ubiquitousItemHasUnresolvedConflictsKey`: other versions exist that nobody has
    /// resolved yet. Not a displayed state; what triggers the conflict policy.
    var hasUnresolvedConflicts: Bool = false
    /// `ubiquitousItemUploadingErrorKey` is set.
    var hasUploadingError:      Bool = false
    /// `ubiquitousItemDownloadingErrorKey` is set.
    var hasDownloadingError:    Bool = false

    init(
        isUbiquitousItem:       Bool,
        isUploading:            Bool = false,
        isUploaded:             Bool = true,
        isDownloading:          Bool = false,
        downloadingStatus:      DownloadingStatus = .current,
        hasUnresolvedConflicts: Bool = false,
        hasUploadingError:      Bool = false,
        hasDownloadingError:    Bool = false
    ) {
        self.isUbiquitousItem       = isUbiquitousItem
        self.isUploading            = isUploading
        self.isUploaded             = isUploaded
        self.isDownloading          = isDownloading
        self.downloadingStatus      = downloadingStatus
        self.hasUnresolvedConflicts = hasUnresolvedConflicts
        self.hasUploadingError      = hasUploadingError
        self.hasDownloadingError    = hasDownloadingError
    }

    /// The keys to request from `URL.resourceValues(forKeys:)` (or to observe through a
    /// metadata query) so that `init(_:)` sees every field it reads.
    static let resourceKeys: Set<URLResourceKey> = [
        .isUbiquitousItemKey,
        .ubiquitousItemIsUploadingKey,
        .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemHasUnresolvedConflictsKey,
        .ubiquitousItemUploadingErrorKey,
        .ubiquitousItemDownloadingErrorKey,
    ]

    /// The snapshot of a URL's resource values, as `url.resourceValues(forKeys:
    /// resourceKeys)` returns them. A missing value falls back to the up-to-date default.
    init(_ values: URLResourceValues) {
        self.init(
            isUbiquitousItem:       values.isUbiquitousItem ?? false,
            isUploading:            values.ubiquitousItemIsUploading ?? false,
            isUploaded:             values.ubiquitousItemIsUploaded ?? true,
            isDownloading:          values.ubiquitousItemIsDownloading ?? false,
            downloadingStatus:      values.ubiquitousItemDownloadingStatus.flatMap(DownloadingStatus.init) ?? .current,
            hasUnresolvedConflicts: values.ubiquitousItemHasUnresolvedConflicts ?? false,
            hasUploadingError:      values.ubiquitousItemUploadingError != nil,
            hasDownloadingError:    values.ubiquitousItemDownloadingError != nil
        )
    }
}
