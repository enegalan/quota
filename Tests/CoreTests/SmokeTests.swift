import Testing
@testable import Core

@Suite("Toolchain")
struct SmokeTests {
    @Test("The core target links and runs")
    func coreTargetRuns() {
        // Present so that `swift test` is proven to work before any real logic
        // exists. QuotaDomainError is the first real type in the layer.
        #expect(QuotaDomainError.emptyBuckets.description == "a usage snapshot must carry at least one bucket")
    }
}
