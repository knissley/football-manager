import FMCore
import FMRandom
import Testing

@testable import FMGeneration

private let season = 2030
private let seeds: [UInt64] = [1, 5, 7, 11]

private func world(seed: UInt64) -> WorldGenerator.GeneratedWorld? {
    try? WorldGenerator.generate(seed: seed, season: season).get()
}

private func everyone(seed: UInt64) -> [Player] {
    guard let world = world(seed: seed) else { return [] }
    // `world.teams` is ordered by identifier, so this walk is stable.
    return world.teams.flatMap { world.roster(of: $0.id) }
}

private func mean(_ values: [Int]) -> Double {
    guard !values.isEmpty else { return 0 }
    return Double(values.reduce(0, +)) / Double(values.count)
}

/// The league you inherit has a past.
///
/// No generated player carried a `DraftInfo` at all, so the initial league had no draft
/// history: nobody had been picked by anybody, every accrued season was guessed from a
/// birthday, and the first draft you ran was the first draft that had ever happened.
/// Issue #6.
@Suite("Draft history in a generated world")
struct DraftHistoryTests {

    /// Three quarters is the generation target — the rest arrived undrafted — and it is a
    /// design choice about the world rather than a measured fact about any real league.
    @Test("contract: about three quarters of a generated league was drafted", .tags(.contract))
    func draftedShare() {
        for seed in seeds {
            let players = everyone(seed: seed)
            #expect(!players.isEmpty, "seed \(seed) generated nobody")
            let drafted = players.filter { $0.draft != nil }.count
            let share = Double(drafted) / Double(max(1, players.count))
            #expect(share > 0.70 && share < 0.80, "seed \(seed) drafted \(share)")
        }
    }

