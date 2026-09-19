//
//  ConflictPolicyTests.swift
//  LSVR CineSchedTests
//
//  The conflict policy is a pure decision over the current version and the system's
//  other versions (#15): newest wins, the rest are resolved, the loser is retained for
//  the notice and the restore. These tests pin one row each; reading the versions
//  through the coordinator, flagging them resolved and applying the restore through the
//  funnel are the wiring's.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct ConflictPolicyTests {

    private let noon    = Date(timeIntervalSince1970: 1_700_000_000)
    private let project = ProjectCodecTests.project

    private func version(_ id: String, minutesAfterNoon: Int, device: String? = nil, snapshot: ProjectData? = nil) -> ConflictVersion {
        ConflictVersion(
            id:               id,
            modificationDate: noon.addingTimeInterval(TimeInterval(minutesAfterNoon * 60)),
            deviceName:       device,
            snapshot:         snapshot
        )
    }

    // MARK: - The decision table

    @Test func singleVersionYieldsNoNotice() {
        let current  = version("current", minutesAfterNoon: 0, device: "Matt's Mac")
        let decision = ConflictPolicy.decide(current: current, others: [])
        #expect(decision.winner == current)
        #expect(decision.currentWins)
        #expect(decision.resolved.isEmpty)
        #expect(decision.retained == nil)
        #expect(decision.notice == nil)
    }

    @Test func newerCurrentVersionWinsAndRetainsTheOther() {
        var edited = project
        edited.projectTitle = "The iPad's Way Home"
        let current  = version("current", minutesAfterNoon: 10, device: "Matt's Mac", snapshot: project)
        let other    = version("ipad",    minutesAfterNoon: 5,  device: "Matt's iPad", snapshot: edited)
        let decision = ConflictPolicy.decide(current: current, others: [other])
        #expect(decision.winner == current)
        #expect(decision.currentWins)
        #expect(decision.resolved == ["ipad"])
        #expect(decision.retained == other)
        #expect(decision.retained?.snapshot == edited)
        #expect(decision.notice == ConflictPolicy.Notice(deviceName: "Matt's iPad", modificationDate: other.modificationDate))
    }

    @Test func newerOtherVersionWinsAndRetainsTheCurrent() {
        let current  = version("current", minutesAfterNoon: 0, device: "Matt's Mac", snapshot: project)
        let other    = version("ipad",    minutesAfterNoon: 5, device: "Matt's iPad")
        let decision = ConflictPolicy.decide(current: current, others: [other])
        #expect(decision.winner == other)
        #expect(!decision.currentWins)
        #expect(decision.resolved == ["current"])
        #expect(decision.retained == current)
        #expect(decision.retained?.snapshot == project)
        #expect(decision.notice == ConflictPolicy.Notice(deviceName: "Matt's Mac", modificationDate: current.modificationDate))
    }

    /// Equal dates keep what this device shows.
    @Test func equalDatesKeepTheCurrentVersion() {
        let current  = version("current", minutesAfterNoon: 5, device: "Matt's Mac")
        let other    = version("ipad",    minutesAfterNoon: 5, device: "Matt's iPad")
        let decision = ConflictPolicy.decide(current: current, others: [other])
        #expect(decision.winner == current)
        #expect(decision.currentWins)
        #expect(decision.resolved == ["ipad"])
        #expect(decision.retained == other)
    }

    /// Three versions, the current one oldest: the newest other wins, the current version
    /// is what the notice offers back (this device's own work), and the middle one is
    /// resolved without a notice of its own.
    @Test func threeVersionsResolveToTheNewestAndRetainTheCurrent() {
        let current  = version("current", minutesAfterNoon: 0,  device: "Matt's Mac", snapshot: project)
        let iPad     = version("ipad",    minutesAfterNoon: 20, device: "Matt's iPad")
        let iPhone   = version("iphone",  minutesAfterNoon: 10, device: "Matt's iPhone")
        let decision = ConflictPolicy.decide(current: current, others: [iPhone, iPad])
        #expect(decision.winner == iPad)
        #expect(!decision.currentWins)
        #expect(decision.resolved == ["current", "iphone"])
        #expect(decision.retained == current)
    }

    /// Three versions, the current one newest: the newest of the losers is the one the
    /// notice names.
    @Test func threeVersionsWithTheCurrentNewestRetainTheNewestLoser() {
        let current  = version("current", minutesAfterNoon: 30, device: "Matt's Mac")
        let iPad     = version("ipad",    minutesAfterNoon: 20, device: "Matt's iPad")
        let iPhone   = version("iphone",  minutesAfterNoon: 10, device: "Matt's iPhone")
        let decision = ConflictPolicy.decide(current: current, others: [iPhone, iPad])
        #expect(decision.winner == current)
        #expect(decision.resolved == ["iphone", "ipad"])
        #expect(decision.retained == iPad)
        #expect(decision.notice?.deviceName == "Matt's iPad")
    }

    /// Two others on the same date resolve the same way whatever order the system lists
    /// them in.
    @Test func equalDatesAmongOthersResolveIndependentlyOfOrder() {
        let current  = version("current", minutesAfterNoon: 0)
        let a        = version("a", minutesAfterNoon: 5, device: "A")
        let b        = version("b", minutesAfterNoon: 5, device: "B")
        let forward  = ConflictPolicy.decide(current: current, others: [a, b])
        let backward = ConflictPolicy.decide(current: current, others: [b, a])
        #expect(forward.winner  == a)
        #expect(backward.winner == a)
        #expect(forward.resolved  == ["current", "b"])
        #expect(backward.resolved == ["current", "b"])
        #expect(forward.retained == current)
    }

    /// The tie-break reads the number in the id as a number: the wiring names versions
    /// by their index, and `"version-2"` is the smaller id next to `"version-10"`, though
    /// a plain string compare would put `"version-10"` first.
    @Test func equalDatesAmongOthersBreakTheTieByTheIndexInTheID() {
        let current  = version("current", minutesAfterNoon: 0)
        let second   = version("version-2",  minutesAfterNoon: 5, device: "Second")
        let tenth    = version("version-10", minutesAfterNoon: 5, device: "Tenth")
        #expect(ConflictPolicy.decide(current: current, others: [tenth, second]).winner == second)
        #expect(ConflictPolicy.decide(current: current, others: [second, tenth]).winner == second)
    }

    /// A version is the same version with or without its contents read.
    @Test func versionEqualityIsIdentity() {
        let unread = version("ipad", minutesAfterNoon: 5, device: "Matt's iPad")
        let read   = version("ipad", minutesAfterNoon: 5, device: "Matt's iPad", snapshot: project)
        #expect(unread == read)
        #expect(unread != version("iphone", minutesAfterNoon: 5, device: "Matt's iPad"))
        #expect(unread != version("ipad",   minutesAfterNoon: 6, device: "Matt's iPad"))
    }

    /// A listing that repeats the current version is not a conflict with itself.
    @Test func otherSharingTheCurrentIDIsIgnored() {
        let current  = version("current", minutesAfterNoon: 0)
        let decision = ConflictPolicy.decide(current: current, others: [version("current", minutesAfterNoon: 99)])
        #expect(decision.winner == current)
        #expect(decision.notice == nil)
    }
}
