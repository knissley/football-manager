import Testing

@testable import FMCore

/// What a player's arrival in the league means.
///
/// `isRookie` used to be a tautology — it compared `draft.season` with
/// `birthSeason + (draft.season - birthSeason)`, which is `draft.season` written the long
/// way round, so every drafted player was a rookie forever. It could not be wrong about
/// one player without being wrong about all of them, and nothing asked it anything.
/// Issue #6.
@Suite("A player's arrival in the league")
struct PlayerArrivalTests {

    private let ordinary = Ratings()

    private func player(
        birthSeason: Int,
        draft: DraftInfo? = nil,
        firstSeason: Int?
    ) -> Player {
        Player(
            id: PlayerID(1),
            name: PersonName(given: "Test", family: "Player"),
            birthSeason: birthSeason,
            college: College(name: "Fallback State", profile: .midMajor),
            draft: draft,
            firstSeason: firstSeason,
            position: .wideReceiver,
            physical: PhysicalProfile(
                heightInches: 73, weightPounds: 200, fortyYardDash: 445, verticalJump: 350,
                broadJump: 1200, threeCone: 690, benchReps: 14),
            ratings: ordinary,
            hidden: HiddenAttributes(
                ceiling: 80, developmentTrait: .normal, workEthic: 60, durability: 60))
    }

    private let secondRoundPick = DraftInfo(season: 2030, round: 2, pick: 12, overallPick: 44)

    @Test("unit: a drafted player is a rookie in the season he was drafted", .tags(.unit))
    func draftedRookie() {
        let rookie = player(birthSeason: 2008, draft: secondRoundPick, firstSeason: 2030)
        #expect(rookie.isRookie(in: 2030))
        #expect(rookie.experience(in: 2030) == 0)
    }

    @Test("unit: a second-year player is not a rookie", .tags(.unit))
    func secondYear() {
        let sophomore = player(birthSeason: 2008, draft: secondRoundPick, firstSeason: 2030)
        #expect(!sophomore.isRookie(in: 2031))
        #expect(sophomore.experience(in: 2031) == 1)
        // And still not one in his ninth. The tautology was true here too.
        #expect(!sophomore.isRookie(in: 2038))
    }

    @Test("unit: an undrafted player is a rookie in his first season and not after", .tags(.unit))
    func undraftedRookie() {
        let undrafted = player(birthSeason: 2007, firstSeason: 2030)
        #expect(undrafted.isRookie(in: 2030))
        #expect(!undrafted.isRookie(in: 2031))
    }

    /// The old fallback read experience off age — `season - birthSeason - 22` — so a
    /// twenty-six-year-old who signed last spring was a four-year veteran, and a
    /// twenty-three-year-old who had been in the league two years was a rookie.
    @Test("unit: experience counts from the first season rather than from an age", .tags(.unit))
    func experienceIsCounted() {
        let lateArrival = player(birthSeason: 2004, firstSeason: 2029)
        #expect(lateArrival.age(in: 2030) == 26)
        #expect(lateArrival.experience(in: 2030) == 1)

        let early = player(birthSeason: 2009, firstSeason: 2028)
        #expect(early.age(in: 2030) == 21)
        #expect(early.experience(in: 2030) == 2)
    }

    /// Two sources for one fact is one too many: a drafted player's first season *is* his
    /// draft season, so the type does not let them disagree.
    @Test("unit: a drafted player's first season is his draft season", .tags(.unit))
    func firstSeasonFollowsTheDraft() {
        let mismatched = player(birthSeason: 2008, draft: secondRoundPick, firstSeason: 2033)
        #expect(mismatched.firstSeason == 2030)
        #expect(mismatched.experience(in: 2032) == 2)
    }

    @Test("unit: nobody has negative experience in a season before he arrived", .tags(.unit))
    func beforeHeArrived() {
        let rookie = player(birthSeason: 2008, draft: secondRoundPick, firstSeason: 2030)
        #expect(rookie.experience(in: 2029) == 0)
        #expect(!rookie.isRookie(in: 2029))
    }

    /// A man with no first season has not arrived — a college prospect, whom nobody has
    /// drafted and nobody has signed. He is not a rookie in any season, and he has accrued
    /// nothing, until somebody gives him a first season by taking him
    /// ([#67](https://github.com/knissley/football-manager/issues/67)).
    @Test("unit: a player who has not arrived is not a rookie in any season", .tags(.unit))
    func hasNotArrived() {
        let prospect = player(birthSeason: 2008, firstSeason: nil)
        #expect(prospect.firstSeason == nil)
        #expect(!prospect.isRookie(in: 2030))
        #expect(!prospect.isRookie(in: 2031))
        #expect(prospect.experience(in: 2030) == 0)
        #expect(prospect.experience(in: 2040) == 0)
    }
}
