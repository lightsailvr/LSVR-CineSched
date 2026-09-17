// WindowPreference.swift
// View state that belongs to one window but should carry over to the next: Calendar or
// Stripboard, the cast row, page counts vs times, all days on the Stripboard, the
// calendar's grid vs list. With one project per window (#8) these were still @AppStorage,
// so switching one window to the Stripboard switched every open project; two projects side
// by side (story 9 of #1) need their own. A `@WindowPreference` reads its initial value
// from UserDefaults once, holds it as @State for this window, and writes every change back
// as the default the next window opens with, which is what Finder and Xcode do with their
// view settings. Real app preferences (Dark Mode, Theme, Stripboard fields, the DOOD hold
// toggle) stay @AppStorage and apply everywhere at once.

import SwiftUI

@propertyWrapper
struct WindowPreference<Value: WindowPreferenceValue>: DynamicProperty {
    @State private var value: Value
    private let key: String

    /// `State(initialValue:)` only counts the first time the view is installed, so the
    /// defaults read happens once per window however often the view struct is rebuilt.
    init(wrappedValue defaultValue: Value, _ key: String) {
        self.key = key
        _value   = State(initialValue: Value.readWindowPreference(forKey: key) ?? defaultValue)
    }

    var wrappedValue: Value {
        get { value }
        nonmutating set {
            value = newValue
            newValue.writeWindowPreference(forKey: key)
        }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

/// How a value round-trips through UserDefaults for `@WindowPreference`.
protocol WindowPreferenceValue {
    static func readWindowPreference(forKey key: String) -> Self?
    func writeWindowPreference(forKey key: String)
}

extension Bool: WindowPreferenceValue {
    static func readWindowPreference(forKey key: String) -> Bool? {
        UserDefaults.standard.object(forKey: key) as? Bool
    }
    func writeWindowPreference(forKey key: String) {
        UserDefaults.standard.set(self, forKey: key)
    }
}

/// String-backed enums store their raw value, the same representation @AppStorage used
/// for these keys, so a preference set by an earlier build seeds the first window.
extension WindowPreferenceValue where Self: RawRepresentable, RawValue == String {
    static func readWindowPreference(forKey key: String) -> Self? {
        UserDefaults.standard.string(forKey: key).flatMap(Self.init(rawValue:))
    }
    func writeWindowPreference(forKey key: String) {
        UserDefaults.standard.set(rawValue, forKey: key)
    }
}

extension ScheduleViewMode: WindowPreferenceValue {}
extension CalendarViewMode: WindowPreferenceValue {}
