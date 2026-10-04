import Foundation
import Testing
@testable import Core
@testable import Platform

/// One provider backs one quota per bucket.
///
/// Two quotas on the same provider and the same bucket read exactly the same
/// numbers and differ only in how they are divided, so the interface would be
/// showing two panels disagreeing about one set of readings with nothing to tell
/// the user which is the real one. Two quotas on one provider and *different*
/// buckets are a different thing: a provider metering two pools is entitled to a
/// quota per pool, and those read genuinely different numbers.
@Suite("Quota registration")
struct QuotaRegistrationTests {
    private func makeQuota(
        name: String,
        bucketID: String? = nil,
        providerID: String = "mock"
    ) throws -> Quota {
        let start = QuotaFixture.start
        let end = QuotaFixture.end
        return try Quota(
            name: name,
            providerID: try ProviderID(providerID),
            bucketID: bucketID,
            period: try QuotaPeriod(start: start, end: end),
            policy: .even,
            createdAt: start,
            updatedAt: start
        )
    }

    @Test("Creating a quota on a provider and bucket that already has one is refused")
    func createRefusesADuplicate() async throws {
        let repository = QuotaRepository(store: CodableStore.inMemory())
        try await repository.create(makeQuota(name: "First"))

        await #expect(throws: QuotaRegistrationError.self) {
            try await repository.create(makeQuota(name: "Second"))
        }
        #expect(try await repository.all().map(\.name) == ["First"])
    }

    @Test("A refusal names the quota already in the way")
    func duplicateErrorSaysWhich() async throws {
        let repository = QuotaRepository(store: CodableStore.inMemory())
        try await repository.create(makeQuota(name: "First"))

        let error = await #expect(throws: QuotaRegistrationError.self) {
            try await repository.create(makeQuota(name: "Second"))
        }
        // The refusal is shown as one line of text in the creation flow, so a
        // message that does not name the quota already there tells the user
        // nothing about which one to go and remove.
        #expect(error?.errorDescription?.contains("First") == true)
    }

    @Test("A second bucket on one provider is created, not refused")
    func createAcceptsADifferentBucket() async throws {
        let repository = QuotaRepository(store: CodableStore.inMemory())
        try await repository.create(makeQuota(name: "First", bucketID: "models"))

        try await repository.create(makeQuota(name: "Second", bucketID: "requests"))

        #expect(try await repository.all().map(\.name) == ["First", "Second"])
    }

    /// The half of the rule that is not a bucket comparison.
    ///
    /// A quota naming no bucket reads the provider's primary, so it and a quota
    /// naming the primary are two records describing one set of readings. The
    /// repository cannot know which identifier a provider calls primary without a
    /// reading, so the safe direction is taken instead: a quota that names no
    /// bucket is in the way of every quota on its provider, whichever order the
    /// two arrive in.
    @Test("A quota naming no bucket is refused beside any bucket on that provider")
    func unboundBucketIsRefusedEitherWay() async throws {
        let namedFirst = QuotaRepository(store: CodableStore.inMemory())
        try await namedFirst.create(makeQuota(name: "Models", bucketID: "models"))
        await #expect(throws: QuotaRegistrationError.self) {
            try await namedFirst.create(makeQuota(name: "Everything"))
        }
        #expect(try await namedFirst.all().map(\.name) == ["Models"])

        let unboundFirst = QuotaRepository(store: CodableStore.inMemory())
        try await unboundFirst.create(makeQuota(name: "Everything"))
        await #expect(throws: QuotaRegistrationError.self) {
            try await unboundFirst.create(makeQuota(name: "Models", bucketID: "models"))
        }
        #expect(try await unboundFirst.all().map(\.name) == ["Everything"])
    }

    /// Another provider's pools are none of this one's business.
    @Test("A bucket on another provider is not in the way")
    func otherProvidersDoNotConflict() async throws {
        let repository = QuotaRepository(store: CodableStore.inMemory())
        try await repository.create(makeQuota(name: "Models", bucketID: "models"))

        try await repository.create(
            makeQuota(name: "Models", bucketID: "models", providerID: "other")
        )

        #expect(try await repository.all().count == 2)
    }

    @Test("Saving a quota that already exists is still how it is changed")
    func saveStillEdits() async throws {
        // `create` is separate from `save` for exactly this: a policy edit
        // rewrites the record of the quota being edited, and a uniqueness rule
        // applied to every write would refuse the write of the very quota it is
        // protecting.
        let repository = QuotaRepository(store: CodableStore.inMemory())
        let quota = try makeQuota(name: "First")
        try await repository.create(quota)

        let edited = quota.withPolicy(.weekly(weekdayWeights: .weekdaysOnly), updatedAt: quota.updatedAt)
        try await repository.save(edited)

        #expect(try await repository.all().count == 1)
        #expect(try await repository.quota(id: quota.id)?.policy == edited.policy)
    }

    @Test("Deleting a quota frees its provider for a new one")
    func deletingFreesTheProvider() async throws {
        // The other half of the rule: what a user does when they *do* want a
        // second quota on a provider is remove the first one, so that path has
        // to work or the rule is a dead end.
        let repository = QuotaRepository(store: CodableStore.inMemory())
        let first = try makeQuota(name: "First")
        try await repository.create(first)
        try await repository.delete(id: first.id)

        try await repository.create(makeQuota(name: "Second"))

        #expect(try await repository.all().map(\.name) == ["Second"])
    }
}
