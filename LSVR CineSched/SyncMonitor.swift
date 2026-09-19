// SyncMonitor.swift
// The observer behind the sync indicator (#14) and the conflict notice (#15): one per
// editor (a Mac window, an iOS or visionOS scene), owned as `@State` and started with the
// document. It publishes `state`, the `SyncState?` beside the title, and `notice`, the
// conflict notice with its retained snapshot; the mapping and the decision are the pure
// halves (`SyncState.derive`, `ConflictPolicy.decide`, `ConflictNoticeState`), and this
// file is the wiring around them.
//
// How the state is observed, on every platform alike (no `#if os`; the one platform
// difference, who resolves a conflict, is the `PlatformConflictResolution` seam):
//   - The document URL's ubiquitous resource values (`UbiquitousResourceSnapshot.
//     resourceKeys`), read on start, on every change to the document (`changeCount`),
//     on every restore (`restoreCount`), when the scene becomes active, and on a poll:
//     every 2 s while the file is in iCloud, every 10 s otherwise (to notice a save into
//     the CineSched folder). The read is one `stat`-class call, and it works without an
//     iCloud entitlement: the Mac reads `isUbiquitousItem == true` and the transfer keys
//     for any file under `~/Library/Mobile Documents` it may open (learnings, 2026-09-19).
//   - An `NSMetadataQuery` over the ubiquitous documents and external-documents scopes,
//     with a predicate on the file's path, whose update notifications trigger a re-read.
//     It reports on iOS and visionOS, where the app has the container entitlement, and
//     gathers nothing on the entitlement-free Mac, which is why the poll exists too.
//   - An `NWPathMonitor` for `networkReachable`, on every platform including the Mac,
//     whose indicator must show the same states as the iPad's (issue #14).
//
// Conflicts (#15). Where the platform leaves them to the app, `checkForConflicts` runs on
// start, on every restore, when the metadata query reports, when the scene activates and
// when the resource values say `hasUnresolvedConflicts`: it lists `NSFileVersion`'s
// unresolved conflict versions, reads each one's contents inside a coordinated read
// through the document's own coordinator (never an uncoordinated read of a version URL;
// the read also downloads a version that has no local contents), decides with
// `ConflictPolicy`, applies a winning other version through `document.perform` (one undo
// step, and what the infrastructure autosaves from), then under a coordinated
// metadata-only write marks every conflict version resolved and removes it, as the
// `NSFileVersion` header prescribes ("set this property to YES … you must then remove any
// versions of the file that are no longer useful"). Only the conflict versions are
// removed, never the Mac's own saved versions. The loser's snapshot is retained here for
// the session; Restore other version applies it through `perform`, so it is undoable.
//
// The fallback. When the versions are not observable (the Mac, where NSDocument's own
// sheet resolves them; or a platform that resolved before the app looked), a snapshot
// from disk can still replace edits this device had not written. `ProjectDocument`
// records those edits when `apply` runs over unsaved changes, and the monitor takes the
// record on the restore that produced it: the notice then cannot name the other device,
// but the replaced edits are retained and restorable like a policy loser. Which path
// fires where is in CLAUDE.md and learnings (2026-09-19).

import Foundation
import Network
import Observation

@MainActor
@Observable
final class SyncMonitor {

    // MARK: - Published

    /// What the indicator shows; nil for a file outside iCloud, an untitled document, or
    /// a monitor that has not started.
    private(set) var state: SyncState?

    /// The last resource values read; nil before the first read or for an untitled
    /// document. Carried for the indicator's detail text (errors, pending conflicts).
    private(set) var snapshot: UbiquitousResourceSnapshot?

    /// The network as the path monitor last reported it; true until it has.
    private(set) var networkReachable = true

    /// The conflict notice on display, or nil.
    var notice: ConflictNotice? { noticeState.notice }

    /// Whether Restore other version has a snapshot to apply.
    var canRestore: Bool { retainedSnapshot != nil && (notice?.canRestore ?? false) }

