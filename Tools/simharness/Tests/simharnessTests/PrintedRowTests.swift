import Testing

@testable import simharness

/// What a printed row says, against what the harness graded.
///
/// The grade is taken on the unrounded value with the endpoints in the band, and the
/// table prints a rounded one. Where the two disagree the row is unreadable: a value
/// printed as its band's endpoint sits within half a display unit of it and can be on
/// either side, so the reader cannot arrive at the verdict printed beside it. These
/// assert that the printed value and the printed band, read on their own, give the
/// verdict — which is the property the whole calibration argument rests on, because a
/// reviewer comparing two runs reads the table and not the doubles behind it.
@Suite("Printed precision")
struct PrintedRowTests {

    /// A one-decimal row with a band whose endpoints are exact at that precision.
    private let row = CalibrationTarget(
        id: "t", label: "t", low: 1.3, high: 1.8, season: .season(2025), source: "s",
        rulesSensitiveTo: [], gate: true, decimals: 1)

    @Test(
        "unit: a value above the band that rounds onto the ceiling prints the digits that put it outside",
        .tags(.unit))
    func aboveTheCeiling() {
        let shown = row.printed(1.84, inBand: false)
        #expect(shown.value == "1.84")
        #expect(shown.band == "1.30-1.80")
    }

    @Test(
        "unit: a value below the band that rounds onto the floor prints the digits that put it outside",
        .tags(.unit))
    func belowTheFloor() {
        let shown = row.printed(1.26, inBand: false)
        #expect(shown.value == "1.26")
        #expect(shown.band == "1.30-1.80")
    }

    /// The endpoint is in the band (`>=`, `<=`), so a value that *is* the endpoint is `ok`
    /// and printing it as the endpoint says exactly that. This is the case the widening
    /// must leave alone: there are no digits that would separate the two, and adding any
    /// would suggest a gap that is not there.
    @Test(
        "unit: a value exactly on an endpoint prints the row's own precision, and reads as in band",
        .tags(.unit))
    func exactlyOnAnEndpoint() {
        let top = row.printed(1.8, inBand: true)
        #expect(top.value == "1.8")
        #expect(top.band == "1.3-1.8")
        let floor = row.printed(1.3, inBand: true)
        #expect(floor.value == "1.3")
        #expect(floor.band == "1.3-1.8")
    }

    /// Inside the band a tie reads correctly on its own — "at the endpoint" and "in band"
    /// agree — so the row keeps its own precision and the table stays as narrow as it was.
    @Test(
        "unit: a value inside the band that rounds onto an endpoint keeps the row's precision",
        .tags(.unit))
    func insideTheBandRoundingOntoAnEndpoint() {
        #expect(row.printed(1.78, inBand: true).value == "1.8")
        #expect(row.printed(1.32, inBand: true).value == "1.3")
    }

    /// An endpoint can carry more precision than its row prints, and then widening the
    /// value alone makes the line worse rather than better: 1.58 against a band printed
    /// `1.3-1.6` reads as in band while the grade says otherwise. Value and band widen
    /// together for that reason.
    @Test(
        "unit: the band widens with the value, so an endpoint finer than the row's precision is readable too",
        .tags(.unit))
    func theBandWidensWithTheValue() {
        let fine = CalibrationTarget(
            id: "f", label: "f", low: 1.3, high: 1.55, season: .season(2025), source: "s",
            rulesSensitiveTo: [], gate: true, decimals: 1)
        let shown = fine.printed(1.58, inBand: false)
        #expect(shown.value == "1.58")
        #expect(shown.band == "1.30-1.55")
    }

    @Test(
        "unit: one more decimal is not always enough, and the row keeps adding until the value is off the endpoint",
        .tags(.unit))
    func twoMoreDecimals() {
        let shown = row.printed(1.801, inBand: false)
        #expect(shown.value == "1.801")
        #expect(shown.band == "1.300-1.800")
    }

