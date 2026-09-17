//
//  CineSchedApp.swift
//  CineSched
//
//  Created by Christopher Tempel on 7/15/25.
//
//  On the Mac the app is document-based (#8, ADR 0004): `DocumentGroup` opens one window
//  per `ProjectDocument`, and the system supplies New, Open, Open Recent, Save, Duplicate,
//  Rename, Move To, Revert To, Close, the edited indicator, autosave in place, and the
//  Edit menu's Undo and Redo. The menus below add only what is CineSched's own, and each
//  item reaches the frontmost window through `ProjectCommands` (a focused scene value).

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct CineSchedApp: App {
    @AppStorage("CineSchedDarkMode") private var isDarkMode: Bool = false
    @AppStorage("CineSchedIncludeHoldInDOOD") private var includeHoldInDOOD: Bool = true
    @AppStorage("cinesched_app_language") private var appLanguage: AppLanguage = .english
    @AppStorage("CineSchedTheme") private var currentTheme: AppTheme = .blue

    /// The key window's command slots; nil while no project window is key, which disables
    /// every item that needs one.
    @FocusedValue(\.projectCommands) private var commands

    // Platform seam: the delegate that recovers the legacy UserDefaults working copy on
    // the first launch of the document model (#10). Mac-only because the copy was.
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    init() {
        // Platform seam: window tabbing is a Mac-only concept (the "+" tab bar the system
        // adds to every multi-window app), and a schedule window makes no sense as a tab.
        #if os(macOS)
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
    }

    var body: some SwiftUI.Scene {
        // Platform seam: the Mac runs the document lifecycle with its full editor as the
        // window content; the other platforms show the in-progress placeholder until their
        // own document scenes land (#1, M2 #12 and M3/M4).
        #if os(macOS)
        DocumentGroup(editor: { document in
            // A legacy .json is never edited in place: its contents move to an untitled
            // .cinesched document (see LegacyProjectHandoff). The URL is read live because
            // the configuration receives it after the document is made.
            if ProjectDocument.isLegacySource(document.fileURL) {
                LegacyProjectHandoff(document: document)
            } else {
                ContentView(document: document)
                    .accentColor(currentTheme.primaryAccent(isDarkMode: isDarkMode))
            }
        }, makeDocument: { configuration, _ in
            // Called for New and for Open alike; an opened file's contents arrive through
            // the reader and `apply` straight after, replacing the blank month. The one
            // untitled document that starts with a project is the recovered working copy.
            ProjectDocument(MacAppDelegate.takePendingUntitledProject() ?? .newProject(), configuration: configuration)
        })
        .commands { menus }
        #else
        WindowGroup {
            PlatformPlaceholderView()
        }
        #endif
    }

    @CommandsBuilder
    private var menus: some Commands {
        // File menu — the import and export items, between the system's Save group and Print
        CommandGroup(replacing: .importExport) {
            Button(L("Import Script…", lang: appLanguage)) {
                commands?.importScript()
            }
            .disabled(commands == nil)

            Divider()

            Button(L("Export Schedule to PDF…", lang: appLanguage)) {
                commands?.exportSchedulePDF()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(commands == nil)

            Button(L("Export Strip Schedule to PDF…", lang: appLanguage)) {
                commands?.exportStripboardPDF()
            }
            .disabled(commands == nil)

            Button(L("Export Days Out of Days…", lang: appLanguage)) {
                commands?.exportDaysOutOfDays()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(commands == nil)

            Button(L("Export Scene Breakdowns…", lang: appLanguage)) {
                commands?.exportBreakdowns()
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(commands == nil)
        }

        // A home for the actions that don't fit File/Edit/View
        CommandMenu("Production") {
            Button(L("Production Setup…", lang: appLanguage)) {
                commands?.openProductionSetup()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(commands == nil)

            Button(L("Scan for Conflicts…", lang: appLanguage)) {
                commands?.scanForConflicts()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(commands == nil)

            Divider()

            Button(L("Breakdown Browser…", lang: appLanguage)) {
                commands?.openBreakdownBrowser()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(commands == nil)

            Divider()

            Toggle(L("Include Hold Days in DOoD Report", lang: appLanguage), isOn: $includeHoldInDOOD)

            Divider()

            Button(L("Lock Schedule", lang: appLanguage)) {
                commands?.lockSchedule()
            }
            .disabled(commands == nil)
            Button(L("Unlock Schedule", lang: appLanguage)) {
                commands?.unlockSchedule()
            }
            .disabled(commands == nil)
            Button(L("Schedule Lock Report…", lang: appLanguage)) {
                commands?.showScheduleLockReport()
            }
            .disabled(commands == nil)
        }

        // View menu — appearance for the app, then the key window's view state
        CommandGroup(after: .toolbar) {
            Divider()
            Toggle(L("Dark Mode", lang: appLanguage), isOn: $isDarkMode)
                .keyboardShortcut("d", modifiers: [.command, .shift])

            Picker(L("Schedule View", lang: appLanguage), selection: commands?.viewMode ?? .constant(.calendar)) {
                ForEach(ScheduleViewMode.allCases, id: \.self) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            }
            .disabled(commands == nil)

            Toggle(L("Show Cast in Calendar", lang: appLanguage), isOn: commands?.showCastOnCards ?? .constant(false))
                .disabled(commands == nil)
            Toggle(L("Show Estimated Time Instead of Page Count", lang: appLanguage), isOn: commands?.showEstTimeOnCards ?? .constant(false))
                .disabled(commands == nil)

            Menu(L("Theme", lang: appLanguage)) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Button(currentTheme == theme ? "✓ \(theme.localizedName)" : theme.localizedName) {
                        currentTheme = theme
                    }
                }
            }

            Button(L("Color Legend…", lang: appLanguage)) {
                commands?.showColorLegend()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(commands == nil)

            Button(L("Customize Scene Colors…", lang: appLanguage)) {
                commands?.showSceneColorSettings()
            }
            .disabled(commands == nil)

            Button(L("Stripboard Fields…", lang: appLanguage)) {
                commands?.showStripboardFields()
            }
            .disabled(commands == nil)
            Toggle(L("Show All Days on Stripboard", lang: appLanguage), isOn: commands?.stripboardShowAllDays ?? .constant(false))
                .disabled(commands == nil)
        }
    }
}
