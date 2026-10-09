import Foundation
import Testing
@testable import AutoengCore

@MainActor
struct SettingsStoreTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "local.autoeng.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func freshInstallHasDefaultTargetsAndNoChosenSource() {
        withDefaults { defaults in
            let settings = SettingsStore(defaults: defaults).load()
            #expect(settings.englishSourceID == nil)
            #expect(settings.targetBundleIDs == ["com.googlecode.iterm2", "com.apple.Terminal"])
            #expect(!settings.isPaused)
        }
    }

    @Test func reloadPreservesSourceTargetsAndPause() throws {
        try withDefaults { defaults in
            let expected = AppSettings(englishSourceID: "com.apple.keylayout.ABC", targetBundleIDs: ["com.apple.Terminal"], isPaused: true)
            try SettingsStore(defaults: defaults).save(expected)
            #expect(SettingsStore(defaults: defaults).load() == expected)
        }
    }

    @Test func disabledAllTargetsRemainsEmptyOnReload() throws {
        try withDefaults { defaults in
            try SettingsStore(defaults: defaults).save(AppSettings(targetBundleIDs: []))
            #expect(SettingsStore(defaults: defaults).load().targetBundleIDs.isEmpty)
        }
    }

    @Test(arguments: [Data("broken".utf8), Data("{\"englishSourceID\":42}".utf8)])
    func corruptSettingsUseDefaults(data: Data) {
        withDefaults { defaults in
            defaults.set(data, forKey: SettingsStore.storageKey)
            #expect(SettingsStore(defaults: defaults).load() == AppSettings())
        }
    }

    @Test func removedSourceIDIsPreservedForVisibleError() throws {
        try withDefaults { defaults in
            try SettingsStore(defaults: defaults).save(AppSettings(englishSourceID: "removed"))
            #expect(SettingsStore(defaults: defaults).load().englishSourceID == "removed")
        }
    }

    @Test func emptySourceIDIsNormalizedToUnconfigured() throws {
        try withDefaults { defaults in
            try SettingsStore(defaults: defaults).save(AppSettings(englishSourceID: ""))
            #expect(SettingsStore(defaults: defaults).load().englishSourceID == nil)
        }
    }
}
