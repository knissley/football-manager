import FMCore
import Testing

@testable import FMSimulation

/// Who was on the field, as the stream says it.
///
/// Credits are sparse by design — only the men who did something are in
/// `outcome.participants` — so for a long time the record could not answer the most
/// ordinary question a box score asks: who took the snap. A lineman was credited on
/// three to five of every five snaps and a safety on a sixth of run plays, and a snap
/// count was whatever the credits happened to add up to. `PlayRecord.onField` is
/// twenty-two roster indices in slot order, and `GameResult.rosters` is the table they
/// index, so presence is a fact and a snap count is a query.
///
/// Every test here is a promise the engine makes about its own stream, never a claim
/// about the sport.
@Suite("Who was on the field")
struct OnFieldTests {

    private static func game(seed: UInt64) -> GameResult {
        TestWorld.game(seed: seed, game: GameID(seed))
    }

    private static let sample: [GameResult] = (UInt64(1)...20).map(game(seed:))

    /// The roster the slot indexes: the possessing team's for the offensive slots, the
    /// other side's for the defensive ones — which on a kickoff makes the kicking team
    /// the offence, exactly as `Situation.possession` and `PlayerSlot.isOffense` say.
    private static func roster(
        for slot: PlayerSlot, on play: PlayRecord, in result: GameResult
    ) -> [PlayerID] {
        let possession = play.situation.possession
        if slot.isOffense { return result.rosters[possession] ?? [] }
        let other = result.rosters.keys.first { $0 != possession }
        return other.flatMap { result.rosters[$0] } ?? []
    }

