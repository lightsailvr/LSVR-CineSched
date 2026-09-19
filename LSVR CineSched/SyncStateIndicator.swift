// SyncStateIndicator.swift
// The sync state beside the project title (#14) and, in the same spot, the conflict
// notice (#15). Platform-free SwiftUI: the Mac's toolbar row and the minimal editor's
// title section both place it next to the title. Subtle by design: an SF Symbol and a
// caption in the secondary color, animated only while a transfer is in progress, and
// nothing at all (no space) for a file outside iCloud or an untitled document, where
// `SyncMonitor.state` is nil.
//
// After a conflict the indicator reads "Conflict Resolved" in the warning tint and opens
// the notice as a popover: which device's version was set aside and when, with Restore
// other version (through the funnel, so it is undoable) and Dismiss. The popover opens
// by itself the moment a notice is raised and again on a click while the notice stands;
// it goes with the notice, which the next edit retires.

import SwiftUI

struct SyncStateIndicator: View {
    let monitor: SyncMonitor
    @Environment(\.undoManager) private var undoManager
    @State private var showingNotice = false

    var body: some View {
        if let state = monitor.state {
            Button {
                if monitor.notice != nil { showingNotice = true }
            } label: {
                Label(state.localizedTitle, systemImage: Self.symbolName(for: state))
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(state == .conflictResolved ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .symbolEffect(.variableColor.iterative, isActive: state == .uploading || state == .downloading)
                    .contentTransition(.symbolEffect(.replace))
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help(helpText(for: state))
            .accessibilityLabel(Text("\(L("iCloud")): \(state.localizedTitle)"))
            .accessibilityHint(monitor.notice != nil ? Text(L("Shows the conflict notice")) : Text(""))
            .popover(isPresented: $showingNotice, arrowEdge: .bottom) {
                if let notice = monitor.notice {
                    ConflictNoticeView(
                        notice:     notice,
                        canRestore: monitor.canRestore,
                        onRestore:  {
                            monitor.restoreOtherVersion(undoManager: undoManager)
                            showingNotice = false
                        },
                        onDismiss:  {
                            monitor.dismissNotice()
                            showingNotice = false
                        }
                    )
                }
            }
            .onChange(of: monitor.notice) { _, notice in
                showingNotice = notice != nil
            }
        }
    }

    // MARK: - Presentation

    static func symbolName(for state: SyncState) -> String {
        switch state {
        case .upToDate:          return "checkmark.icloud"
        case .uploading:         return "icloud.and.arrow.up"
        case .downloading:       return "icloud.and.arrow.down"
        case .waitingForNetwork: return "icloud.slash"
        case .conflictResolved:  return "exclamationmark.icloud"
        }
    }

    /// The tooltip: the state, plus the detail the resource values carry but the state
    /// does not show (an upload or download error iCloud is retrying, versions still in
    /// conflict where the system resolves them).
    private func helpText(for state: SyncState) -> String {
        var lines = [String(format: L("iCloud Drive: %@"), state.localizedTitle)]
        if let snapshot = monitor.snapshot {
            if snapshot.hasUploadingError      { lines.append(L("The last upload failed; iCloud will retry.")) }
            if snapshot.hasDownloadingError    { lines.append(L("The last download failed; iCloud will retry.")) }
            if snapshot.hasUnresolvedConflicts { lines.append(L("Versions of this project are in conflict.")) }
        }
        if monitor.notice != nil { lines.append(L("Click for the conflict notice.")) }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Notice

/// The popover's content: what happened, the device and time of the version set aside,
/// and the two actions.
struct ConflictNoticeView: View {
    let notice:     ConflictNotice
    let canRestore: Bool
    let onRestore:  () -> Void
    let onDismiss:  () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("Conflict Resolved"), systemImage: "exclamationmark.icloud")
                .font(.headline)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("Dismiss"), action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                if canRestore {
                    Button(L("Restore Other Version"), action: onRestore)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
    }

    private var message: String {
        let when = notice.modificationDate.formatted(date: .abbreviated, time: .shortened)
        switch notice.origin {
        case .policy:
            let device = notice.deviceName ?? L("another device")
            return String(format: L("Resolved a conflict: kept the newer version. The version from %@ at %@ was set aside."), device, when)
        case .replacedUnsavedEdits:
            return String(format: L("iCloud replaced this copy with a newer version. The edits made here at %@ were set aside."), when)
        }
    }
}
