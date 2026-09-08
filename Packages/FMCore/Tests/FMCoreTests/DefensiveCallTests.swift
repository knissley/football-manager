import Testing

@testable import FMCore

@Suite("Defensive calls")
struct DefensiveCallTests {

    /// The named calls are a convenience over the composition. They only earn
    /// that if each one actually describes the defence its name claims.
    private static let named: [(String, DefensiveCall)] = [
        ("baseCoverThree", .baseCoverThree),
        ("nickelTwoMan", .nickelTwoMan),
        ("quartersMatch", .quartersMatch),
        ("coverTwoZone", .coverTwoZone),
        ("fireZone", .fireZone),
        ("manFreeBlitz", .manFreeBlitz),
        ("allOut", .allOut),
        ("goalLineStop", .goalLineStop),
        ("dimeRush", .dimeRush),
        ("preventShell", .preventShell),
        ("runStuff", .runStuff),
    ]

    // MARK: - Coverage

    @Test("Deep help is counted, not assumed")
    func deepDefenders() {
        #expect(Coverage.coverZero.deepDefenders == 0)
        #expect(Coverage.manFree.deepDefenders == 1)
        #expect(Coverage.coverThree.deepDefenders == 1)
        #expect(Coverage.coverTwo.deepDefenders == 2)
        #expect(Coverage.twoMan.deepDefenders == 2)
        #expect(Coverage.quarters.deepDefenders == 4)
    }

    @Test("Man and zone are distinguished, because rubs only beat one of them")
    func manCoverages() {
        #expect(Coverage.coverZero.isMan)
        #expect(Coverage.manFree.isMan)
        #expect(Coverage.twoMan.isMan)
        #expect(Coverage.coverThree.isMan == false)
        #expect(Coverage.matchQuarters.isMan == false)
    }

    /// A coverage that trades a defender for a rusher has to be paired with a
    /// rush that gets home, or it is just a hole in the middle of the field.
    @Test("Pressure coverages leave no deep help")
    func pressureCoveragesAreBare() {
        for coverage in Coverage.allCases where coverage.isPressureCoverage {
            #expect(coverage.deepDefenders == 0, "\(coverage) should have no deep help")
        }
    }

    // MARK: - Rush

    @Test("Rusher counts match the names")
    func rusherCounts() {
        #expect(PassRush.threeMan.rushers == 3)
        #expect(PassRush.fourMan.rushers == 4)
        #expect(PassRush.zoneBlitz.rushers == 4)
        #expect(PassRush.simulated.rushers == 4)
        #expect(PassRush.fiveManBlitz.rushers == 5)
        #expect(PassRush.sixManBlitz.rushers == 6)
    }

    /// A zone blitz and a simulated pressure send four. They are not blitzes;
    /// calling them one would mean the coverage gave up a body it never gave up.
    @Test("Only extra rushers count as a blitz")
    func blitzMeansExtraRushers() {
        for rush in PassRush.allCases {
            #expect(rush.isBlitz == (rush.rushers > 4), "\(rush)")
        }
    }

    // MARK: - Composed reads