    /// The widening is bounded, because a column has to end somewhere. Eight decimals
    /// separates every rate the harness measures from an endpoint it is not on — each is a
    /// ratio of integer counts, so a value that is not the endpoint differs from it by at
    /// least one part in the denominator times the endpoint's own hundredth, about two
    /// parts in ten million for the fifty-odd thousand plays a 400-game run takes. A pair
    /// that still ties here is two numbers a billionth apart.
    @Test("unit: the widening stops at eight decimals", .tags(.unit))
    func theWideningIsBounded() {
        let shown = row.printed(1.8 + 1e-12, inBand: false)
        #expect(shown.value == "1.80000000")
        #expect(shown.band == "1.30000000-1.80000000")
    }

    /// The reproducer this was found from: two 400-game runs, two trees apart, both
    /// printing `1.8` for `kneels per game` against a band of 1.3–1.8, one graded `OFF`
    /// and one graded `ok`. Neither tree is needed to check the fix — the verdict and the
    /// printed value bound the measurement on each side, and kneels per game is a count
    /// over 400 games, so each is a multiple of 1/400 in its interval. Every value on the
    /// `OFF` side must now print as something other than `1.8`; every value on the `ok`
    /// side still prints `1.8`, which is what makes the two runs tell apart.
    @Test(
        "unit: the two runs that both printed 1.8 for kneels per game, one ok and one OFF, no longer print the same number",
        .tags(.unit))
    func theKneelsReproducer() {
        guard let kneels = CalibrationTarget.all.first(where: { $0.id == "kneelsPerGame" }) else {
            Issue.record("kneelsPerGame is no longer a row")
            return
        }
        #expect(
            kneels.low == 1.3 && kneels.high == 1.8 && kneels.decimals == 1,
            "the band the two captures were graded against has moved; re-read them before trusting this"
        )
        for step in 1...19 {
            let above = 1.8 + Double(step) / 400
            #expect(
                kneels.printed(above, inBand: false).value != "1.8",
                "an OFF run at \(above) still prints what the ok run prints")
        }
        for step in 0...20 {
            let within = 1.8 - Double(step) / 400
            #expect(
                kneels.printed(within, inBand: true).value == "1.8",
                "an ok run at \(within) no longer prints the value it printed")
        }
    }

    /// A row the grade did not read against its band — sourced under another rulebook, or
    /// unsourced — has no verdict for a printed value to agree or disagree with, so it
    /// prints exactly what it printed before.
    @Test(
        "contract: a row the grade did not read against its band prints the row's own precision",
        .tags(.contract))
    func ungradedRowsAreUntouched() {
        for value in [1.8, 1.84, 1.26, 1.3] {
            let shown = row.printed(value, inBand: nil)
            #expect(shown.value == row.format(value))
            #expect(shown.band == row.band)
        }
    }

    /// The property, over the real table rather than a fixture: for every band in
    /// `Targets.swift`, at values placed a quarter, a half and three-quarters of a display
    /// unit either side of each endpoint and on the endpoint itself, the verdict a reader
    /// takes from the two printed numbers is the verdict the harness took from the
    /// unrounded one. `report` grades `value >= low && value <= high`; so does this.
    @Test(
        "contract: a graded row's printed value, read against its printed band, gives the verdict the harness graded",
        .tags(.contract))
    func thePrintedLineImpliesTheVerdict() {
        for target in CalibrationTarget.all {
            guard let low = target.low, let high = target.high else { continue }
            var step = 1.0
            for _ in 0..<target.decimals { step /= 10 }
            for edge in [low, high] {
                for quarters in [-3, -2, -1, 0, 1, 2, 3] {
                    let value = edge + Double(quarters) * step / 4
                    let inBand = value >= low && value <= high
                    let shown = target.printed(value, inBand: inBand)
                    let printed = shown.value.dropLast(target.unit.count)
                    let bounds = shown.band.split(separator: "-")
                    guard bounds.count == 2, let read = Double(printed),
                        let readLow = Double(bounds[0]), let readHigh = Double(bounds[1])
                    else {
                        Issue.record("\(target.id) printed \(shown.value) against \(shown.band)")
                        continue
                    }
                    let reads = read >= readLow && read <= readHigh
                    let why =
                        "\(target.id) at \(value) prints \(shown.value) against \(shown.band), "
                        + "which reads \(reads ? "in" : "out of") band while the grade says "
                        + "\(inBand ? "in" : "out of")"
                    #expect(reads == inBand, Comment(rawValue: why))
                }
            }
        }
    }
}