    // MARK: - Configuration

    /// Whether this monitor runs the conflict policy or leaves versions to the system;
    /// the platform seam decides in the app, a test passes its own.
    private let resolvesConflicts: Bool

    init(resolvesConflicts: Bool = !PlatformConflictResolution.systemPresentsConflictUI) {
        self.resolvesConflicts = resolvesConflicts
    }

    // MARK: - Private state

    private var document:          ProjectDocument?
    private var noticeState        = ConflictNoticeState()
    private var retainedSnapshot:  ProjectData?
    private var pollTask:          Task<Void, Never>?
    private var pathMonitor:       NWPathMonitor?
    private var metadataQuery:     NSMetadataQuery?
    private var queryObservers:    [any NSObjectProtocol] = []
    private var queriedURL:        URL?
    private var isCheckingConflicts = false
    /// The coordinated accesses run here, off the main actor, so a presenter that has to
    /// relinquish the file never waits on the thread that asked.
    private let accessQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.lsvr.LSVR-CineSched.SyncMonitor"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    // MARK: - Lifecycle

    /// Starts observing `document`. Idempotent for the same document.
    func start(document: ProjectDocument) {
        if self.document === document, pollTask != nil { return }
        stop()
        self.document = document
        startPathMonitor()
        refresh()
        checkForConflicts()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval: Duration = (self?.snapshot?.isUbiquitousItem ?? false) ? .seconds(2) : .seconds(10)
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        stopMetadataQuery()
        document = nil
    }

    // MARK: - Events from the editor

    /// `document.changeCount` moved: an edit, an undo, a redo or a reload. Retires the
    /// notice unless the count is the resolution's own, then re-reads the file.
    func documentDidChange(changeCount: Int) {
        noticeState.documentDidChange(changeCount: changeCount)
        if !noticeState.isShowing { retainedSnapshot = nil }
        refresh()
    }

    /// `document.restoreCount` moved: the project was replaced wholesale (undo, redo, or a
    /// snapshot from disk). A snapshot from disk is where a conflict becomes visible, and
    /// where the fallback's replaced edits come from.
    func documentWasRestored() {
        refresh()
        checkForConflicts()
    }

    /// The scene came to the foreground: what iCloud did meanwhile is worth a look.
    func sceneDidActivate() {
        refresh()
        checkForConflicts()
    }

    // MARK: - Resource values

    /// Re-reads the resource values and re-derives the state. Cheap; called often.
    func refresh() {
        guard let document else { return }
        let url = document.fileURL
        snapshot = url.flatMap(Self.readSnapshot(of:))
        updateMetadataQuery(for: snapshot?.isUbiquitousItem == true ? url : nil)
        if snapshot?.hasUnresolvedConflicts == true { checkForConflicts() }
        rederive()
    }

    private func rederive() {
        state = Self.state(for: snapshot, networkReachable: networkReachable, noticeShowing: noticeState.isShowing)
    }

    /// The state for what the monitor holds: nil with no snapshot (no file), otherwise
    /// `SyncState.derive` over it. Pure; the tests drive it with fake snapshots.
    nonisolated static func state(for snapshot: UbiquitousResourceSnapshot?, networkReachable: Bool, noticeShowing: Bool) -> SyncState? {
        guard let snapshot else { return nil }
        return SyncState.derive(from: snapshot, networkReachable: networkReachable, conflictResolved: noticeShowing)
    }

    /// The URL's ubiquitous resource values as a snapshot; nil only when the read itself
    /// fails. A file that is gone does not fail it: its ubiquity keys come back unset,
    /// which is a snapshot outside iCloud, and the indicator shows nothing either way.
    nonisolated static func readSnapshot(of url: URL) -> UbiquitousResourceSnapshot? {
        guard let values = try? url.resourceValues(forKeys: UbiquitousResourceSnapshot.resourceKeys) else { return nil }
        return UbiquitousResourceSnapshot(values)
    }

