// MinimalProjectEditor.swift
// What a project document shows on iOS, iPadOS and visionOS until their real editors
// land (#12, milestone 2 of #1): the project title as an editable field and the shoot
// days with their scene counts. Deliberately small; its job is to prove the document
// lifecycle (create in the CineSched folder, autosave, reopen, sync) on those platforms,
// and milestones 3 and 4 replace it. Platform-free SwiftUI so it needs no seam: it also
// compiles on the Mac, which never shows it (CineSchedApp gives the Mac `ContentView`).
//
// Every write goes through `document.perform` with the window's `UndoManager`, as on
// the Mac: the document infrastructure autosaves only from registered undo actions, so a
// write that bypassed the funnel would never reach the file. Typing in the title field is
// one undo step per focus session (`titleGesture`, the pattern `ContentView` uses). The
// sync indicator beside the title and its conflict notice (#14, #15) come from a
// `SyncMonitor` the editor owns, as on the Mac.

import SwiftUI

struct MinimalProjectEditor: View {
    let document: ProjectDocument
    @Environment(\.undoManager) private var undoManager

    /// Every keystroke writes the title binding; one token per focus session folds them
    /// into one undo step, and losing focus mints the next.
    @State private var titleGesture = EditGesture()
    @FocusState private var titleFieldFocused: Bool

    /// The iCloud sync state beside the title and the conflict notice (#14, #15): one
    /// monitor per scene, fed the document's counts and the scene phase below.
    @State private var syncMonitor = SyncMonitor()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    TextField(L("Movie Title"), text: projectTitleBinding)
                        .font(.title2)
                        .focused($titleFieldFocused)
                    SyncStateIndicator(monitor: syncMonitor)
                }
            }
            Section(L("Shoot Days")) {
                if document.project.shootDays.isEmpty {
                    Text(L("No shoot days"))
                        .foregroundStyle(.secondary)
                }
                ForEach(document.project.shootDays) { day in
                    ShootDayRow(day: day)
                }
            }
        }
        .onChange(of: titleFieldFocused) { _, focused in
            if !focused { titleGesture = EditGesture() }
        }
        .onAppear {
            syncMonitor.attach(undoManager: undoManager)
            syncMonitor.start(document: document)
        }
        .onDisappear {
            syncMonitor.stop()
        }
        .onChange(of: document.changeCount) { _, newCount in
            syncMonitor.documentDidChange(changeCount: newCount)
        }
        .onChange(of: document.restoreCount) { _, _ in
            syncMonitor.documentWasRestored()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { syncMonitor.sceneDidActivate() }
        }
    }

    // MARK: - Edits

    private var projectTitleBinding: Binding<String> {
        Binding(get: { document.project.projectTitle }, set: { new in
            document.perform(L("Rename Project"), coalescing: titleGesture, undoManager: undoManager) { $0.projectTitle = new }
        })
    }
}

// MARK: - Day row

/// One shoot day: its date and how many script scenes it holds (banners, auto-meals and
/// calendar events are not scenes). `formattedDate` caches its formatter, so the row is
/// cheap enough to draw per day (#34).
private struct ShootDayRow: View {
    let day: ShootDay

    private var sceneCount: Int {
        day.scenes.filter { !$0.isBanner && !$0.isCalendarEvent }.count
    }

    var body: some View {
        HStack {
            Text(formattedDate(day.date))
            if day.dayType != .shoot {
                Text(day.dayType.localizedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(sceneCount == 1 ? L("1 scene") : String(format: L("%d scenes"), sceneCount))
                .foregroundStyle(sceneCount == 0 ? .tertiary : .secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Launch screen background

/// The launch screen's backdrop on iOS and visionOS (behind the title, New Project and
/// the recents): the accent color and the app's film-stack symbol, kept quiet so the
/// system's controls read over it.
struct ProjectLaunchBackground: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: "film.stack")
                .font(.system(size: 220, weight: .thin))
                .foregroundStyle(.white.opacity(0.18))
                .padding(.top, 48)
                .padding(.trailing, -40)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}
