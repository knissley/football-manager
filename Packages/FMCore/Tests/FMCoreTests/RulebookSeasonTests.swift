import Testing

@testable import FMCore

/// The defaults in `Rules` are a particular season's book, and this suite is what says
/// which one.
///
/// The engine was written from a mixture of two books: the kickoff touchback sat at the
/// 2024 spot while the overtime rules were the 2025 ones, and nothing in the tree
/// recorded the contradiction. A season on `Rules` and a test per constant is what makes
/// the mixture impossible to reintroduce quietly.
@Suite("The rulebook the defaults come from")
struct RulebookSeasonTests {

    private let rules = Rules.standard

    @Test(
        "contract: the rules the engine plays under name the season they were read from",
        .tags(.contract))
    func defaultsNameTheirSeason() {
        #expect(rules.rulebookSeason == 2025)
    }

    /// The kick reaches the end zone without coming down in the landing zone first, so it
    /// is the 35 and not the 30 the 2024 book had.
    @Test(
        "football · Rule 6-1-5 · a kickoff that reaches the end zone without touching down in the landing zone is a touchback at the receiving team's 35",
        .tags(.football))
    func kickoffTouchbackIsAtTheThirtyFive() {
        #expect(rules.kickoffTouchbackOwnYard == 35)
        #expect(rules.kickoffTouchbackSpot == 65, "its own 35 is 65 from the other goal line")

        let situation = Situation(
            quarter: 1, clockRemaining: 900, down: .first, distance: 10,
            ballOn: rules.ballOnFromOwnYard(rules.kickoffFromOwnYard), possession: TeamID(1))
        let advancement = rules.advance(
            from: situation, outcome: Outcome(kind: .kickoff, yards: 0, endedIn: .touchback))

        #expect(advancement.ballOn == 65)
        #expect(advancement.possessionChanged)
        #expect(advancement.down == .first)
        #expect(advancement.distance == rules.yardsToGain)
    }

    /// A punt's touchback did not move, and the two spots being fifteen yards apart is
    /// the whole point of the kickoff rule: a kicker who will not put the ball in the
    /// landing zone hands over the 35.
    @Test(
        "football · Rule 6-1-5, 11-6-2-c · a kickoff touchback comes out fifteen yards further than a punt's",
        .tags(.football))
    func aKickoffTouchbackOutrunsAPunts() {
        #expect(rules.puntTouchbackOwnYard == 20)
        #expect(Int(rules.kickoffTouchbackOwnYard) - Int(rules.puntTouchbackOwnYard) == 15)
    }

    /// Both the 2025 and the 2026 books let the kicking team declare at any time during
    /// the game. What 2025 requires, and 2026 dropped, is that it be **trailing**.
    @Test(
        "football · Rule 6-1-1-c, 6-1-6 · the kicking team may declare an onside kick at any time during the game, and only while trailing",
        .tags(.football))
    func onsideKicksAreDeclaredWheneverTrailing() {
        for quarter in UInt8(1)...4 {
            #expect(
                rules.mayDeclareOnsideKick(quarter: quarter, scoreDifferential: -7),
                "trailing in the \(quarter) quarter")
            #expect(
                !rules.mayDeclareOnsideKick(quarter: quarter, scoreDifferential: 0),
                "level, so nothing to declare")
            #expect(
                !rules.mayDeclareOnsideKick(quarter: quarter, scoreDifferential: 3),
                "leading, so nothing to declare")
        }
        // Overtime is a period past the fourth, and a team can trail inside one.
        #expect(rules.mayDeclareOnsideKick(quarter: 5, scoreDifferential: -3))
    }

    /// The season before, and the reason the field exists: the 2024 book allowed the
    /// declaration only in the fourth quarter and spotted the touchback at the 30. The
    /// harness plays that variant under `--rulebook 2024`, so it is data on `Rules`
    /// rather than a second copy of the rule values in a tool.
    @Test(
        "contract: the 2024 rulebook is a Rules variant, differing only in the kickoff and the onside kick",
        .tags(.contract))
    func the2024RulebookIsData() {
        guard let earlier = Rules.rulebook(2024) else {
            Issue.record("no 2024 rulebook variant")
            return
        }
        #expect(earlier.rulebookSeason == 2024)
        #expect(earlier.kickoffTouchbackOwnYard == 30)
        #expect(earlier.onsideKickEarliestQuarter == 4)
        #expect(!earlier.mayDeclareOnsideKick(quarter: 1, scoreDifferential: -7))
        #expect(earlier.mayDeclareOnsideKick(quarter: 4, scoreDifferential: -7))
        #expect(!earlier.mayDeclareOnsideKick(quarter: 4, scoreDifferential: 7))

        // Nothing else moved between the two books, so the variant is those three fields
        // and no more: a copy that drifted would be a second rulebook nobody was reading.
        var expected = Rules.standard
        expected.rulebookSeason = 2024
        expected.kickoffTouchbackOwnYard = 30
        expected.onsideKickEarliestQuarter = 4
        #expect(earlier == expected)

        #expect(Rules.rulebook(2025) == .standard)
        #expect(Rules.rulebook(2023) == nil, "no book we have read")
        #expect(Rules.supportedRulebooks == [2024, 2025])
    }
}
