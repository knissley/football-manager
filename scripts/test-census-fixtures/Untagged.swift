// The other half of the fixture for scripts/test-census.sh --self-test: the tests the
// census must refuse. Never compiled, never part of a package.

import Testing

@Suite("A suite with untagged tests")
struct UntaggedSuite {

    @Test("A test with a name and no tags at all")
    func noTags() {}

    /// The bare attribute, with no parentheses to put a trait in.
    @Test
    func bareAttribute() {}

    /// Traits, but none of them a kind.
    @Test("A test with a trait that is not a kind", .serialized)
    func aTraitButNoKind() {}

    /// Two kinds is as wrong as none: a test is one of them.
    @Test("A test claiming to be two kinds at once", .tags(.football, .unit))
    func twoKinds() {}
}
