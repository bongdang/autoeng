import Testing
@testable import AutoengCore

@MainActor
private final class FakeInputSources: InputSourceService {
    var sources = [InputSource(id: "abc", name: "ABC", languages: ["en"])]
    var currentSourceID: String? = "korean"
    var status: Int32 = 0
    var updatesSelection = true
    var selections: [String] = []
    func availableSources() -> [InputSource] { sources }
    func selectSource(id: String) -> Int32 {
        selections.append(id)
        if status == 0 && updatesSelection { currentSourceID = id }
        return status
    }
}

@MainActor
struct InputSourceTests {
    @Test func successfulSwitchSelectsExactIDAndVerifiesState() {
        let service = FakeInputSources()
        let result = InputSourceSwitcher(service: service).switchToEnglish(id: "abc")
        #expect(result == .switched)
        #expect(service.selections == ["abc"])
        #expect(service.currentSourceID == "abc")
    }

    @Test func alreadySelectedDoesNotCallAPI() {
        let service = FakeInputSources()
        service.currentSourceID = "abc"
        let result = InputSourceSwitcher(service: service).switchToEnglish(id: "abc")
        #expect(result == .alreadySelected)
        #expect(service.selections.isEmpty)
    }

    @Test func missingTargetDoesNotChooseFallback() {
        let service = FakeInputSources()
        let result = InputSourceSwitcher(service: service).switchToEnglish(id: nil)
        #expect(result == .noTarget)
        #expect(service.selections.isEmpty)
    }

    @Test func removedSourceDoesNotChooseFallback() {
        let service = FakeInputSources()
        let result = InputSourceSwitcher(service: service).switchToEnglish(id: "removed")
        #expect(result == .unavailable("removed"))
        #expect(service.selections.isEmpty)
    }

    @Test(arguments: ["disabled", "unselectable", "nonEnglish", "nonKeyboard"])
    func invalidSourcesAreRejected(reason: String) {
        let service = FakeInputSources()
        service.sources = [InputSource(id: "abc", name: "ABC", languages: reason == "nonEnglish" ? ["ko"] : ["en"],
            isSelectable: reason != "unselectable", isEnabled: reason != "disabled", isKeyboard: reason != "nonKeyboard")]
        let result = InputSourceSwitcher(service: service).switchToEnglish(id: "abc")
        #expect(result == .ineligible("abc"))
        #expect(service.selections.isEmpty)
    }

    @Test func selectionFailureKeepsStatusAndDoesNotRetry() {
        let service = FakeInputSources()
        service.status = -50
        let result = InputSourceSwitcher(service: service).switchToEnglish(id: "abc")
        #expect(result == .selectionFailed(-50))
        #expect(service.selections == ["abc"])
    }

    @Test(arguments: ["korean", nil] as [String?])
    func successStatusWithWrongActualSourceIsFailure(actual: String?) {
        let service = FakeInputSources()
        service.currentSourceID = actual
        service.updatesSelection = false
        let result = InputSourceSwitcher(service: service).switchToEnglish(id: "abc")
        #expect(result == .verificationFailed(expected: "abc", actual: actual))
        #expect(service.selections == ["abc"])
    }

    @Test func englishListUsesLanguageMetadataAndEligibility() {
        let service = FakeInputSources()
        service.sources = [
            InputSource(id: "us", name: "U.S.", languages: ["en-US"]),
            InputSource(id: "abc", name: "ABC", languages: ["en"]),
            InputSource(id: "gb", name: "British", languages: ["en_GB"]),
            InputSource(id: "fr", name: "ASCII-capable French", languages: ["fr"]),
            InputSource(id: "ko", name: "English misleading name", languages: ["ko"]),
            InputSource(id: "unknown", name: "ABC", languages: []),
            InputSource(id: "disabled", name: "ABC", languages: ["en"], isEnabled: false)
        ]
        let ids = Set(InputSourceSwitcher(service: service).englishSources.map(\.id))
        #expect(ids == ["us", "abc", "gb"])
    }

    @Test func sourceRemovalAfterListingIsCheckedAgain() {
        let service = FakeInputSources()
        let switcher = InputSourceSwitcher(service: service)
        #expect(switcher.englishSources.count == 1)
        service.sources = []
        let result = switcher.switchToEnglish(id: "abc")
        #expect(result == .unavailable("abc"))
        #expect(service.selections.isEmpty)
    }
}
