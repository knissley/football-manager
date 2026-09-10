import FMCore
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

    /// Which two clubs of the eight-team world play the *n*-th game.
    ///
    /// It used to be team 0 against team 1 in every one of the ninety, which was fine
    /// while a seed re-rolled the whole league: ninety seeds meant ninety different
    /// grounds. Since [decision 215](../../../../docs/design-decisions.md) the
    /// franchises are curated, so that would be the same fixture in the same stadium
    /// ninety times over, and a sample of one building is thinner than it looks — a punt
    /// downed inside the ten is the sort of thing noise, altitude and a roof all reach.
    /// Walking the pairing visits all eight grounds, both domes among them.
    private static func pairing(_ seed: UInt64) -> (home: Int, away: Int) {
        let teams = UInt64(TestWorld.shape.totalTeams)
        // One ahead by at least one and at most `teams - 1`, so the away side is never
        // the home side and the fixture list is not eight repeats of the same rotation.
        let home = seed % teams
        return (Int(home), Int((home + 1 + (seed / teams) % (teams - 1)) % teams))
    }

    private static func result(seed: UInt64) -> GameResult {
        let (home, away) = pairing(seed)
        return TestWorld.game(seed: seed, home: home, away: away)
    }

    /// Enough games that a rare-but-reachable case is not a coin flip.
    ///
    /// A safety happens about three times in a hundred team-games, so forty games left
    /// roughly a one-in-eleven chance of seeing none — and this suite duly went red for
    /// it once field position improved enough to make being backed up rare. Simulated
    /// once and shared, because six assertions over one stream costs what one used to.
    ///
    /// Ninety is not comfortable for the rarest case in here. Illegal touching needs a
    /// punt that is downed or run out of bounds — about 1.1 a game — and then a 1.8%
    /// roll on top, so ninety games expect two of them and see none about one time in
    /// six. Measured on this sample: 101 such punts and two flags. It is the case to
    /// widen the sample for if this suite goes red on it again, and widening means more
    /// fixtures rather than only more seeds.
    private static let sampled: [PlayRecord] = (UInt64(1)...90).flatMap { result(seed: $0).plays }

    private static func plays() -> [PlayRecord] { sampled }

    @Test("Every play kind the engine claims to model actually occurs", .tags(.contract))
    func everyKindIsReachable() {
        let seen = Set(Self.plays().map(\.outcome.kind))
        for kind in PlayKind.allCases where Self.unreachableKinds[kind] == nil {
            #expect(seen.contains(kind), "no snap in ninety games was a \(kind)")
        }
    }

    @Test("Every play ending the engine claims to model actually occurs", .tags(.contract))
    func everyEndingIsReachable() {
        let seen = Set(Self.plays().map(\.outcome.endedIn))
        for ending in PlayEnding.allCases where Self.unreachableEndings[ending] == nil {
            #expect(seen.contains(ending), "no play in ninety games ended in \(ending)")
        }
    }

    /// The other direction, and the one that keeps the register honest: when a milestone
    /// makes one of these reachable, this fails and the entry has to come out.
    @Test("The unreachable register describes the engine as it is", .tags(.contract))
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

    /// Fouls are the same question as play kinds, and the answer was worse: `Foul` has
    /// thirty-three cases, every one of them with its yardage, its side and its
    /// automatic-first-down rule already settled in `FMCore`, and the engine threw twelve
    /// of them. There was no offensive pass interference in the league, nobody was ever
    /// called for lining up wrong, and a kicker could be run over with impunity.
    @Test("Every foul the rules define actually gets called", .tags(.contract))
    func everyFoulIsCalled() {
        // Nothing. Every foul in the book gets thrown.
        let unreachable: [Foul: String] = [:]

        let called = Set(Self.plays().flatMap(\.outcome.penalties).map(\.foul))
        for foul in Foul.allCases where unreachable[foul] == nil {
            #expect(called.contains(foul), "\(foul) was never called in ninety games")
        }
        for (foul, reason) in unreachable {
            #expect(!called.contains(foul), "\(foul) is called now (was: \(reason))")
        }
    }

    /// The mirror of an unreachable case: a credit handed to somebody who did not earn
    /// it. Coverage tests cannot see this one — the role *is* produced — so it needs its
    /// own assertion, and the shape that catches it is who the credits land on.
    ///
    /// Every run play used to credit all four defensive linemen with a tackle in the
    /// blocking loop, before anybody had touched the ball. The role looked healthy and
    /// the leaderboard was nonsense.
    @Test("Tackles are spread across the defence, not banked by the front", .tags(.contract))
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
    @Test("Every position on a roster gets on the field", .tags(.contract))
    func everyPositionPlays() {
        // Nothing. Every position a team carries takes a snap: the specialists on kicks,
        // the fullback in a heavy grouping and on the coverage units, the third
        // linebacker when the defence is in base. It was three positions short of this
        // before the kicking game and personnel substitution were wired in.
        let unreachable: [Position: String] = [:]
        let seen = Set(Self.plays().flatMap(\.outcome.participants).map(\.position))
        for position in Position.allCases where unreachable[position] == nil {
            #expect(seen.contains(position), "no \(position) took a snap in ninety games")
        }
        for (position, reason) in unreachable {
            #expect(
                !seen.contains(position),
                "\(position) plays now — take it out of the register (was: \(reason))")
        }
    }

    /// Roles are the same shape of gap: a role nothing ever credits is a hole in every
    /// query built on top of it. `.tackler` went missing on sacks exactly this way.
    @Test("Every play role gets credited to somebody", .tags(.contract))
    func everyRoleIsCredited() {
        let unreachable: [PlayRole: String] = [
            .assistTackler: "M5 — the crude resolver credits a single tackler."
        ]
        let seen = Set(Self.plays().flatMap(\.outcome.participants).map(\.role))
        for role in PlayRole.allCases where unreachable[role] == nil {
            #expect(seen.contains(role), "nobody in ninety games was credited as \(role)")
        }
        for (role, reason) in unreachable {
            #expect(
                !seen.contains(role),
                "\(role) is credited now — take it out of the register (was: \(reason))")
        }
    }
}
