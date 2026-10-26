import SwiftUI

/// A stored setting paired with the value it reverts to.
///
/// Panes used to spell "unchanged" out twice — once in an `@AppStorage`
/// default and again inside a bespoke Reset button that reset several values at
/// once. Keeping the binding and its default together lets a single row draw
/// its own reset affordance, and lets the section above it aggregate what it
/// owns without knowing how any of it is stored.
struct CrestSettingValue<Value: Equatable> {
    @Binding private var value: Value
    let defaultValue: Value

    init(_ value: Binding<Value>, default defaultValue: Value) {
        _value = value
        self.defaultValue = defaultValue
    }

    var wrappedValue: Value { value }
    var binding: Binding<Value> { $value }
    var isDefault: Bool { value == defaultValue }

    func reset() {
        guard value != defaultValue else { return }
        value = defaultValue
    }

    /// The type-erased face a group or pane aggregates.
    func resettable(_ title: LocalizedStringKey) -> CrestResettableSetting {
        CrestResettableSetting(title: title, isDefault: isDefault, reset: reset)
    }
}

extension CrestSettingValue {
    /// A setting whose default is "unset", such as an accent that follows Space
    /// branding until someone picks a color.
    init<Wrapped: Equatable>(_ value: Binding<Wrapped?>) where Value == Wrapped? {
        self.init(value, default: nil)
    }
}

/// What one control contributes to a Reset: a name, whether it still holds its
/// default, and how to put it back.
struct CrestResettableSetting {
    let title: LocalizedStringKey
    let isDefault: Bool
    let reset: () -> Void

    init(title: LocalizedStringKey, isDefault: Bool, reset: @escaping () -> Void) {
        self.title = title
        self.isDefault = isDefault
        self.reset = reset
    }
}

extension Collection<CrestResettableSetting> {
    /// Whether anything in this collection has moved off its default.
    var isModified: Bool { contains { !$0.isDefault } }

    func resetAll() {
        for setting in self { setting.reset() }
    }
}
