// A fixture for the first structural exception: never compiled, scanned only by
// scripts/lint-sim.sh --self-test.

import Testing

struct PinFixtureTests {
    /// Pins the crude resolver's single tackler, and names the issue that
    /// replaces the reading (#39). Exempt: the doc comment on a pinned test.
    @Test(
        "pin · a tackle is made by one man",
        .tags(.pin)
    )
    func oneTackler() {}

    /// The same sentence on a test that is not pinned fails (#39).
    @Test("the clock starts on the snap, 4-3-2", .tags(.football))
    func clockStarts() {}

    // MARK: - A section marker is not a doc comment, so this fails (#39)

    /// Exempt, and the exemption reaches the whole doc comment rather than the
    /// line touching the attribute: this second line names #39 as well.
    @Test("pin · the whole doc comment", .tags(.pin))
    func wholeDocComment() {}
}
