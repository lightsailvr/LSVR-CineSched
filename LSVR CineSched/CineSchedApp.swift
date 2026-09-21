//
//  CineSchedApp.swift
//  CineSched
//
//  Created by Christopher Tempel on 7/15/25.
//
//  The app is document-based on every platform (ADR 0004). On the Mac (#8) `DocumentGroup`
//  opens one window per `ProjectDocument`, and the system supplies New, Open, Open Recent,
//  Save, Duplicate, Rename, Move To, Revert To, Close, the edited indicator, autosave in
//  place, and the Edit menu's Undo and Redo. The menus below add only what is CineSched's
//  own, and each item reaches the frontmost window through `ProjectCommands` (a focused
//  scene value). On iOS, iPadOS and visionOS (#12, ADR 0006) the same `DocumentGroup`
//  opens one file at a time from the system's launch screen (title, New Project, Import
//  Script…, Import Project… (#13), recents, the document browser), which starts in the
//  CineSched folder in iCloud Drive, into `ProjectEditor` (#17): the three-column
//  editor in regular width, the minimal editor in compact width.

import SwiftUI
#if os(macOS)
import AppKit
#endif

// Platform seam: the launch screen's creation sources (#13); `DocumentCreationSource` has no
// initializer on the Mac.
#if !os(macOS)
extension DocumentCreationSource {
    /// Import Script…: a new project whose Boneyard holds a screenplay's scenes.
    static let importScript  = DocumentCreationSource(id: "importScript")
    /// Import Project…: a new `.cinesched` holding a legacy `.json`'s project.
    static let importProject = DocumentCreationSource(id: "importProject")
}
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
    #else
    // Platform seam: the launch screen's Import Script… and Import Project… (#13). One
    // flow serves both buttons; `makeDocument` awaits it and the presentation modifier
    // on the launch scene shows its picker and summary.
    @State private var launchImport = LaunchImportFlow()
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
        // window content and the app-wide menus; the other platforms run it with
        // `ProjectEditor` (the three-column editor in regular width, #17; the minimal
        // editor in compact width until M4) and the system's launch screen. Both halves
        // make the document the same way, and only through `ProjectDocument`, so the
        // file, the undo funnel and the palette adoption are one code path.
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
            // The device's legacy color overrides ride along for a project without a
            // palette to adopt (#11).
            ProjectDocument(
                MacAppDelegate.takePendingUntitledProject() ?? .newProject(),
                configuration: configuration,
                deviceOverrides: SceneColorSettings.deviceOverrides()
            )
        })
        .commands { menus }
        #else
        DocumentGroup(editor: { document in
            ProjectEditor(document: document)
                .accentColor(currentTheme.primaryAccent(isDarkMode: isDarkMode))
        }, makeDocument: { configuration, context in
            // New Project and an opened file alike start from the template; an opened
            // file's contents arrive through the reader and `apply` straight after. The
            // two imports (#13) start from what their flow returns: the button's
            // creation source lands here, this closure is async, and a throw (the user
            // cancelled) leaves the launch screen as it was. The device's legacy color
            // overrides ride along for a project without a palette to adopt (#11); on
            // these platforms no device ever had any, so a file from before #11 keeps the
            // standard code until a Mac adopts into it.
            let project: ProjectData
            switch context.creationSource {
            case .importScript:  project = try await launchImport.prepareProject(for: .script)
            case .importProject: project = try await launchImport.prepareProject(for: .project)
            default:             project = .newProject()
            }
            return ProjectDocument(
                project,
                configuration: configuration,
                deviceOverrides: SceneColorSettings.deviceOverrides()
            )
        })

        // The system's launch screen: title, the actions below, the recents grid and a
        // Browse button into the document browser, which starts in the CineSched folder
        // (`NSUbiquitousContainers` in Config/Info.plist, ADR 0006). The two imports
        // (#13) are typed creation sources; the screen shows two actions and folds the
        // rest into a More… menu. Their picker, summary and failure message hang off the
        // New Project button, which stays on screen while `makeDocument` awaits the flow
        // (the modifier needs a view in the launch scene; any of the three would do).
        DocumentGroupLaunchScene(L("CineSched")) {
            NewDocumentButton(L("New Project"))
                .launchImportPresentation(launchImport)
            NewDocumentButton(L("Import Script…"),  source: .importScript)
            NewDocumentButton(L("Import Project…"), source: .importProject)
        } background: {
            ProjectLaunchBackground()
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
