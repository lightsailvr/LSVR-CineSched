//
//  SyncStateTests.swift
//  LSVR CineSchedTests
//
//  The sync state beside the project title is a pure function of a URL's ubiquitous
//  resource values, the network and the conflict policy's flag (#14). One test per
//  displayed state, one for a file outside iCloud, and one per precedence choice in the
//  header of SyncState.swift, so a change to the order is a deliberate one.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct SyncStateTests {

    private typealias Snapshot = UbiquitousResourceSnapshot

    /// An iCloud file with nothing pending.
    private let settled = Snapshot(isUbiquitousItem: true)

    // MARK: - One per state

    @Test func settledItemIsUpToDate() {
        #expect(SyncState.derive(from: settled) == .upToDate)
    }

    @Test func itemBeingUploadedIsUploading() {
        let snapshot = Snapshot(isUbiquitousItem: true, isUploading: true, isUploaded: false)
        #expect(SyncState.derive(from: snapshot) == .uploading)
    }

    @Test func itemBeingDownloadedIsDownloading() {
        let snapshot = Snapshot(isUbiquitousItem: true, isDownloading: true, downloadingStatus: .downloaded)
        #expect(SyncState.derive(from: snapshot) == .downloading)
    }

    @Test func noNetworkIsWaitingForNetwork() {
        #expect(SyncState.derive(from: settled, networkReachable: false) == .waitingForNetwork)
    }

    @Test func resolvedConflictIsConflictResolved() {
        #expect(SyncState.derive(from: settled, conflictResolved: true) == .conflictResolved)
    }

    // MARK: - Outside iCloud

    /// A local file, or an untitled window, has no indicator at all, whatever else is set.
    @Test func fileOutsideICloudHasNoState() {
        let local = Snapshot(isUbiquitousItem: false, isUploading: true, isUploaded: false, downloadingStatus: .notDownloaded)
        #expect(SyncState.derive(from: local) == nil)
        #expect(SyncState.derive(from: local, networkReachable: false) == nil)
        #expect(SyncState.derive(from: local, conflictResolved: true) == nil)
    }

    // MARK: - Owed transfers

    /// Local changes iCloud has not taken yet show as uploading even before the transfer
    /// starts: iCloud starts it by itself.
    @Test func changesNotYetUploadedAreUploading() {
        let snapshot = Snapshot(isUbiquitousItem: true, isUploaded: false)
        #expect(SyncState.derive(from: snapshot) == .uploading)
    }

    @Test func newerVersionElsewhereIsDownloading() {
        #expect(SyncState.derive(from: Snapshot(isUbiquitousItem: true, downloadingStatus: .downloaded))    == .downloading)
        #expect(SyncState.derive(from: Snapshot(isUbiquitousItem: true, downloadingStatus: .notDownloaded)) == .downloading)
    }

    // MARK: - Precedence

    @Test func resolvedConflictOutranksTheUploadItsSaveStarts() {
        let snapshot = Snapshot(isUbiquitousItem: true, isUploading: true, isUploaded: false)
        #expect(SyncState.derive(from: snapshot, conflictResolved: true) == .conflictResolved)
    }

    /// The system's own flag is what triggers the policy; nothing is resolved yet, so it
    /// changes nothing on its own.
    @Test func unresolvedConflictsAreNotDisplayed() {
        let uploading = Snapshot(isUbiquitousItem: true, isUploading: true, isUploaded: false, hasUnresolvedConflicts: true)
        #expect(SyncState.derive(from: uploading) == .uploading)
        let settledWithConflicts = Snapshot(isUbiquitousItem: true, hasUnresolvedConflicts: true)
        #expect(SyncState.derive(from: settledWithConflicts) == .upToDate)
    }

    @Test func resolvedConflictOutranksTheMissingNetwork() {
        #expect(SyncState.derive(from: settled, networkReachable: false, conflictResolved: true) == .conflictResolved)
    }

    /// Offline, nothing transfers whatever the resource values claim.
    @Test func missingNetworkOutranksEveryTransfer() {
        let uploading   = Snapshot(isUbiquitousItem: true, isUploading: true, isUploaded: false)
        let downloading = Snapshot(isUbiquitousItem: true, isDownloading: true, downloadingStatus: .downloaded)
        let owed        = Snapshot(isUbiquitousItem: true, isUploaded: false, downloadingStatus: .notDownloaded)
        #expect(SyncState.derive(from: uploading,   networkReachable: false) == .waitingForNetwork)
        #expect(SyncState.derive(from: downloading, networkReachable: false) == .waitingForNetwork)
        #expect(SyncState.derive(from: owed,        networkReachable: false) == .waitingForNetwork)
    }

    @Test func uploadInProgressOutranksDownload() {
        let both = Snapshot(isUbiquitousItem: true, isUploading: true, isUploaded: false, isDownloading: true, downloadingStatus: .downloaded)
        #expect(SyncState.derive(from: both) == .uploading)
        let downloadingWithOwedUpload = Snapshot(isUbiquitousItem: true, isUploaded: false, isDownloading: true)
        #expect(SyncState.derive(from: downloadingWithOwedUpload) == .downloading)
    }

    @Test func owedUploadOutranksOwedDownload() {
        let both = Snapshot(isUbiquitousItem: true, isUploaded: false, downloadingStatus: .notDownloaded)
        #expect(SyncState.derive(from: both) == .uploading)
    }

    /// Errors are detail for the wiring; iCloud retries, so the owed direction stands.
    @Test func errorsDoNotChangeTheState() {
        let uploadFailed   = Snapshot(isUbiquitousItem: true, isUploaded: false, hasUploadingError: true)
        let downloadFailed = Snapshot(isUbiquitousItem: true, downloadingStatus: .notDownloaded, hasDownloadingError: true)
        let settledErrors  = Snapshot(isUbiquitousItem: true, hasUploadingError: true, hasDownloadingError: true)
        #expect(SyncState.derive(from: uploadFailed)   == .uploading)
        #expect(SyncState.derive(from: downloadFailed) == .downloading)
        #expect(SyncState.derive(from: settledErrors)  == .upToDate)
        #expect(SyncState.derive(from: uploadFailed, networkReachable: false) == .waitingForNetwork)
    }

    // MARK: - From resource values

    /// The `URLResourceValues` initializer maps each key; an empty set of values (keys
    /// never requested) reads as a local file.
    @Test func resourceValuesMapToTheSnapshot() {
        let empty = URLResourceValues()
        #expect(Snapshot(empty) == Snapshot(isUbiquitousItem: false))
        #expect(SyncState.derive(from: Snapshot(empty)) == nil)
        #expect(Snapshot.DownloadingStatus(.current)       == .current)
        #expect(Snapshot.DownloadingStatus(.downloaded)    == .downloaded)
        #expect(Snapshot.DownloadingStatus(.notDownloaded) == .notDownloaded)
        #expect(Snapshot.resourceKeys.count == 8)
    }

    @Test func everyStateHasATitle() {
        for state in SyncState.allCases {
            #expect(!state.localizedTitle.isEmpty)
        }
    }
}
