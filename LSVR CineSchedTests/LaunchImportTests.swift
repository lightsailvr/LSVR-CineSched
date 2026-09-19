//
//  LaunchImportTests.swift
//  LSVR CineSchedTests
//
//  The launch screen's Import Script… and Import Project… (#13) without the launch
//  screen: the pure steps (`ScriptImport`, `LaunchImport`) over files in a temporary
//  directory, and the flow (`LaunchImportFlow`) driven through the callbacks its
//  presentation layer would call, so a cancelled pick, a cancelled summary, a confirmed
//  script and an imported legacy project can each be pinned to what `makeDocument`
//  receives.
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import LSVR_CineSched

@MainActor
struct LaunchImportTests {

    // MARK: - Fixtures

    static let fountain = """
    Title: The Long Way Home
    Author: Someone

    INT. KITCHEN - DAY

    ANA stands at the counter.

    ANA
    Good morning.

    LUIS
    Morning.

    EXT. BEACH - NIGHT

    Waves crash. LUIS walks alone.

    LUIS
    Where is she?
    """

    static let fdx = """
    <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
    <FinalDraft DocumentType="Script" Template="No" Version="12">
    <Content>
    <Paragraph Number="1" Type="Scene Heading"><Text>INT. OFFICE - DAY</Text></Paragraph>
    <Paragraph Type="Action"><Text>MARK types furiously.</Text></Paragraph>
    <Paragraph Type="Character"><Text>MARK</Text></Paragraph>
    <Paragraph Type="Dialogue"><Text>This has to ship today.</Text></Paragraph>
    <Paragraph Number="2" Type="Scene Heading"><Text>EXT. PARKING LOT - NIGHT</Text></Paragraph>
    <Paragraph Type="Character"><Text>JEN</Text></Paragraph>
    <Paragraph Type="Dialogue"><Text>Did it ship?</Text></Paragraph>
    </Content>
    </FinalDraft>
    """

    /// A fresh directory per test; removed when the test ends.
    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    private func write(_ text: String, as name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    /// A Highland document: a zip holding `text.fountain` as a stored (uncompressed)
    /// entry, which is all `HighlandArchiveReader` needs to find the screenplay.
    private func highlandArchive(fountain: String) -> Data {
        let name    = Data("text.fountain".utf8)
        let payload = Data(fountain.utf8)
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
        func u32(_ v: Int) -> [UInt8] { u16(v & 0xffff) + u16((v >> 16) & 0xffff) }

        var local: [UInt8] = [0x50, 0x4b, 0x03, 0x04]
        local += u16(20) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0)   // version, flags, method (stored), time, date, crc
        local += u32(payload.count) + u32(payload.count) + u16(name.count) + u16(0)
        local += name + payload

        var central: [UInt8] = [0x50, 0x4b, 0x01, 0x02]
        central += u16(20) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0)
        central += u32(payload.count) + u32(payload.count) + u16(name.count) + u16(0) + u16(0)
        central += u16(0) + u16(0) + u32(0) + u32(0)                   // disk, attrs, local header offset
        central += name

        var eocd: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        eocd += u16(0) + u16(0) + u16(1) + u16(1)
        eocd += u32(central.count) + u32(local.count) + u16(0)