    @Test(
        "Every play carries exactly twenty-two slots, kicks, tries and flags included",
        .tags(.contract))
    func everyPlayCarriesTwentyTwoSlots() {
        var kinds: Set<PlayKind> = []
        for result in Self.sample {
            for play in result.plays {
                kinds.insert(play.outcome.kind)
                #expect(
                    play.onField.count == PlayerSlot.count,
                    "play \(play.index) of game \(result.game) carries \(play.onField.count) slots")
            }
        }
        for kind in [PlayKind.kickoff, .punt, .fieldGoal, .extraPoint, .penaltyOnly] {
            #expect(kinds.contains(kind), "the sample never produced a \(kind)")
        }
    }

    @Test("Every occupied slot indexes inside its team's roster", .tags(.contract))
    func everyIndexIsWithinTheRoster() {
        for result in Self.sample {
            #expect(result.rosters.count == 2, "a game has two rosters")
            for play in result.plays {
                for (index, entry) in play.onField.enumerated() where entry != PlayRecord.vacant {
                    let slot = PlayerSlot(index)
                    let roster = Self.roster(for: slot, on: play, in: result)
                    #expect(
                        Int(entry) < roster.count,
                        "slot \(index) on play \(play.index) indexes \(entry) into a roster of \(roster.count)"
                    )
                }
            }
        }
    }

    /// The join that makes the field real: every credit is a slot, every slot is a man,
    /// and they had better be the same man. Offence in 0 through 10 indexes the
    /// possessing team's roster and defence in 11 through 21 the other side's, so on a
    /// kickoff the kicker sits in an offensive slot on the *kicking* team's roster.
    @Test("Every credited participant is the player the slot resolves to", .tags(.contract))
    func creditsAgreeWithTheField() {
        var kickoffs = 0
        for result in Self.sample {
            for play in result.plays {
                for participant in play.outcome.participants {
                    let resolved = play.player(at: participant.slot, rosters: result.rosters)
                    #expect(
                        resolved == participant.player,
                        "play \(play.index): slot \(participant.slot.rawValue) is credited to \(participant.player) and resolves to \(String(describing: resolved))"
                    )
                }
                guard play.outcome.kind == .kickoff,
                    let kicker = play.outcome.participants.first(where: { $0.role == .kicker })
                else { continue }
                kickoffs += 1
                #expect(kicker.slot.isOffense, "the kicker is on the side with the ball")
                #expect(
                    result.rosters[play.situation.possession]?.contains(kicker.player) == true,
                    "the kicker is on the kicking team's roster")
            }
        }
        #expect(kickoffs > 0, "no kickoff to check")
    }

    @Test("No player appears twice on one play", .tags(.contract))
    func nobodyAppearsTwice() {
        for result in Self.sample {
            for play in result.plays {
                var seen: Set<PlayerID> = []
                for index in 0..<PlayerSlot.count {
                    guard let player = play.player(at: PlayerSlot(index), rosters: result.rosters)
                    else { continue }
                    #expect(
                        seen.insert(player).inserted,
                        "\(player) is in two slots on play \(play.index) of game \(result.game)")
                }
            }
        }
    }

    /// Next man up, seen from the field rather than from the credits: `InjuryTests`
    /// already checks a man who left is never credited again, and a man who is on the
    /// field without being credited is exactly what the credits could not see.
    @Test("A player who left hurt is never on the field again", .tags(.contract))
    func theHurtLeaveTheField() {
        var checked = 0
        for result in Self.sample {
            for injury in result.injuries where injury.leavesTheGame {
                guard let index = result.plays.firstIndex(where: { $0.id == injury.occurredOn })
                else { continue }
                checked += 1
                for play in result.plays[(index + 1)...] {
                    let present = (0..<PlayerSlot.count).contains { slot in
                        play.player(at: PlayerSlot(slot), rosters: result.rosters) == injury.player
                    }
                    #expect(
                        !present,
                        "\(injury.player) left on play \(index) and is on the field on play \(play.index)"
                    )
                }
            }
        }
        #expect(checked > 0, "twenty games and nobody left hurt")
    }

    /// One quarterback takes every snap from scrimmage, and he is the possessing team's:
    /// so the snap counts of a team's quarterbacks sum to its plays from scrimmage, which
    /// is the arithmetic a snap count has to satisfy before it can be believed.
    @Test("A team's quarterback snaps sum to its plays from scrimmage", .tags(.contract))
    func quarterbackSnapsSumToScrimmagePlays() {
        for result in Self.sample {
            let players = TestWorld.world(seed: result.game.rawValue).players
            for (team, roster) in result.rosters.sorted(by: { $0.key < $1.key }) {
                let scrimmage = result.plays.filter {
                    $0.outcome.kind.isScrimmagePlay && $0.situation.possession == team
                }
                let quarterbacks = Set(roster.filter { players[$0]?.position == .quarterback })
                let counts = scrimmage.snapCounts(rosters: result.rosters)
                let quarterbackSnaps = counts.filter { quarterbacks.contains($0.key) }
                    .values.reduce(0, +)
                #expect(
                    quarterbackSnaps == scrimmage.count,
                    "game \(result.game), \(team): \(quarterbackSnaps) quarterback snaps over \(scrimmage.count) plays"
                )
                for play in scrimmage {
                    let underCentre = play.player(at: PlayerSlot(0), rosters: result.rosters)
                    #expect(
                        underCentre.map(quarterbacks.contains) == true,
                        "play \(play.index): slot 0 is \(String(describing: underCentre)), not a quarterback"
                    )
                }
            }
        }
    }

    /// Pins the redraw: `Lineup.fill` draws every slot per snap against the rotation
    /// shares, so the backup takes about one snap in fifty with nobody hurt, and the
    /// starter's count is *most* of his team's plays rather than all of them. The plan
    /// for the record says a starting quarterback's snap count equals his team's
    /// scrimmage plays while he was available; that is the sentence
    /// [#27](https://github.com/knissley/football-manager/issues/27) makes true, and when
    /// it lands this pin comes out and the equality goes into the test above.
    @Test(
        "pin: the starting quarterback takes most but not all of his team's snaps, because slot 0 is redrawn per snap (#27)",
        .tags(.pin))
    func startingQuarterbackTakesMostSnaps() {
        var starterSnaps = 0
        var teamSnaps = 0
        for result in Self.sample {
            let world = TestWorld.world(seed: result.game.rawValue)
            for (team, _) in result.rosters.sorted(by: { $0.key < $1.key }) {
                guard let starter = world.depthChart(of: team).starter(at: .quarterback) else {
                    continue
                }
                let scrimmage = result.plays.filter {
                    $0.outcome.kind.isScrimmagePlay && $0.situation.possession == team
                }
                let counts = scrimmage.snapCounts(rosters: result.rosters)
                starterSnaps += counts[starter] ?? 0
                teamSnaps += scrimmage.count
            }
        }
        let share = Double(starterSnaps) / Double(max(1, teamSnaps))
        #expect(share > 0.9, "the starter took \(starterSnaps) of \(teamSnaps) snaps")
        #expect(
            share < 1.0,
            "the starter took every snap — #27 landed: delete this pin and assert equality above")
    }
}
