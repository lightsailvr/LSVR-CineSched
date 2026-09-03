//
//  DayTypeTests.swift
//  LSVR CineSchedTests
//
//  Day types replace the old `isBlackout` flag on ShootDay. These tests pin down the file
//  compatibility rules (old files still open, old builds still see unavailable days) and
//  production day numbering. Stripboard row behaviour lives in StripboardRowsTests.
//

import Foundation
import Testing
@testable import LSVR_CineSched

struct DayTypeTests {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ day: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day))!
    }

    private func scene(_ n: Int) -> Scene {
        Scene(title: "INT. ROOM - DAY", sceneNumber: "\(n)")
    }

    /// Encodes a day, then lets the caller rewrite the raw JSON object before decoding it
    /// back, which is how "a file written by an older build" is simulated below.
    private func reencode(_ day: ShootDay, editing: (inout [String: Any]) -> Void) throws -> ShootDay {
        let data = try JSONEncoder().encode(day)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        editing(&json)
        let edited = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(ShootDay.self, from: edited)
    }

    // MARK: - File compatibility

    @Test func dayTypeAndNoteRoundTrip() throws {
        let original = ShootDay(date: date(3), dayType: .travel, dayNote: "Fly LAX → ABQ")
        let decoded = try reencode(original) { _ in }
        #expect(decoded.dayType == .travel)
        #expect(decoded.dayNote == "Fly LAX → ABQ")
        #expect(decoded.isBlackout == false)
    }

    @Test func legacyBlackoutFileDecodesAsUnavailable() throws {
        // A file from before day types: no `dayType`/`dayNote` keys, only `isBlackout`.
        let decoded = try reencode(ShootDay(date: date(3))) { json in
            json.removeValue(forKey: "dayType")
            json.removeValue(forKey: "dayNote")
            json["isBlackout"] = true
        }
        #expect(decoded.dayType == .unavailable)
        #expect(decoded.isBlackout == true)
        #expect(decoded.dayNote == "")
    }

    @Test func legacyFileWithoutBlackoutDecodesAsShoot() throws {
        let decoded = try reencode(ShootDay(date: date(3))) { json in
            json.removeValue(forKey: "dayType")
            json.removeValue(forKey: "dayNote")
            json.removeValue(forKey: "isBlackout")
        }
        #expect(decoded.dayType == .shoot)
    }

    @Test func dayTypeWinsOverLegacyFlagWhenBothPresent() throws {
        // A newer build wrote `dayType: travel` plus `isBlackout: false`; an in-between edit
        // that flipped only the legacy flag must not downgrade the typed value.
        let decoded = try reencode(ShootDay(date: date(3), dayType: .travel)) { json in
            json["isBlackout"] = true
        }
        #expect(decoded.dayType == .travel)
    }

    @Test func unknownDayTypeFallsBackToShootInsteadOfFailing() throws {
        let decoded = try reencode(ShootDay(date: date(3))) { json in
            json["dayType"] = "lunarEclipse"
        }
        #expect(decoded.dayType == .shoot)
    }

    @Test func encoderStillWritesLegacyBlackoutFlagForOlderBuilds() throws {
        let unavailable = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(ShootDay(date: date(3), dayType: .unavailable))) as! [String: Any]
        #expect(unavailable["isBlackout"] as? Bool == true)
        #expect(unavailable["dayType"] as? String == "unavailable")

        let travel = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(ShootDay(date: date(3), dayType: .travel))) as! [String: Any]
        #expect(travel["isBlackout"] as? Bool == false)
    }

    @Test func legacyInitParameterMapsToUnavailable() {
        #expect(ShootDay(date: date(1), isBlackout: true).dayType == .unavailable)
        #expect(ShootDay(date: date(1), isBlackout: false).dayType == .shoot)
    }

    // MARK: - Day numbering

    @Test func nonShootDayTypesNeverEarnAProductionDayNumber() {
        let days = [
            ShootDay(date: date(1), scenes: [scene(1)]),
            ShootDay(date: date(2), scenes: [scene(2)], dayType: .travel),      // scenes, but travel
            ShootDay(date: date(3), dayType: .holiday),
            ShootDay(date: date(4), scenes: [scene(3)], dayType: .unavailable),
            ShootDay(date: date(5), scenes: [scene(4)]),
        ]
        let numbers = productionDayNumbers(for: days)
        #expect(numbers[days[0].id] == 1)
        #expect(numbers[days[1].id] == nil)
        #expect(numbers[days[2].id] == nil)
        #expect(numbers[days[3].id] == nil)
        #expect(numbers[days[4].id] == 2)
    }

}
