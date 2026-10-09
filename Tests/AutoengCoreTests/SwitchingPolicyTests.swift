import Testing
@testable import AutoengCore

struct SwitchingPolicyTests {
    @Test func tabMoveSwitchesOnceAndObservationRecoveryDoesNotSwitch() {
        var subject = SwitchingPolicy(targetBundleIDs: ["com.googlecode.iterm2"])
        func tab(_ value: Int?) -> FocusContext {
            FocusContext(bundleID: "com.googlecode.iterm2", processID: 10, windowID: 1, tabID: value)
        }
        let tabResult1 = subject.shouldSwitch(to: tab(1))
        #expect(tabResult1)
        let tabResult2 = !subject.shouldSwitch(to: tab(1))
        #expect(tabResult2)
        let tabResult3 = subject.shouldSwitch(to: tab(2))
        #expect(tabResult3)
        let tabResult4 = !subject.shouldSwitch(to: tab(2))
        #expect(tabResult4)
        let tabResult5 = !subject.shouldSwitch(to: tab(nil))
        #expect(tabResult5)
        let tabResult6 = !subject.shouldSwitch(to: tab(3))
        #expect(tabResult6)
        let tabResult7 = subject.shouldSwitch(to: tab(1))
        #expect(tabResult7)
        subject.isPaused = true
        let tabResult8 = !subject.shouldSwitch(to: tab(2))
        #expect(tabResult8)
    }
    private let terminal = "com.apple.Terminal"
    private let browser = FocusContext(bundleID: "com.apple.Safari", processID: 90)

    private func context(_ pid: Int32 = 10, window: Int? = 1) -> FocusContext {
        FocusContext(bundleID: terminal, processID: pid, windowID: window)
    }

    private func policy() -> SwitchingPolicy {
        SwitchingPolicy(targetBundleIDs: [terminal])
    }

    @Test func testInitialTargetFocusAppliesRule() {
        var subject = policy()
        let result1 = subject.shouldSwitch(to: context())
        #expect(result1)
    }

    @Test func testNonTargetDoesNotApplyRule() {
        var subject = policy()
        let result2 = !subject.shouldSwitch(to: browser)
        #expect(result2)
        let result3 = !subject.shouldSwitch(to: nil)
        #expect(result3)
    }

    @Test func testDuplicateFocusDoesNotOverrideManualKoreanSelection() {
        var subject = policy()
        let result4 = subject.shouldSwitch(to: context())
        #expect(result4)
        let result5 = !subject.shouldSwitch(to: context())
        #expect(result5)
    }

    @Test func testDifferentProcessWithSameBundleAppliesRule() {
        var subject = policy()
        let result6 = subject.shouldSwitch(to: context(10))
        #expect(result6)
        let result7 = subject.shouldSwitch(to: context(11))
        #expect(result7)
    }

    @Test func testDifferentWindowInSameProcessAppliesRule() {
        var subject = policy()
        let result8 = subject.shouldSwitch(to: context(window: 1))
        #expect(result8)
        let result9 = subject.shouldSwitch(to: context(window: 2))
        #expect(result9)
    }

    @Test func testReturnToSameWindowAfterOtherAppAppliesRule() {
        var subject = policy()
        let result10 = subject.shouldSwitch(to: context())
        #expect(result10)
        let result11 = !subject.shouldSwitch(to: browser)
        #expect(result11)
        let result12 = subject.shouldSwitch(to: context())
        #expect(result12)
    }

    @Test func testMissingForegroundClearsPreviousFocus() {
        var subject = policy()
        let result13 = subject.shouldSwitch(to: context())
        #expect(result13)
        let result14 = !subject.shouldSwitch(to: nil)
        #expect(result14)
        let result15 = subject.shouldSwitch(to: context())
        #expect(result15)
    }

    @Test func testPauseSuppressesBothAppAndWindowSwitches() {
        var subject = policy()
        subject.isPaused = true
        let result16 = !subject.shouldSwitch(to: context())
        #expect(result16)
        let result17 = !subject.shouldSwitch(to: context(window: 2))
        #expect(result17)
    }

    @Test func testResumeAppliesCurrentTargetExactlyOnce() {
        var subject = policy()
        let result18 = subject.shouldSwitch(to: context())
        #expect(result18)
        subject.isPaused = true
        let result19 = !subject.shouldSwitch(to: context())
        #expect(result19)
        let result20 = subject.resume(at: context())
        #expect(result20)
        let result21 = !subject.isPaused
        #expect(result21)
        let result22 = !subject.shouldSwitch(to: context())
        #expect(result22)
    }

    @Test func testResumeInOtherAppDoesNotApplyRule() {
        var subject = policy()
        subject.isPaused = true
        let result23 = !subject.resume(at: browser)
        #expect(result23)
        let result24 = !subject.isPaused
        #expect(result24)
        let result25 = subject.shouldSwitch(to: context())
        #expect(result25)
    }

    @Test func testDiscoveringWindowAfterAppActivationIsNotSecondEntry() {
        var subject = policy()
        let result26 = subject.shouldSwitch(to: context(window: nil))
        #expect(result26)
        let result27 = !subject.shouldSwitch(to: context(window: 1))
        #expect(result27)
        let result28 = subject.shouldSwitch(to: context(window: 2))
        #expect(result28)
    }

    @Test func testTemporarilyUnavailableWindowDoesNotCauseRepeatSwitch() {
        var subject = policy()
        let result29 = subject.shouldSwitch(to: context(window: 1))
        #expect(result29)
        let result30 = !subject.shouldSwitch(to: context(window: nil))
        #expect(result30)
        let result31 = !subject.shouldSwitch(to: context(window: 1))
        #expect(result31)
        let result32 = subject.shouldSwitch(to: context(window: 2))
        #expect(result32)
    }

    @Test func testTerminatedProcessDoesNotKeepStaleFocus() {
        var subject = policy()
        let result33 = subject.shouldSwitch(to: context())
        #expect(result33)
        subject.processTerminated(10)
        let result34 = subject.shouldSwitch(to: context())
        #expect(result34)
    }

    @Test func testOtherProcessTerminationDoesNotResetCurrentFocus() {
        var subject = policy()
        let result35 = subject.shouldSwitch(to: context())
        #expect(result35)
        subject.processTerminated(11)
        let result36 = !subject.shouldSwitch(to: context())
        #expect(result36)
    }

    @Test func testDisabledTargetDoesNotApplyRuleOnNextEntry() {
        var subject = policy()
        let result37 = subject.shouldSwitch(to: context())
        #expect(result37)
        subject.targetBundleIDs.remove(terminal)
        let result38 = !subject.shouldSwitch(to: browser)
        #expect(result38)
        let result39 = !subject.shouldSwitch(to: context())
        #expect(result39)
    }
}