    @Test("All-out means more rushers than deep help")
    func allOut() {
        #expect(DefensiveCall.allOut.isAllOut)
        #expect(DefensiveCall.manFreeBlitz.isAllOut)
        #expect(DefensiveCall.fireZone.isAllOut == false)
        #expect(DefensiveCall.baseCoverThree.isAllOut == false)
        #expect(
            DefensiveCall(coverage: .quarters, rush: .sixManBlitz).isAllOut == false,
            "six rushers with four deep is a heavy call, not a bare one")
    }

    /// Conceding underneath is not a bug in the call — it is the trade. The
    /// analysis layer needs to know, so a nine-yard completion on second and
    /// fifteen reads as the defence winning.
    @Test("Calls that concede short yardage say so")
    func concedesUnderneath() {
        #expect(DefensiveCall.preventShell.concedesUnderneath)
        #expect(DefensiveCall.dimeRush.concedesUnderneath)
        #expect(DefensiveCall.allOut.concedesUnderneath == false)
        #expect(DefensiveCall.goalLineStop.concedesUnderneath == false)
    }

    @Test("A two-minute sound call keeps help deep and does not vacate the middle")
    func twoMinuteSoundness() {
        #expect(DefensiveCall.coverTwoZone.isTwoMinuteSound)
        #expect(DefensiveCall.dimeRush.isTwoMinuteSound)
        #expect(DefensiveCall.allOut.isTwoMinuteSound == false)
        #expect(DefensiveCall.baseCoverThree.isTwoMinuteSound == false)
    }

    // MARK: - Vulnerability

    /// The point of the call being a bet: a coordinator choosing between these
    /// is choosing what to give up, so the list has to actually offer different
    /// trades rather than a best call and ten worse ones.
    @Test("The named calls offer genuinely different trades")
    func namedCallsDiffer() {
        let weaknesses = Set(Self.named.map(\.1.vulnerability))
        #expect(weaknesses.count >= 5, "the playbook barely discriminates: \(weaknesses)")
    }

    @Test("Vulnerabilities read the way the sport does")
    func vulnerabilities() {
        #expect(DefensiveCall.allOut.vulnerability == .quickGame)
        #expect(DefensiveCall.goalLineStop.vulnerability == .playAction)
        #expect(DefensiveCall.nickelTwoMan.vulnerability == .crossers)
        #expect(DefensiveCall.preventShell.vulnerability == .theRun)
        #expect(DefensiveCall.dimeRush.vulnerability == .theRun)
        #expect(DefensiveCall.fireZone.vulnerability == .hotThrow)
        #expect(DefensiveCall.baseCoverThree.vulnerability == .seams)
        #expect(DefensiveCall.coverTwoZone.vulnerability == .seams)
        #expect(
            DefensiveCall(coverage: .coverThree, frontAlignment: .overShifted).vulnerability
                == .runAwayFromStrength)
    }

    /// Each weakness must be reachable from some legal call, or the analysis
    /// layer holds a vocabulary it can never use.
    @Test("Every vulnerability is reachable")
    func everyVulnerabilityIsReachable() {
        var seen: Set<CallVulnerability> = []
        for coverage in Coverage.allCases {
            for rush in PassRush.allCases {
                for alignment in FrontAlignment.allCases {
                    for fit in RunFit.allCases {
                        seen.insert(
                            DefensiveCall(
                                coverage: coverage, rush: rush, frontAlignment: alignment,
                                runFit: fit
                            ).vulnerability)
                    }
                }
            }
        }
        #expect(seen.count == CallVulnerability.allCases.count)
    }

    // MARK: - Named calls

    @Test("Named calls describe the defence their name claims")
    func namedCallsAreCoherent() {
        #expect(DefensiveCall.goalLineStop.package == .goalLine)
        #expect(DefensiveCall.goalLineStop.runFit == .sellOut)
        #expect(DefensiveCall.preventShell.coverage.deepDefenders >= 4)
        #expect(DefensiveCall.preventShell.rush.isBlitz == false)
        #expect(DefensiveCall.fireZone.rush == .zoneBlitz)
        #expect(DefensiveCall.allOut.coverage == .coverZero)
        #expect(DefensiveCall.runStuff.frontAlignment == .bear)
        #expect(DefensiveCall.nickelTwoMan.coverage.isMan)
    }

    /// Nickel and dime exist to add coverage bodies. A blitz-heavy call out of
    /// dime would be spending them on the rush instead, which is a real call but
    /// not one of these.
    @Test("Sub packages carry enough defensive backs for their coverage")
    func packagesMatchCoverage() {
        for (name, call) in Self.named where call.coverage.deepDefenders >= 4 {
            #expect(call.package.defensiveBacks >= 5, "\(name) needs sub-package bodies")
        }
    }

    // MARK: - Situational fit

    /// The tie back to `SituationClass`: the shared vocabulary has to be able to
    /// tell these calls apart, or a gameplan rule keyed to a situation could not
    /// pick between them.
    @Test("Situational reads separate the calls a coordinator would choose between")
    func situationsDiscriminate() {
        let twoMinute = SituationClass(
            Situation(
                quarter: 4, clockRemaining: 70, down: .first, distance: 10, ballOn: 60,
                possession: TeamID(1), scoreDifferential: -4))
        #expect(twoMinute.isMustPass)
        #expect(DefensiveCall.preventShell.isTwoMinuteSound)
        #expect(DefensiveCall.allOut.isTwoMinuteSound == false)

        let shortYardage = SituationClass(
            Situation(
                quarter: 2, clockRemaining: 600, down: .third, distance: 1, ballOn: 40,
                possession: TeamID(1)))
        #expect(shortYardage.downAndDistance.isShortYardage)
        #expect(shortYardage.isMustPass == false)
        #expect(DefensiveCall.goalLineStop.vulnerability == .playAction)
    }
}
