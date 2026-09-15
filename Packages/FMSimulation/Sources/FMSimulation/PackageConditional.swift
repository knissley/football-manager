import FMCore

/// What the sport answers a personnel grouping with, as a distribution over the packages
/// a coordinator substitutes between.
///
/// One row of `PlayCaller.package(for:)`'s table: the shares of base, nickel, dime and —
/// on the goal-line row alone — the three-back eleven, on the snaps where the offence sent
/// out this grouping on this kind of down, held as cumulative per-mille thresholds so the
/// draw is one integer comparison and the arithmetic is exact at the tenth of a point the
/// source states.
///
/// **Every number here is measured, and none of it is a level.** The shares are
/// `scripts/calibration-sources.py`'s own participation population — regular-season plays
/// from scrimmage with two-point tries excluded, both sides' personnel readable — folded
/// over the 2023 and 2024 releases together and renormalised across four, five and six
/// defensive backs. A three- or seven-defensive-back snap is out of a grouping row's
/// denominator because the caller does not draw those from a grouping: a goal-line eleven and a
/// prevent shell are answers to where the ball is and what the clock says, and
/// `package(for:)` returns them before it reaches this table.
/// `docs/reference/calibration-sources.md` carries the derivation, the per-season figures
/// and the releases they were read from.
///
/// The gotcha worth naming: these are shares of **snaps**, not of carries. The same feed
/// answers a grouping differently on a run and on a pass — eleven personnel meets four
/// defensive backs on 18.8% of first-and-ten designed carries and 10.8% of first-and-ten
/// dropbacks in 2023 — and a caller asked after the concept has been drawn cannot see
/// which it is. Setting a row from the carry figure would put the pass game in a box the
/// sport does not play it in, to make one graded subset land on a number.
struct PackageConditional {

    /// Per mille of snaps answered with four defensive backs.
    let base: UInt64
    /// Per mille answered with four or five, so the nickel arm is everything below this
    /// and at or above `base`.
    let throughNickel: UInt64
    /// And with six or fewer. Everything above it is `DefensivePackage.goalLine`, which is
    /// the remainder rather than a fourth stored share, and **the remainder is not a
    /// sliver**: on the one row that uses it, it is every defensive back count the row does
    /// not name, which the engine has one package heavy enough to play. On every other row
    /// it is a thousand, so that arm never fires.
    let throughDime: UInt64

    private init(base: UInt64, nickel: UInt64, dime: UInt64 = 0, goalLineIsTheRest: Bool = false) {
        self.base = base
        self.throughNickel = base + nickel
        self.throughDime = goalLineIsTheRest ? base + nickel + dime : 1000
    }

    /// The ball on the three or closer, where the situation answers the grouping rather
    /// than the other way round.
    ///
    /// The one row keyed on where the ball is instead of who is on the field, because that
    /// is how the feed reads down there: a defence's answer inside the three moves far more
    /// with the yard line than with the grouping, and the sample — 793 snaps in 2023 and
    /// 857 in 2024 — is thin enough that splitting it six ways would be noise per cell.
    ///
    /// **Four defensive backs on 30.1% (2023) and 34.8% (2024), five on 46.2 and 40.5, six
    /// on 3.9 and 1.5.** Those three are the shares as the feed records them, not
    /// renormalised, so what is left of the thousand — 216 — is everything else the feed
    /// saw inside the three, and that is **three defensive backs or fewer: 19.7% and
    /// 23.2%**, plus the single seven-back snap the two seasons hold between them.
    ///
    /// **So the remainder is a `<= 3` mapping and not the three-back share**, which is
    /// 11.7 and 12.5 on its own and would be wrong here. The engine has one package below
    /// four defensive backs, so a two-back or a one-back goal-line front — 7.6% of these
    /// snaps in 2023 and 10.7% in 2024, the heaviest fronts the sport plays anywhere — has
    /// `goalLine` to land on and nothing else. Folding them onto it plays them as the
    /// heaviest eleven this engine has rather than losing them to a nickel.
    ///
    /// What the engine did before was put the goal-line eleven on *every* snap inside the
    /// three: the same defect this file exists for, one branch along, a function where the
    /// sport has a distribution. The sport's most common answer on the goal line is its
    /// nickel.
    static let insideTheThree = PackageConditional(
        base: 325, nickel: 432, dime: 27, goalLineIsTheRest: true)

