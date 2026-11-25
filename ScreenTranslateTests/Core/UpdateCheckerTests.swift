import Testing
@testable import ScreenTranslate

struct UpdateCheckerTests {
    @Test func normalizedVersionStripsPrefixAndPreReleaseSuffix() {
        #expect(UpdateChecker.normalizedVersion("v0.1.5-beta") == "0.1.5")
        #expect(UpdateChecker.normalizedVersion("V1.2.0-local") == "1.2.0")
        #expect(UpdateChecker.normalizedVersion("0.1.4") == "0.1.4")
    }

    @Test func semanticVersionComparison() {
        #expect(UpdateChecker.isNewer("v0.1.5-beta", than: "0.1.4"))
        #expect(UpdateChecker.isNewer("v0.2.0", than: "0.1.9"))
        #expect(UpdateChecker.isNewer("1.0.0", than: "0.9.9"))
        #expect(!UpdateChecker.isNewer("v0.1.4-beta", than: "0.1.4"))
        #expect(!UpdateChecker.isNewer("v0.1.3-beta", than: "0.1.4"))
    }
}
