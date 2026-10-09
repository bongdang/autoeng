public enum TabElementRole: Equatable {
    case container, tabGroup, tab, other
}

@MainActor
public protocol TabElementReading {
    associatedtype Element: Equatable
    func role(of element: Element) -> TabElementRole
    func children(of element: Element) -> [Element]?
    func tabs(of group: Element) -> [Element]?
    func isSelected(_ tab: Element) -> Bool?
}

@MainActor
public struct TabSelectionReader<Backend: TabElementReading> {
    public let backend: Backend
    public init(backend: Backend) { self.backend = backend }
    public func selection(in root: Backend.Element) -> (group: Backend.Element, tab: Backend.Element)? {
        var pending = [(root, 0)]
        var visited: [Backend.Element] = []
        var result: (group: Backend.Element, tab: Backend.Element)?
        while let (element, depth) = pending.popLast() {
            guard depth <= 6, visited.count < 64 else { return nil }
            if visited.contains(element) { continue }
            visited.append(element)
            switch backend.role(of: element) {
            case .tabGroup:
                guard let tabs = backend.tabs(of: element), !tabs.isEmpty, tabs.count <= 128 else { return nil }
                var selected: Backend.Element?
                for tab in tabs {
                    guard backend.role(of: tab) == .tab, let value = backend.isSelected(tab) else { return nil }
                    if value {
                        guard selected == nil else { return nil }
                        selected = tab
                    }
                }
                guard let selected, result == nil else { return nil }
                result = (element, selected)
            case .container:
                guard let children = backend.children(of: element), children.count <= 64 else { return nil }
                pending.append(contentsOf: children.map { ($0, depth + 1) })
            case .tab, .other: break // Never descend into terminal text or read its value.
            }
        }
        return result
    }
}
