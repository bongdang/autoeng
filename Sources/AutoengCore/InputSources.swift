import Foundation

public struct InputSource: Equatable, Sendable {
    public let id: String
    public let name: String
    public let languages: [String]
    public let isSelectable: Bool
    public let isEnabled: Bool
    public let isKeyboard: Bool

    public init(id: String, name: String, languages: [String], isSelectable: Bool = true,
                isEnabled: Bool = true, isKeyboard: Bool = true) {
        self.id = id; self.name = name; self.languages = languages
        self.isSelectable = isSelectable; self.isEnabled = isEnabled; self.isKeyboard = isKeyboard
    }

    public var isEnglishCandidate: Bool {
        isKeyboard && isEnabled && isSelectable && languages.contains {
            $0.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first == "en"
        }
    }
}

@MainActor
public protocol InputSourceService: AnyObject {
    func availableSources() -> [InputSource]
    var currentSourceID: String? { get }
    func selectSource(id: String) -> Int32
    func selectSource(id: String, ifStillValid: () -> Bool) -> Int32?
}

public extension InputSourceService {
    func selectSource(id: String, ifStillValid: () -> Bool) -> Int32? {
        guard ifStillValid() else { return nil }
        return selectSource(id: id)
    }
}

public enum InputSwitchResult: Equatable, Sendable {
    case noTarget
    case unavailable(String)
    case ineligible(String)
    case selectionFailed(Int32)
    case verificationFailed(expected: String, actual: String?)
    case alreadySelected
    case switched
    case cancelled
}

@MainActor
public final class InputSourceSwitcher {
    private let service: any InputSourceService
    public init(service: any InputSourceService) { self.service = service }
    public var currentSourceID: String? { service.currentSourceID }
    public var englishSources: [InputSource] {
        service.availableSources().filter(\.isEnglishCandidate).sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }
    }
    public func switchToEnglish(id: String?, ifStillValid: () -> Bool = { true }) -> InputSwitchResult {
        guard let id, !id.isEmpty else { return .noTarget }
        let initialSource = service.currentSourceID
        guard let source = service.availableSources().first(where: { $0.id == id }) else {
            return .unavailable(id)
        }
        guard source.isEnglishCandidate else { return .ineligible(id) }
        guard ifStillValid(), service.currentSourceID == initialSource else { return .cancelled }
        guard initialSource != id else { return .alreadySelected }
        guard let status = service.selectSource(id: id, ifStillValid: {
            // Focus validation may itself perform IPC: check the input source afterwards.
            ifStillValid() && self.service.currentSourceID == initialSource
        }) else { return .cancelled }
        guard status == 0 else { return .selectionFailed(status) }
        let actual = service.currentSourceID
        guard actual == id else { return .verificationFailed(expected: id, actual: actual) }
        return .switched
    }
}