    /// Undrafted is a way of arriving, not a missing record. Every player knows the
    /// season he first counted against a roster, which is what accrued seasons are
    /// counted from.
    @Test("contract: an undrafted player still knows the season he arrived", .tags(.contract))
    func undraftedStillArrive() {
        for seed in seeds {
            let undrafted = everyone(seed: seed).filter { $0.draft == nil }
            #expect(!undrafted.isEmpty, "seed \(seed) had nobody undrafted")
            for player in undrafted {
                #expect(player.firstSeason <= season, "\(player.name.full) arrives in the future")
                #expect(
                    player.firstSeason >= player.birthSeason + 20,
                    "\(player.name.full) arrived at \(player.firstSeason - player.birthSeason)")
            }
        }
    }

    @Test(
        "contract: a drafted player's first season is the season he was drafted", .tags(.contract))
    func draftedFirstSeason() {
        for seed in seeds {
            for player in everyone(seed: seed) {
                guard let draft = player.draft else { continue }
                #expect(player.firstSeason == draft.season)
                #expect(player.experience(in: season) == season - draft.season)
            }
        }
    }

    /// A pick that is not on the board is not a pick. Seven rounds of thirty-two, which is
    /// the standard league's draft.
    @Test("contract: every pick sits on the board it was made from", .tags(.contract))
    func picksAreOnTheBoard() {
        let rounds = DraftClassGenerator.ClassShape.standard.rounds
        for seed in seeds {
            guard let world = world(seed: seed) else {
                Issue.record("seed \(seed) did not produce a world")
                continue
            }
            let picksPerRound = world.teams.count
            let drafted = world.teams.flatMap { world.roster(of: $0.id) }
                .compactMap(\.draft)
            #expect(!drafted.isEmpty, "seed \(seed) drafted nobody")
            for pick in drafted {
                #expect(pick.round >= 1 && Int(pick.round) <= rounds, "round \(pick.round)")
                #expect(pick.pick >= 1 && Int(pick.pick) <= picksPerRound, "pick \(pick.pick)")
                #expect(
                    Int(pick.overallPick)
                        == (Int(pick.round) - 1) * picksPerRound + Int(pick.pick),
                    "overall \(pick.overallPick) disagrees with \(pick.round)-\(pick.pick)")
                #expect(pick.season <= season, "drafted in \(pick.season)")
            }
        }
    }

    /// Every round is used. A history where nobody was ever a seventh-round pick is a
    /// history with no late bloomers in it.
    @Test("contract: a generated league contains a player from every round", .tags(.contract))
    func everyRoundIsRepresented() {
        let rounds = DraftClassGenerator.ClassShape.standard.rounds
        let byRound = Set(everyone(seed: 7).compactMap { $0.draft?.round })
        for round in 1...rounds {
            #expect(byRound.contains(UInt8(round)), "nobody went in round \(round)")
        }
    }

    /// The league's history is a decade deep, not one draft. A world where every player
    /// entered in the same season has veterans who are somehow all the same age.
    @Test("contract: draft history goes back more than a decade", .tags(.contract))
    func historyIsDeep() {
        let seasons = Set(everyone(seed: 7).compactMap { $0.draft?.season })
        #expect(seasons.count >= 10, "only \(seasons.count) draft seasons in the league")
        #expect(seasons.contains(season), "no team has a rookie draft pick")
    }

    /// The point of hanging the round off the ceiling: the best players in the league are
    /// the ones who went early, so a roster's draft history reads as an explanation of the
    /// roster rather than as decoration next to it.
    @Test("contract: the better the player, the earlier he went", .tags(.contract))
    func betterPlayersWentEarlier() {
        let drafted = seeds.flatMap { everyone(seed: $0) }.filter { $0.draft != nil }
        #expect(!drafted.isEmpty)

        func meanCeiling(round: UInt8) -> Double {
            mean(drafted.filter { $0.draft?.round == round }.map { Int($0.hidden.ceiling) })
        }
        let first = meanCeiling(round: 1)
        let fourth = meanCeiling(round: 4)
        let seventh = meanCeiling(round: 7)
        #expect(first > fourth, "round 1 \(first), round 4 \(fourth)")
        #expect(fourth > seventh, "round 4 \(fourth), round 7 \(seventh)")

        let undrafted = mean(
            seeds.flatMap { everyone(seed: $0) }.filter { $0.draft == nil }
                .map { Int($0.hidden.ceiling) })
        #expect(seventh > undrafted, "round 7 \(seventh), undrafted \(undrafted)")
    }

    /// A contending roster is made of players who went earlier than a rebuilding one's.
    /// The round comes off a league-wide band rather than a place in this team's own
    /// order, which is what lets the two differ at all.
    @Test("contract: a contender's roster went earlier than a rebuilding one's", .tags(.contract))
    func strengthShowsInTheHistory() {
        func meanRound(_ strength: RosterGenerator.Strength) -> Double {
            var random = SplittableRandom(seed: 31)
            var ids = IdentifierSequence<PlayerSubject>()
            let colleges = NameGenerator.collegePool(count: 60, using: &random)
            let roster = RosterGenerator.roster(
                strength: strength, season: season, colleges: colleges, ids: &ids,
                using: &random)
            // An undrafted player counts as a round past the last, which is what being
            // undrafted is.
            let rounds = DraftClassGenerator.ClassShape.standard.rounds
            return mean(roster.map { Int($0.draft?.round ?? UInt8(rounds + 1)) })
        }
        let contender = meanRound(.contender)
        let rebuilding = meanRound(.rebuilding)
        #expect(contender < rebuilding, "contender \(contender), rebuilding \(rebuilding)")
    }

    /// About a sixth of a roster is in its first season, and the rest of it has been here
    /// before.
    ///
    /// **Sourced.** Opening-week rosters — week 1 of the regular season, the active list
    /// plus that week's inactives, without the practice squad — carried 281 first-season
    /// players of 1,729 in 2023 (0.1625), 274 of 1,754 in 2024 (0.1562) and 266 of 1,740 in
    /// 2025 (0.1529), counted from the nflverse weekly roster data set. The band spans those
    /// three seasons widened by 5% of their mean, which is the band policy in
    /// [`calibration-sources.md`](../../../../docs/reference/calibration-sources.md), where
    /// this row and its derivation are recorded.
    ///
    /// Pooled over eight leagues rather than asserted seed by seed. One league is 1,696 men
    /// and its share moves further from seed to seed than the band is wide — 0.130 to 0.169
    /// over sixteen seeds — so a per-seed bound would be a claim about the seed rather than
    /// about generation. Eight leagues is 13,568 men.
    ///
    /// **This replaces a fence.** The test here before asserted `share < 0.30`, a bound
    /// picked knowing the output, and it was green while a quarter of every roster was a
    /// rookie because `RosterGenerator.age` clamped at twenty-one
    /// ([#67](https://github.com/knissley/football-manager/issues/67)).
    @Test(
        "football: about a sixth of a roster is in its first season, 0.145 to 0.171 (2023-2025 week 1 rosters, nflverse weekly roster data)",
        .tags(.football))
    func firstSeasonShare() {
        var rookies = 0
        var players = 0
        for seed in UInt64(1)...8 {
            let league = everyone(seed: seed)
            #expect(!league.isEmpty, "seed \(seed) generated nobody")
            rookies += league.filter { $0.isRookie(in: season) }.count
            players += league.count
        }
        let share = Double(rookies) / Double(max(1, players))
        #expect(
            share >= 0.145 && share <= 0.171,
            "\(rookies) of \(players) are in their first season — \(share)")
    }

    /// Every club has a rookie class and no club is mostly rookies. Structure rather than a
    /// rate: the rate is `firstSeasonShare` above, and this is what stops one club carrying
    /// the whole league's intake.
    @Test(
        "contract: every roster has first-season players and none is made of them",
        .tags(.contract))
    func everyRosterHasARookieClass() {
        for seed in seeds {
            guard let world = world(seed: seed) else {
                Issue.record("seed \(seed) did not produce a world")
                continue
            }
            for team in world.teams {
                let roster = world.roster(of: team.id)
                let rookies = roster.filter { $0.isRookie(in: season) }
                #expect(!rookies.isEmpty, "seed \(seed): \(team.identity.fullName) has no rookies")
                let makeup = "\(rookies.count) of \(roster.count)"
                #expect(
                    rookies.count * 3 <= roster.count * 2,
                    "seed \(seed): \(team.identity.fullName) is \(makeup) rookies")
                #expect(rookies.allSatisfy { $0.experience(in: season) == 0 })
            }
        }
    }

    @Test("contract: the same seed writes the same draft history", .tags(.contract))
    func deterministic() {
        let first = everyone(seed: 5).map { $0.draft }
        let second = everyone(seed: 5).map { $0.draft }
        #expect(first == second)
    }
}
