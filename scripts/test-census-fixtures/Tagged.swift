// A fixture for scripts/test-census.sh --self-test. Never compiled, never part of a
// package, never run: it exists to be counted.
//
// Every shape here is one the scan has to get right. What each one must count as is in
// expected.txt beside its line number, so a shape that quietly stops being recognised
// fails the self-test as loudly as one counted twice.

import Testing

/// A suite may carry a tag of its own. That is not a test, and must not be counted as
/// one.
@Suite("A tagged suite", .tags(.unit))
struct TaggedSuite {

    @Test("football · Rule 0-0-0 · the plainest shape", .tags(.football))
    func football() {}

    @Test("contract: the second plainest", .tags(.contract))
    func contract() {}

    @Test("unit: and the third", .tags(.unit))
    func unit() {}

    @Test("pin · pinned because the fixture needs one of these", .tags(.pin))
    func pinned() {}

    /// A display name too long to sit on one line puts the attribute over several, which
    /// is the shape swift-format leaves behind and the reason the scan balances
    /// parentheses rather than reading a line.
    @Test(
        "football · Rule 0-0-1 · an attribute spread over more than one line is one test",
        .tags(.football)
    )
    func multiLineAttribute() {}

    /// A parameterised test is one `@Test`, whatever it is handed.
    @Test(
        "unit: a parameterised test counts once, not once per argument",
        .tags(.unit),
        arguments: [1, 2, 3])
    func parameterised(value: Int) {}

    /// Prose about a `@Test` is not a test: this line names one and must not be counted.
    @Test("unit: a doc comment above it naming @Test does not add a test", .tags(.unit))
    func docCommentMentionsTheAttribute() {}

    @Test("unit: a string holding the attribute does not add a test", .tags(.unit))
    func multiLineStringHoldingTheAttribute() {
        let sample = """
            @Test("this line begins with the attribute but is inside a string")
            func notATest() {}
            """
        _ = sample
    }
}

/*
@Test("A commented-out test is not a test", .tags(.unit))
func insideABlockComment() {}
*/

/// A struct with no `@Suite` still groups its tests, under the type's own name.
struct BareStruct {

    @Test("unit: a test in a struct with no @Suite attribute", .tags(.unit))
    func inABareStruct() {}
}