    // MARK: - Network

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.networkReachable != reachable else { return }
                self.networkReachable = reachable
                self.rederive()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.lsvr.LSVR-CineSched.SyncMonitor.network", qos: .utility))
        pathMonitor = monitor
    }

    // MARK: - Metadata query

    /// Keeps one query alive for the file while it is in iCloud, on the entitled
    /// platforms; the query's own notifications only trigger `refresh`, so the resource
    /// values stay the single source of truth.
    private func updateMetadataQuery(for url: URL?) {
        let wanted = url?.standardizedFileURL
        guard wanted != queriedURL else { return }
        stopMetadataQuery()
        guard let wanted else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope, NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, wanted.path)
        query.notificationBatchingInterval = 0.5
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            queryObservers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                    self?.checkForConflicts()
                }
            })
        }
        query.start()
        metadataQuery = query
        queriedURL    = wanted
    }

    private func stopMetadataQuery() {
        metadataQuery?.stop()
        metadataQuery = nil
        queryObservers.forEach(NotificationCenter.default.removeObserver)
        queryObservers.removeAll()
        queriedURL = nil
    }

    // MARK: - Conflicts

    /// Looks for the system's unresolved conflict versions and, where this platform
    /// resolves them, decides. Where it does not (the Mac), only the fallback below can
    /// raise a notice. Re-entrancy is refused: a check in flight covers the trigger.
    func checkForConflicts() {
        guard let document, !isCheckingConflicts else { return }
        let replaced = document.takeReplacedUnsavedEdits()
        guard resolvesConflicts, let url = document.fileURL,
              let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !versions.isEmpty
        else {
            raiseFallbackNotice(for: replaced)
            return
        }
        isCheckingConflicts     = true
        pendingConflictVersions = versions
        // What the accessor needs is Sendable: the version URLs and their metadata. The
        // versions themselves stay on the main actor for the resolution step.
        let entries: [(id: String, url: URL, date: Date, device: String?)] = versions.enumerated().map { index, version in
            ("version-\(index)", version.url, version.modificationDate ?? .distantPast, version.localizedNameOfSavingComputer)
        }
        let coordinator = document.makeFileCoordinator()
        let intents     = entries.map { NSFileAccessIntent.readingIntent(with: $0.url, options: []) }
        coordinator.coordinate(with: intents, queue: accessQueue) { [weak self] error in
            let readFailed = error != nil
            // The coordinator may have redirected an intent; read from `intent.url`.
            let others: [ConflictVersion] = readFailed ? [] : zip(entries, intents).map { entry, intent in
                let snapshot = (try? Data(contentsOf: intent.url)).flatMap { try? ProjectCodec.decode($0) }
                return ConflictVersion(id: entry.id, modificationDate: entry.date, deviceName: entry.device, snapshot: snapshot)
            }
            Task { @MainActor [weak self] in
                self?.finishConflictCheck(others: others, readFailed: readFailed, replaced: replaced)
            }
        }
    }

    /// The versions a check in flight is reading, for the resolution step once it lands.
    private var pendingConflictVersions: [NSFileVersion] = []

    /// The decision and what follows from it, back on the main actor. A version whose
    /// contents could not be read is not a version that can win: it stays unresolved for
    /// the next check (the coordinated read may still be downloading it).
    private func finishConflictCheck(others: [ConflictVersion], readFailed: Bool, replaced: ProjectDocument.ReplacedEdits?) {
        isCheckingConflicts = false
        let versions = pendingConflictVersions
        pendingConflictVersions = []
        guard let document else { return }
        let readable = others.filter { $0.snapshot != nil }
        guard !readFailed, readable.count == others.count, let url = document.fileURL else {
            raiseFallbackNotice(for: replaced)
            return
        }
        let fileVersion = NSFileVersion.currentVersionOfItem(at: url)
        let current     = ConflictVersion.current(
            project:              document.project,
            fileModificationDate: fileVersion?.modificationDate ?? document.lastContentModificationDate,
            fileDeviceName:       fileVersion?.localizedNameOfSavingComputer,
            hasUnsavedEdits:      document.hasUnsavedEdits,
            lastEditDate:         document.lastEditDate,
            now:                  Date()
        )
        let decision = ConflictPolicy.decide(current: current, others: readable)
        if !decision.currentWins, let winning = decision.winner.snapshot {
            document.perform(L("Resolve Conflict"), undoManager: undoManager) { data in
                data = Self.adopting(winning, paletteOf: data)
            }
        }
        // Every conflict version is now accounted for: the winner's contents live in the
        // document (and autosave as the current version), the losers are retained here
        // or lost by the policy's rule. Marking and removing happen under a coordinated
        // write, as the header prescribes.
        resolve(versions, of: url)
        retainedSnapshot = decision.retained?.snapshot
        if let notice = ConflictNotice(decision: decision) {
            noticeState.raise(notice, changeCount: document.changeCount)
        }
        rederive()
    }

    /// The winner's snapshot with the document's palette when the winner brought none
    /// (a file from before #11 saved elsewhere), so a resolution never resets the strip
    /// colors this project already adopted.
    nonisolated static func adopting(_ snapshot: ProjectData, paletteOf project: ProjectData) -> ProjectData {
        guard snapshot.palette == nil, let palette = project.palette else { return snapshot }
        var adopted = snapshot
        adopted.palette = palette
        return adopted
    }

    /// Marks `versions` resolved and removes them from the version store, inside a
    /// coordinated write on the file that changes no content (`.contentIndependentMetadataOnly`,
    /// so the presenter is not asked to save). The versions are not Sendable; they are
    /// handed to the accessor and not touched here again.
    private func resolve(_ versions: [NSFileVersion], of url: URL) {
        nonisolated(unsafe) let versions = versions
        let coordinator = document?.makeFileCoordinator() ?? NSFileCoordinator(filePresenter: nil)
        let intent = NSFileAccessIntent.writingIntent(with: url, options: [.contentIndependentMetadataOnly])
        coordinator.coordinate(with: [intent], queue: accessQueue) { error in
            guard error == nil else { return }
            for version in versions {
                version.isResolved = true
                try? version.remove()
            }
        }
    }

    /// The fallback notice for edits a snapshot replaced (see the header); nothing when
    /// there were none, or when the file is not in iCloud (a local reload is the user's
    /// own Revert, not a sync event).
    private func raiseFallbackNotice(for replaced: ProjectDocument.ReplacedEdits?) {
        guard let replaced, let document, snapshot?.isUbiquitousItem == true else { return }
        retainedSnapshot = replaced.project
        let notice = ConflictNotice(
            origin:           .replacedUnsavedEdits,
            deviceName:       nil,
            modificationDate: replaced.editedAt ?? Date(),
            canRestore:       true
        )
        noticeState.raise(notice, changeCount: document.changeCount)
        rederive()
    }

    // MARK: - Acting on the notice

    /// The undo manager the resolution registers with: the editor's, handed in when it
    /// starts the monitor's actions (`restoreOtherVersion`) or set through
    /// `attach(undoManager:)` so a resolution that arrives on its own is undoable too.
    private var undoManager: UndoManager?

    /// The window's undo manager, so a resolution's `perform` registers with it.
    func attach(undoManager: UndoManager?) {
        self.undoManager = undoManager
    }

    /// Restore other version: applies the retained snapshot through the funnel (one undo
    /// step, "Undo Restore Other Version") and retires the notice.
    func restoreOtherVersion(undoManager: UndoManager?) {
        guard let document, let retained = retainedSnapshot else { return }
        document.perform(L("Restore Other Version"), undoManager: undoManager ?? self.undoManager) { data in
            data = Self.adopting(retained, paletteOf: data)
        }
        retainedSnapshot = nil
        noticeState.restored()
        rederive()
    }

    /// Dismisses the notice without restoring; the retained snapshot goes with it.
    func dismissNotice() {
        retainedSnapshot = nil
        noticeState.dismiss()
        rederive()
    }
}