        return Data(local + central + eocd)
    }

    /// Runs `prepareProject` for `kind` and returns once the flow is waiting on the
    /// picker, so a test can answer as the presentation layer would.
    private func startFlow(_ flow: LaunchImportFlow, _ kind: LaunchImportKind) async -> Task<ProjectData, Error> {
        let task = Task { try await flow.prepareProject(for: kind) }
        while flow.stage != .picking(kind) { await Task.yield() }
        return task
    }

    // MARK: - Content types

    @Test func scriptPickerOffersTheMacPanelsTypesAndProjectPickerOffersJSON() throws {
        let script = LaunchImportKind.script.contentTypes
        #expect(script == ScriptImport.contentTypes)
        #expect(script.contains(try #require(UTType(filenameExtension: "fdx"))))
        #expect(script.contains(try #require(UTType(filenameExtension: "fountain"))))
        #expect(script.contains(try #require(UTType(filenameExtension: "highland"))))
        #expect(LaunchImportKind.project.contentTypes == [.json])
    }

    // MARK: - Parsing, one per format

    @Test func parsesAFountainScriptWithItsTitle() async throws {
        try await withTemporaryDirectory { dir in
            let result = try LaunchImport.parseScript(at: try write(Self.fountain, as: "Sample.fountain", in: dir))
            #expect(result.scenes.map(\.title) == ["INT. KITCHEN - DAY", "EXT. BEACH - NIGHT"])
            #expect(result.scenes.map(\.dayNightType) == [.day, .night])
            #expect(result.castList == ["ANA", "LUIS"])
            #expect(result.title == "The Long Way Home")
            #expect(result.fileName == "Sample.fountain")
        }
    }

    @Test func parsesAFinalDraftScriptWithSummedTotalsAndNoTitle() async throws {
        try await withTemporaryDirectory { dir in
            let result = try LaunchImport.parseScript(at: try write(Self.fdx, as: "Sample.fdx", in: dir))
            #expect(result.scenes.map(\.sceneNumber) == ["1", "2"])
            #expect(result.scenes.map(\.title) == ["INT. OFFICE", "EXT. PARKING LOT"])
            #expect(result.scenes.map(\.dayNightType) == [.day, .night])
            #expect(result.totalEighths == result.scenes.reduce(0) { $0 + $1.duration })
            #expect(result.totalEighths >= 2)
            #expect(result.castList == ["JEN", "MARK"])
            #expect(result.warnings.isEmpty)
            #expect(result.title == nil)
        }
    }

    @Test func parsesAHighlandDocumentLikeItsFountain() async throws {
        try await withTemporaryDirectory { dir in
            let url = dir.appendingPathComponent("Sample.highland")
            try highlandArchive(fountain: Self.fountain).write(to: url)
            let result = try LaunchImport.parseScript(at: url)
            #expect(result.scenes.map(\.title) == ["INT. KITCHEN - DAY", "EXT. BEACH - NIGHT"])
            #expect(result.title == "The Long Way Home")
        }
    }

    @Test func aScriptWithoutScenesThrowsForEveryFormat() async throws {
        try await withTemporaryDirectory { dir in
            let fountain = try write("Just some notes.\n", as: "Empty.fountain", in: dir)
            let fdx      = try write("<FinalDraft><Content></Content></FinalDraft>", as: "Empty.fdx", in: dir)
            #expect(throws: FountainImportError.self) { try LaunchImport.parseScript(at: fountain) }
            #expect(throws: FountainImportError.self) { try LaunchImport.parseScript(at: fdx) }
        }
    }

    // MARK: - Script → new project

    /// The new project is the New Project template with the parsed scenes as its
    /// Boneyard: same run of empty shoot days, nothing scheduled, the script's title.
    @Test func newProjectFromAScriptHasTheScenesInTheBoneyardAndTheTemplatesDays() {
        let scenes  = [PDFFixture.makeScene(1), PDFFixture.makeScene(2, dayNight: .night)]
        let result  = FountainImportResult(scenes: scenes, totalPages: 1, totalEighths: 8, castList: [], warnings: [], fileName: "S.fountain", title: "Night Shoot")
        let date    = Date(timeIntervalSince1970: 1_700_000_000)
        let project = LaunchImport.newProject(from: result, around: date, calendar: .current)
        let template = ProjectData.newProject(around: date, calendar: .current)

        #expect(project.allScenes == scenes)
        #expect(project.shootDays.map(\.date) == template.shootDays.map(\.date))
        #expect(project.shootDays.allSatisfy { $0.scenes.isEmpty })
        #expect(project.projectTitle == "Night Shoot")
        #expect(project.createdDate == date)
        #expect(project.palette == nil)
    }

    @Test func newProjectFromAScriptWithoutATitleKeepsTheDefault() {
        let result  = FountainImportResult(scenes: [PDFFixture.makeScene(1)], totalPages: 1, totalEighths: 8, castList: [], warnings: [], fileName: "S.fdx", title: nil)
        let project = LaunchImport.newProject(from: result)
        #expect(project.projectTitle == ProjectData.newProject().projectTitle)
    }

    // MARK: - Legacy project → new project

    /// Import Project decodes exactly what the codec decodes, current shape included,
    /// and leaves the source's bytes alone.
    @Test func readsACurrentShapeJSONAsTheCodecDoesAndLeavesTheFileUntouched() async throws {
        try await withTemporaryDirectory { dir in
            let bytes = try ProjectCodec.encode(ProjectCodecTests.project)
            let url   = dir.appendingPathComponent("Old Project.json")
            try bytes.write(to: url)

            let read = try LaunchImport.readLegacyProject(at: url)

            #expect(read == (try ProjectCodec.decode(bytes)))
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    /// The oldest lineage's shape, too. Its decode stamps `createdDate` with now, so the
    /// comparison is field by field (learnings.md, 2026-09-17 #10).
    @Test func readsTheOldestLineagesShapeAndLeavesTheFileUntouched() async throws {
        try await withTemporaryDirectory { dir in
            let bytes = Data(ProjectCodecTests.legacyJSON.utf8)
            let url   = dir.appendingPathComponent("Legacy.json")
            try bytes.write(to: url)

            let read    = try LaunchImport.readLegacyProject(at: url)
            let decoded = try ProjectCodec.decode(bytes)

            #expect(read.allScenes    == decoded.allScenes)
            #expect(read.shootDays    == decoded.shootDays)
            #expect(read.projectTitle == ProjectCodec.legacyProjectTitle)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test func readingAFileThatIsNotAProjectThrows() async throws {
        try await withTemporaryDirectory { dir in
            let url = try write("{ \"not\": \"a project\" }", as: "Other.json", in: dir)
            #expect(throws: (any Error).self) { try LaunchImport.readLegacyProject(at: url) }
        }
    }

    // MARK: - The flow

    @Test func cancellingThePickerThrowsCancellationAndYieldsNoProject() async throws {
        let flow = LaunchImportFlow()
        let task = await startFlow(flow, .script)

        flow.pickerCancelled()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(flow.stage == .idle)
    }

    @Test func aPickerThatReturnsNothingIsACancellation() async throws {
        let flow = LaunchImportFlow()
        let task = await startFlow(flow, .project)

        flow.pickerFinished(.success([]))

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(flow.stage == .idle)
    }

    @Test func aPickedScriptGoesToTheSummaryAndCancellingItYieldsNoProject() async throws {
        try await withTemporaryDirectory { dir in
            let url  = try write(Self.fountain, as: "Sample.fountain", in: dir)
            let flow = LaunchImportFlow()
            let task = await startFlow(flow, .script)

            flow.pickerFinished(.success([url]))
            guard case .reviewing(let result) = flow.stage else {
                Issue.record("expected the summary, got \(flow.stage)")
                return
            }
            #expect(result.scenes.count == 2)

            flow.cancelReview()

            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(flow.stage == .idle)
        }
    }

    @Test func confirmingTheSummaryYieldsTheNewProjectWithTheScenes() async throws {
        try await withTemporaryDirectory { dir in
            let url  = try write(Self.fountain, as: "Sample.fountain", in: dir)
            let flow = LaunchImportFlow()
            let task = await startFlow(flow, .script)

            flow.pickerFinished(.success([url]))
            flow.confirmReview()

            let project = try await task.value
            #expect(project.allScenes.map(\.title) == ["INT. KITCHEN - DAY", "EXT. BEACH - NIGHT"])
            #expect(project.projectTitle == "The Long Way Home")
            #expect(project.shootDays.count == ProjectData.newProject().shootDays.count)
            #expect(flow.stage == .idle)
        }
    }

    @Test func aPickedLegacyProjectYieldsItsProjectWithoutASummary() async throws {
        try await withTemporaryDirectory { dir in
            let bytes = try ProjectCodec.encode(ProjectCodecTests.project)
            let url   = dir.appendingPathComponent("Old.json")
            try bytes.write(to: url)
            let flow = LaunchImportFlow()
            let task = await startFlow(flow, .project)

            flow.pickerFinished(.success([url]))

            let project = try await task.value
            #expect(project == (try ProjectCodec.decode(bytes)))
            #expect(flow.stage == .idle)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test func anUnreadableScriptShowsAFailureWhoseDismissalIsACancellation() async throws {
        try await withTemporaryDirectory { dir in
            let url  = try write("no scenes here", as: "Empty.fountain", in: dir)
            let flow = LaunchImportFlow()
            let task = await startFlow(flow, .script)

            flow.pickerFinished(.success([url]))
            guard case .failed = flow.stage else {
                Issue.record("expected a failure, got \(flow.stage)")
                return
            }

            flow.dismissFailure()

            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(flow.stage == .idle)
        }
    }

    /// A second tap while a flow is waiting cancels the first, so `makeDocument` never
    /// waits on a picker that is no longer up.
    @Test func startingAnotherImportCancelsTheOneWaiting() async throws {
        let flow  = LaunchImportFlow()
        let first = await startFlow(flow, .script)

        let second = Task { try await flow.prepareProject(for: .project) }
        await #expect(throws: CancellationError.self) { try await first.value }
        while flow.stage != .picking(.project) { await Task.yield() }

        flow.pickerCancelled()
        await #expect(throws: CancellationError.self) { try await second.value }
    }
}
