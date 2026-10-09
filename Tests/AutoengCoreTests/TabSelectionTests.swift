import Testing
@testable import AutoengCore

@MainActor
private final class TabTree: TabElementReading {
    var roles: [Int: TabElementRole] = [1: .container, 2: .tabGroup, 3: .tab, 4: .tab, 5: .other]
    var descendants = [1: [2, 5], 2: [3, 4], 5: [99]]
    var groupTabs = [2: [3, 4]]
    var selected: [Int: Bool] = [3: true, 4: false]
    var valueReads: [Int] = []
    var childReads: [Int] = []
    func role(of element: Int) -> TabElementRole { roles[element] ?? .other }
    func children(of element: Int) -> [Int]? { childReads.append(element); return descendants[element] }
    func tabs(of group: Int) -> [Int]? { groupTabs[group] }
    func isSelected(_ tab: Int) -> Bool? { valueReads.append(tab); return selected[tab] }
}

@MainActor
struct TabSelectionTests {
    @Test func readsOnlyTabSelectionAndNeverTerminalContent() {
        let tree = TabTree(); let reader = TabSelectionReader(backend: tree)
        #expect(reader.selection(in: 1)?.tab == 3)
        #expect(Set(tree.valueReads) == [3, 4])
        #expect(!tree.childReads.contains(5))
    }
    @Test func ambiguousOrFailedSelectionDoesNotInventTab() {
        let tree = TabTree(); let reader = TabSelectionReader(backend: tree)
        tree.selected[4] = true
        #expect(reader.selection(in: 1) == nil)
        tree.selected[4] = nil
        #expect(reader.selection(in: 1) == nil)
        tree.selected = [3: false, 4: true]
        #expect(reader.selection(in: 1)?.tab == 4)
    }
    @Test func cyclicTreeAndTooManyTabsAreBounded() {
        let tree = TabTree(); tree.descendants[1] = [1]
        #expect(TabSelectionReader(backend: tree).selection(in: 1) == nil)
        tree.descendants[1] = [2]; tree.groupTabs[2] = Array(repeating: 3, count: 129)
        #expect(TabSelectionReader(backend: tree).selection(in: 1) == nil)
    }
}
