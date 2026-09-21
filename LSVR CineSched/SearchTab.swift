// SearchTab.swift
// The iPhone's Search tab (#27), the tab in the search role: one field over the whole
// project, its results from `SceneSearch.results` (number, slugline, cast, summary and
// real location; never a banner, an auto-meal or an event), grouped into the scheduled
// scenes (each with its day) and the Boneyard. A result's tap opens the scene editor
// (the phone's one, through `PhoneDayEdits.presentSceneEditor`, bound by id, with the
// results shown as the siblings Previous and Next step through; its Delete follows where
// the scene is: a scheduled one returns to the Boneyard, a Boneyard one is deleted); its
// trailing button, swipe and menu show the scene
// where it lives: Show in Days switches to the Days tab and scrolls it to the day
// (`PhoneEditor.scrollToDate`, the hook the Today control and the reports use), Show in
// Boneyard switches to the Boneyard tab and scrolls it to the scene. No recent
// searches. The results are recomputed per keystroke over the project, a string scan
// per scene, only while this tab is showing.
//
// The tab's `NavigationStack` exists for the search field: `.searchable` draws it in a
// navigation bar, and with that bar hidden (`editorNavigationBarHidden`, the Days tab's
// way) no field appears at all, on 27.0 the search-role tab does not move it into the tab
// bar under the document infrastructure's scene. So the bar stays, and what the document
// infrastructure mirrors into it (learnings 2026-09-21 #24) is taken out piece by piece:
// its Back button (`navigationBarBackButtonHidden`) and its title menu
// (`toolbar(removing: .title)`), which leaves the bar holding the field alone under the
// document's own bar. Nothing pushes. Platform-free SwiftUI; the Mac compiles it and
// never shows it.

import SwiftUI

struct SearchTab: View {
    let document: ProjectDocument
    /// The scene editor (#26's funnel, the same on every tab).
    let dayEdits: PhoneDayEdits
    /// Switches to the Days tab and scrolls it to the day with this date.
    let showInDays:     (Date) -> Void
    /// Switches to the Boneyard tab and scrolls it to this scene.
    let showInBoneyard: (UUID) -> Void
    @Environment(\.scenePalette) private var palette

    @State private var query = ""

    private var project: ProjectData { document.project }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            resultsList
                .searchable(text: $query, prompt: Text(L("Number, slugline, cast or summary")))
                .autocorrectionDisabled()
                .navigationBarBackButtonHidden(true)
                .toolbar(removing: .title)
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        let results    = SceneSearch.results(for: query, in: project)
        let scheduled  = results.filter { !$0.isInBoneyard }
        let boneyard   = results.filter(\.isInBoneyard)
        let dayNumbers = productionDayNumbers(for: project.shootDays)
        let trimmed    = query.trimmingCharacters(in: .whitespaces)
        return List {
            if trimmed.isEmpty {
                ContentUnavailableView(
                    L("Search Scenes"),
                    systemImage: "magnifyingglass",
                    description: Text(L("Find a scene by number, slugline, cast or summary, on any day or in the Boneyard."))
                )
                .listRowBackground(Color.clear)
            } else if results.isEmpty {
                ContentUnavailableView.search(text: trimmed)
                    .listRowBackground(Color.clear)
            } else {
                if !scheduled.isEmpty {
                    Section(scheduled.count == 1 ? L("1 scheduled") : String(format: L("%d scheduled"), scheduled.count)) {
                        ForEach(scheduled) { result in
                            row(result, dayNumbers: dayNumbers, siblings: results)
                        }
                    }
                }
                if !boneyard.isEmpty {
                    Section(boneyard.count == 1 ? L("1 in the Boneyard") : String(format: L("%d in the Boneyard"), boneyard.count)) {
                        ForEach(boneyard) { result in
                            row(result, dayNumbers: dayNumbers, siblings: results)
                        }
                    }
                }
            }
        }
        .insetGroupedListStyle()
    }

    // MARK: - Row

    /// One hit: its strip color, number and slugline, where it is and what matched
    /// (the cast, else the summary); the trailing button shows it there, the tap opens
    /// the editor over the results shown (`siblings`, what Previous and Next step).
    private func row(_ result: SceneSearchResult, dayNumbers: [UUID: Int], siblings: [SceneSearchResult]) -> some View {
        let scene = result.scene
        let day   = result.dayIndex.map { project.shootDays[$0] }
        return Button {
            openEditor(for: result, siblings: siblings)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(scene.stripColor(in: palette))
                    .frame(width: 6, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if !scene.sceneNumber.isEmpty {
                            Text(scene.sceneNumber)
                                .font(.subheadline.weight(.bold).monospaced())
                                .foregroundStyle(Color.secondary)
                        }
                        Text(scene.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.primary)
                            .lineLimit(2)
                    }
                    Text(whereText(day: day, dayNumbers: dayNumbers))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(day == nil ? Color.orange : Color.blue)
                        .lineLimit(1)
                    if let detail = detailText(scene) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    show(result, day: day)
                } label: {
                    Image(systemName: day == nil ? "tray.full" : "calendar.day.timeline.left")
                        .font(.title3)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(day == nil ? L("Show in Boneyard") : L("Show in Days"))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(scene.sceneNumber) \(scene.title)"))
        .contextMenu {
            Button {
                openEditor(for: result, siblings: siblings)
            } label: {
                Label(L("Edit Scene"), systemImage: "pencil")
            }
            Button {
                show(result, day: day)
            } label: {
                Label(day == nil ? L("Show in Boneyard") : L("Show in Days"), systemImage: day == nil ? "tray.full" : "calendar.day.timeline.left")
            }
        } preview: {
            StripPreview(scene: scene)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                show(result, day: day)
            } label: {
                Label(day == nil ? L("Boneyard") : L("Days"), systemImage: day == nil ? "tray.full" : "calendar.day.timeline.left")
            }
            .tint(day == nil ? .orange : .blue)
        }
    }

    /// "Day 3 · Mon Nov 2", a typed or empty day's date alone, or "Boneyard".
    private func whereText(day: ShootDay?, dayNumbers: [UUID: Int]) -> String {
        guard let day else { return L("Boneyard") }
        return DaySummary.label(dayNumber: dayNumbers[day.id], date: day.date)
    }

    /// The cast, else the summary's first lines; nil when the scene has neither.
    private func detailText(_ scene: Scene) -> String? {
        if !scene.cast.isEmpty { return scene.cast.joined(separator: ", ") }
        let summary = scene.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    private func show(_ result: SceneSearchResult, day: ShootDay?) {
        if let day { showInDays(day.date) } else { showInBoneyard(result.scene.id) }
    }

    /// The scene editor over a result, with the results shown as what Previous and Next
    /// step through (no day: the editor's Delete reads where the scene is, so a scheduled
    /// result still returns to the Boneyard and a Boneyard one is deleted).
    private func openEditor(for result: SceneSearchResult, siblings: [SceneSearchResult]) {
        dayEdits.presentSceneEditor(sceneID: result.scene.id, dayID: nil, siblingIDs: siblings.map(\.scene.id))
    }
}
