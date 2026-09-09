import FMCore
import FMGeneration
import FMRandom
import Testing

@testable import FMSimulation

/// Which parts of the event vocabulary the engine can actually reach.
///
/// `PlayKind.scramble` sat in `FMCore` for a while with nothing able to produce it: the
/// case existed, the box score knew how to count it, and no snap ever was one. A unit
/// test cannot catch that, because every unit involved is correct on its own — the type
/// is fine, the resolver is fine, and the gap is that they never meet.
///
/// So this suite asserts the *join*: sim a batch of games and check what came out
/// against the vocabulary that exists. It is deliberately two-directional. A case the
/// engine cannot yet produce has to be named in the register below with a reason, and
/// the moment one of those *starts* being produced the test fails too, so the register
/// cannot quietly rot into a list of things that used to be true.
///
/// See `docs/roadmap.md` — "Audit owed at the end of M1".
@Suite("Vocabulary coverage")
struct VocabularyCoverageTests {

    /// Cases the crude engine is knowingly unable to produce, and why.
    ///
    /// Every entry is a real gap, not an excuse: each names the milestone that closes
    /// it. Deleting an entry is how a milestone reports that it landed.
    static let unreachableKinds: [PlayKind: String] = [:]

    static let unreachableEndings: [PlayEnding: String] = [
        .blocked: "M3 — no rush lane exists on a kick, so nothing can get a hand up."
    ]

    private static func result(seed: UInt64) -> GameResult {
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

        return GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
            .simulate(
                GameSetup(
                    game: GameID(1),
                    home: GameTeam(
                        id: TeamID(1), depthChart: RosterGenerator.depthChart(from: homeRoster),
                        scheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder)),
                    away: GameTeam(
                        id: TeamID(2), depthChart: RosterGenerator.depthChart(from: awayRoster),
                        scheme: TeamScheme(offense: .airRaid, defense: .nickelMatch)),
                    players: players, seed: seed))
    }

    /// Enough games that a rare-but-reachable case is not a coin flip. A safety turns up
    /// about once in fifteen games, so forty is the floor rather than a round number.
    private static func plays(seeds: ClosedRange<UInt64> = 1...40) -> [PlayRecord] {
        seeds.flatMap { result(seed: $0).plays }
    }

    @Test("Every play kind the engine claims to model actually occurs")
    func everyKindIsReachable() {
        let seen = Set(Self.plays().map(\.outcome.kind))
        for kind in PlayKind.allCases where Self.unreachableKinds[kind] == nil {
            #expect(seen.contains(kind), "no snap in forty games was a \(kind)")
        }
    }

    @Test("Every play ending the engine claims to model actually occurs")
    func everyEndingIsReachable() {
        let seen = Set(Self.plays().map(\.outcome.endedIn))
        for ending in PlayEnding.allCases where Self.unreachableEndings[ending] == nil {
            #expect(seen.contains(ending), "no play in forty games ended in \(ending)")
        }
    }

    /// The other direction, and the one that keeps the register honest: when a milestone
    /// makes one of these reachable, this fails and the entry has to come out.
    @Test("The unreachable register describes the engine as it is")
    func registerIsCurrent() {
        let plays = Self.plays()
        let kinds = Set(plays.map(\.outcome.kind))
        let endings = Set(plays.map(\.outcome.endedIn))

        for (kind, reason) in Self.unreachableKinds {
            #expect(
                !kinds.contains(kind),
                "\(kind) is produced now — take it out of the register (was: \(reason))")
        }
        for (ending, reason) in Self.unreachableEndings {
            #expect(
                !endings.contains(ending),
                "\(ending) is produced now — take it out of the register (was: \(reason))")
        }
    }

    /// The mirror of an unreachable case: a credit handed to somebody who did not earn
    /// it. Coverage tests cannot see this one — the role *is* produced — so it needs its
    /// own assertion, and the shape that catches it is who the credits land on.
    ///
    /// Every run play used to credit all four defensive linemen with a tackle in the
    /// blocking loop, before anybody had touched the ball. The role looked healthy and
    /// the leaderboard was nonsense.
    @Test("Tackles are spread across the defence, not banked by the front")
    func tacklesReachTheWholeDefense() {
        let tackles = Self.plays()
            .flatMap(\.outcome.participants)
            .filter { $0.role == .tackler }

        var byGroup: [PositionGroup: Int] = [:]
        for tackle in tackles { byGroup[tackle.position.group, default: 0] += 1 }
        let total = tackles.count

        #expect(total > 0)
        let front = (byGroup[.edge] ?? 0) + (byGroup[.defensiveInterior] ?? 0)
        let secondLevel = byGroup[.linebacker] ?? 0
        let secondary = (byGroup[.cornerback] ?? 0) + (byGroup[.safety] ?? 0)
        let levels = [
            ("front", front), ("linebackers", secondLevel), ("secondary", secondary),
        ]
        for (name, count) in levels {
            #expect(
                Double(count) / Double(total) > 0.1,
                "the \(name) made \(count) of \(total) tackles")
        }

        // Roughly one tackle per snap that ends in contact. Well over that means
        // somebody is being credited for being on the field.
        let contactPlays = Self.plays().filter { $0.outcome.kind.isScrimmagePlay }.count
        #expect(
            Double(total) / Double(contactPlays) < 1.1,
            "\(total) tackles across \(contactPlays) plays from scrimmage")
    }

    /// And the same question one level down: a position that exists, is generated onto
    /// every roster, and never takes a snap.
    ///
    /// This is how the kicking game was found out. Every team had a kicker, a punter and
    /// a long snapper, and none of them had ever been on the field — the resolver read
    /// kick accuracy and punt power off the *quarterback's* slot, so a team's kicker had
    /// no bearing on whether it made kicks.
    @Test("Every position on a roster gets on the field")
    func everyPositionPlays() {
        let unreachable: [Position: String] = [
            // Fullbacks are on rosters but the crude engine fields one back, and it is
            // the halfback. The formation layer at M5 is what puts him on the field.
            .fullback: "M5 — the crude engine fields a single back.",
            // He is on the field for every kick; a clean snap is simply not an event.
            // The cost is that he cannot be hurt, because injuries are drawn from the
            // participants, and that is what M2's kicking game has to fix.
            .longSnapper: "M2 — nothing a long snapper does well is recordable yet.",
        ]
        let seen = Set(Self.plays().flatMap(\.outcome.participants).map(\.position))
        for position in Position.allCases where unreachable[position] == nil {
            #expect(seen.contains(position), "no \(position) took a snap in forty games")
        }
        for (position, reason) in unreachable {
            #expect(
                !seen.contains(position),
                "\(position) plays now — take it out of the register (was: \(reason))")
        }
    }

    /// Roles are the same shape of gap: a role nothing ever credits is a hole in every
    /// query built on top of it. `.tackler` went missing on sacks exactly this way.
    @Test("Every play role gets credited to somebody")
    func everyRoleIsCredited() {
        let unreachable: [PlayRole: String] = [
            .assistTackler: "M5 — the crude resolver credits a single tackler."
        ]
        let seen = Set(Self.plays().flatMap(\.outcome.participants).map(\.role))
        for role in PlayRole.allCases where unreachable[role] == nil {
            #expect(seen.contains(role), "nobody in forty games was credited as \(role)")
        }
        for (role, reason) in unreachable {
            #expect(
                !seen.contains(role),
                "\(role) is credited now — take it out of the register (was: \(reason))")
        }
    }
}
