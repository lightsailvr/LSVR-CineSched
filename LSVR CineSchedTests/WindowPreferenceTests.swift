//
//  WindowPreferenceTests.swift
//  LSVR CineSchedTests
//
//  `@WindowPreference` is per-window view state seeded from, and written back to, the
//  last-used value in UserDefaults (#8). The SwiftUI half is the wrapper's @State; the
//  half that can be pinned is the defaults round trip, in the representation @AppStorage
//  used for the same keys so an earlier build's setting seeds the first window.
//

import Foundation
import Testing
@testable import LSVR_CineSched

@MainActor
struct WindowPreferenceTests {

    private func withKey(_ body: (String) -> Void) {
        let key = "WindowPreferenceTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        body(key)
    }

    @Test func aMissingKeySeedsNothing() {
        withKey { key in
            #expect(Bool.readWindowPreference(forKey: key) == nil)
            #expect(ScheduleViewMode.readWindowPreference(forKey: key) == nil)
        }
    }

    @Test func boolsRoundTrip() {
        withKey { key in
            true.writeWindowPreference(forKey: key)
            #expect(Bool.readWindowPreference(forKey: key) == true)
            false.writeWindowPreference(forKey: key)
            #expect(Bool.readWindowPreference(forKey: key) == false)
        }
    }

    @Test func enumsStoreTheirRawValueLikeAppStorageDid() {
        withKey { key in
            ScheduleViewMode.stripboard.writeWindowPreference(forKey: key)
            #expect(UserDefaults.standard.string(forKey: key) == "Stripboard")
            #expect(ScheduleViewMode.readWindowPreference(forKey: key) == .stripboard)

            UserDefaults.standard.set("shootDaysOnly", forKey: key)
            #expect(CalendarViewMode.readWindowPreference(forKey: key) == .shootDaysOnly)

            UserDefaults.standard.set("not a mode", forKey: key)
            #expect(ScheduleViewMode.readWindowPreference(forKey: key) == nil)
        }
    }
}