    /// How a down groups for this purpose.
    ///
    /// Three and not the eleven `DownAndDistanceClass` has, because that is the shape the
    /// feed's own by-down split takes: a grouping's answer moves a point or two between
    /// first down and the downs that still have another play behind them, and then falls
    /// away sharply once the offence has to throw. Eleven personnel draws the four-back
    /// front on 14.4% of first downs, 8.6% of second downs and short third and fourth
    /// ones, and 1.2% of third and fourth and four or more, where the sixth defensive back
    /// takes 38.8% of the snaps the other two buckets give it eight.
    ///
    /// Short is three yards or fewer, which is `DownAndDistanceClass`'s own split and the
    /// source's.
    enum DownBucket {
        case early
        case middle
        case late

        init(down: Down, distance: UInt8) {
            switch down {
            case .first: self = .early
            case .second: self = .middle
            case .third, .fourth: self = distance <= 3 ? .middle : .late
            }
        }
    }

    /// The row for a grouping on a down, keyed on backs and tight ends because that is
    /// what the feed writes a personnel group as and what a defence counts.
    ///
    /// A grouping the feed has too few snaps of to band is answered by the nearest one it
    /// does: the empty set is five receivers, of which two seasons hold twenty-five snaps
    /// in all, so it reads the four-receiver rows of `01` — no back, which is the part of
    /// an empty set a defence is substituting against. Anything else falls to eleven
    /// personnel's row, which is the grouping three snaps in five are played from.
    static func forGrouping(
        _ group: PersonnelGroup, on down: Down, distance: UInt8
    ) -> PackageConditional {
        let bucket = DownBucket(down: down, distance: distance)
        switch (group.runningBacks, group.tightEnds) {
        // 11 personnel. 18,276 / 18,338 / 8,706 snaps behind the three rows.
        case (1, 1):
            switch bucket {
            case .early: return PackageConditional(base: 144, nickel: 792)
            case .middle: return PackageConditional(base: 86, nickel: 835)
            case .late: return PackageConditional(base: 12, nickel: 600)
            }
        // 12 personnel. 8,450 / 6,339 / 781.
        case (1, 2):
            switch bucket {
            case .early: return PackageConditional(base: 597, nickel: 384)
            case .middle: return PackageConditional(base: 499, nickel: 474)
            case .late: return PackageConditional(base: 179, nickel: 545)
            }
        // 13 personnel. 1,391 / 970 / 76. The offence never sends it out today; the row
        // is here because the table is the sport's conditional and not the engine's mix,
        // and a grouping the caller starts using should not fall through to eleven
        // personnel's answer.
        case (1, 3):
            switch bucket {
            case .early: return PackageConditional(base: 832, nickel: 150)
            case .middle: return PackageConditional(base: 803, nickel: 185)
            case .late: return PackageConditional(base: 763, nickel: 184)
            }
        // 21 personnel. 583 / 520 / 59. The one row that inverts the old rule outright:
        // two backs draw the *fifth* defensive back about three times in four, where the
        // engine gave them the four-back front every snap.
        case (2, 1):
            switch bucket {
            case .early: return PackageConditional(base: 228, nickel: 744)
            case .middle: return PackageConditional(base: 233, nickel: 740)
            case .late: return PackageConditional(base: 68, nickel: 610)
            }
        // 22 personnel. 145 / 130 / 31. The thinnest rows that are still a grouping the
        // offence sends out; the late row is thirty-one snaps and is read as such.
        case (2, 2):
            switch bucket {
            case .early: return PackageConditional(base: 579, nickel: 407)
            case .middle: return PackageConditional(base: 677, nickel: 323)
            case .late: return PackageConditional(base: 484, nickel: 387)
            }
        // 10 personnel: one back, four receivers. 366 / 332 / 154.
        case (1, 0):
            switch bucket {
            case .early: return PackageConditional(base: 180, nickel: 784)
            case .middle: return PackageConditional(base: 151, nickel: 819)
            case .late: return PackageConditional(base: 13, nickel: 630)
            }
        // The empty set, answered from `01`'s four-receiver rows. 169 / 233 / 457.
        case (0, _):
            switch bucket {
            case .early: return PackageConditional(base: 118, nickel: 787)
            case .middle: return PackageConditional(base: 60, nickel: 845)
            case .late: return PackageConditional(base: 2, nickel: 575)
            }
        default:
            switch bucket {
            case .early: return PackageConditional(base: 144, nickel: 792)
            case .middle: return PackageConditional(base: 86, nickel: 835)
            case .late: return PackageConditional(base: 12, nickel: 600)
            }
        }
    }
}
