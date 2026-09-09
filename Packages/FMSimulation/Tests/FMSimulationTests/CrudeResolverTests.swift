import FMCore
import FMGeneration
import FMRandom
import Testing

@testable import FMSimulation

/// The constraints in this suite are the point of the crude resolver, not a nicety.
///
/// A resolver that drew a result and decorated it with plausible reasons would let the
/// analysis layer appear to work while reading fiction — the named risk of building M2
/// against scaffolding ([ADR-0012](../../../../docs/adr/0012-play-resolver-seam.md)).
/// These assert the causal chain and the outcome describe the same play.
@Suite("Crude resolver")
struct CrudeResolverTests {

    private func world(seed: UInt64 = 5) -> (GameSetup, [PlayerID: Player]) {
        var random = SplittableRandom(seed: seed)
        var colleges = NameGenerator.collegePool(count: 20, using: &random)
        if colleges.isEmpty { colleges = [College(name: "Fallback State", profile: .midMajor)] }

        var ids = IdentifierSequence<PlayerSubject>()
        let homeRoster = RosterGenerator.roster(
            season: 2030, colleges: colleges, ids: &ids, using: &random)
        let awayRoster = RosterGenerator.roster(
            season: 2030, colleges: colleges, ids: &ids, using: &random)

        var players: [PlayerID: Player] = [:]
        for player in homeRoster + awayRoster { players[player.id] = player }

        let setup = GameSetup(
            game: GameID(1),
            home: GameTeam(
                id: TeamID(1), depthChart: RosterGenerator.depthChart(from: homeRoster),
                scheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder)),
            away: GameTeam(
                id: TeamID(2), depthChart: RosterGenerator.depthChart(from: awayRoster),
                scheme: TeamScheme(offense: .airRaid, defense: .nickelMatch)),
            players: players,
            seed: seed)
        return (setup, players)
    }

    private func game(seed: UInt64 = 5) -> GameResult {
        GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
            .simulate(world(seed: seed).0)
    }

    // MARK: - The causal chain

    /// Every slot a decision point names must be a player who was credited. A decision
    /// referencing somebody who was not on the play is a reason attached to nobody.
    @Test("Every slot named in a decision is a credited participant")
    func decisionsNameRealPlayers() {
        for seed in UInt64(1)...4 {
            for play in game(seed: seed).plays where !play.decisions.isEmpty {
                let credited = Set(play.outcome.participants.map(\.slot))
                for decision in play.decisions {
                    #expect(
                        credited.contains(decision.primary),
                        "\(decision.kind) named slot \(decision.primary.rawValue), uncredited")
                    if !decision.secondary.isNone {
                        #expect(
                            credited.contains(decision.secondary),
                            "\(decision.kind) named slot \(decision.secondary.rawValue), uncredited"
                        )
                    }
                }
            }
        }
    }

    /// A sack must have a rusher who actually got there, and it must be *that* rusher.
    /// This is the example ADR-0012 uses, so it is the one to hold hardest.
    @Test("A sack is credited to the rusher whose pressure caused it")
    func sacksNameTheRusherWhoGotThere() {
        var sacks = 0
        for seed in UInt64(1)...6 {
            for play in game(seed: seed).plays where play.outcome.kind == .sack {
                sacks += 1
                guard
                    let decision = play.decisions.first(where: {
                        $0.kind == .throwDecision && $0.detail == ThrowDecision.sack.rawValue
                    })
                else {
                    Issue.record("a sack with no sack decision")
                    continue
                }
                let rusher = decision.secondary
                #expect(
                    play.decisions.contains {
                        $0.kind == .pressureAllowed && $0.secondary == rusher
                    },
                    "the sacking rusher never beat anybody")
                #expect(
                    play.outcome.participants.contains {
                        $0.slot == rusher && ($0.role == .tackler || $0.role == .passRusher)
                    },
                    "the sacking rusher was not credited")
            }
        }
        #expect(sacks > 0, "six games produced no sacks at all")
    }

    /// An interception has to name the defender who took it, and the ending has to agree
    /// with the catch decision.
    @Test("An interception agrees with its catch decision")
    func interceptionsAgree() {
        var picks = 0
        for seed in UInt64(1)...8 {
            for play in game(seed: seed).plays where play.outcome.endedIn == .intercepted {
                picks += 1
                let attempt = play.decisions.first { $0.kind == .catchAttempt }
                #expect(
                    attempt?.detail == CatchResult.intercepted.rawValue,
                    "an interception whose catch decision says otherwise")
                #expect(play.outcome.finalSpot != nil, "an interception with no spot")
            }
        }
        #expect(picks > 0, "eight games produced no interceptions")
    }

    /// A completion names a receiver, and that receiver is the one the throw went to.
    @Test("A completion's target is the receiver the quarterback read to")
    func completionsNameTheirTarget() {
        for seed in UInt64(1)...4 {
            for play in game(seed: seed).plays
            where play.outcome.kind == .pass && play.outcome.yards > 0 {
                guard
                    let thrown = play.decisions.first(where: {
                        $0.kind == .throwDecision && $0.detail == ThrowDecision.primary.rawValue
                    })
                else { continue }
                let target = thrown.secondary
                #expect(
                    play.decisions.contains { $0.kind == .ballArrival && $0.primary == target },
                    "the ball arrived to somebody else")
                #expect(
                    play.outcome.participants.contains { $0.slot == target },
                    "the target was not credited")
            }
        }
    }

    /// Decisions happen in order. A ball arriving before it was thrown is a causal chain
    /// nobody can read.
    @Test("Decisions are ordered in time")
    func decisionsAreOrdered() {
        for seed in UInt64(1)...4 {
            for play in game(seed: seed).plays {
                let throwTick = play.decisions.first { $0.kind == .throwDecision }?.tick
                let arrival = play.decisions.first { $0.kind == .ballArrival }?.tick
                if let throwTick, let arrival {
                    #expect(arrival > throwTick, "the ball arrived before the throw")
                }
                let katch = play.decisions.first { $0.kind == .catchAttempt }?.tick
                if let arrival, let katch {
                    #expect(katch >= arrival, "the catch resolved before the ball got there")
                }
            }
        }
    }

    // MARK: - Attribution

    /// Every snap credits real players, which is what M2's grades and awards have to
    /// work with.
    @Test("Every scrimmage play credits real players from the roster")
    func participantsAreRealPlayers() {
        let (setup, players) = world()
        let result = GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
            .simulate(setup)

        for play in result.plays where play.outcome.kind.isScrimmagePlay {
            #expect(
                play.outcome.participants.isEmpty == false, "play \(play.index) credited nobody")
            for participant in play.outcome.participants {
                #expect(players[participant.player] != nil, "credited a player who does not exist")
                #expect(
                    players[participant.player]?.position == participant.position,
                    "credited a player at somebody else's position")
            }
        }
    }

    /// Offence and defence live on opposite sides of the slot convention. A defender
    /// credited in an offensive slot would make every team-derived statistic wrong.
    @Test("Participants sit on the correct side of the slot convention")
    func slotsMatchSides() {
        for play in game().plays {
            for participant in play.outcome.participants {
                let isOffensiveRole: Bool
                switch participant.role {
                case .passer, .rusher, .receiver, .target, .blocker: isOffensiveRole = true
                case .passRusher, .coverage, .tackler, .assistTackler: isOffensiveRole = false
                default: continue
                }
                #expect(
                    participant.slot.isOffense == isOffensiveRole,
                    "\(participant.role) in slot \(participant.slot.rawValue)")
            }
        }
    }

    /// Rotation means backups play. If the same eleven took every snap, depth on a
    /// roster would be invisible.
    @Test("More than a starting eleven appears over a game")
    func rotationReachesBackups() {
        let result = game()
        let appeared = Set(result.plays.flatMap { $0.outcome.participants.map(\.player) })
        #expect(appeared.count > 30, "only \(appeared.count) players took a snap")
    }

    // MARK: - Determinism

    @Test("The same seed resolves identically")
    func deterministic() {
        let first = game(seed: 12)
        let second = game(seed: 12)
        #expect(first.plays.map(\.outcome) == second.plays.map(\.outcome))
        #expect(first.plays.map(\.decisions) == second.plays.map(\.decisions))
    }
}
