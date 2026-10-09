import Carbon
import AutoengCore

@MainActor
final class CarbonInputSourceService: InputSourceService {
    var currentSourceID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return stringProperty(source, kTISPropertyInputSourceID)
    }

    var currentSourceName: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return stringProperty(source, kTISPropertyLocalizedName)
    }

    func availableSources() -> [InputSource] {
        sources().compactMap { source in
            guard let id = stringProperty(source, kTISPropertyInputSourceID),
                  let name = stringProperty(source, kTISPropertyLocalizedName) else { return nil }
            return InputSource(id: id, name: name, languages: languages(source),
                isSelectable: boolProperty(source, kTISPropertyInputSourceIsSelectCapable),
                isEnabled: boolProperty(source, kTISPropertyInputSourceIsEnabled),
                isKeyboard: stringProperty(source, kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String))
        }
    }

    func selectSource(id: String) -> Int32 {
        selectSource(id: id, ifStillValid: { true }) ?? Int32(paramErr)
    }

    func selectSource(id: String, ifStillValid: () -> Bool) -> Int32? {
        // Resolve the source again: the enabled list may change after the menu opens.
        guard let source = sources().first(where: { stringProperty($0, kTISPropertyInputSourceID) == id }) else {
            return Int32(paramErr)
        }
        guard ifStillValid() else { return nil }
        return TISSelectInputSource(source)
    }

    private func sources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return [] }
        return (list as NSArray) as? [TISInputSource] ?? []
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }

    private func languages(_ source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
        let array = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue()
        return (array as NSArray) as? [String] ?? []
    }
}
