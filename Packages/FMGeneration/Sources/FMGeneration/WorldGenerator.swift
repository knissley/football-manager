import FMCore
import FMRandom

/// The world a career starts in, built from one seed.
///
/// **The single entry point.** Before this existed, every caller assembled a world its
/// own way: `worldgen` gave team *n* a strength offset interpolated from its index, the
/// harness gave every team the league average and so played four hundred games between
/// identical clubs, and each test suite built two rosters from a bare stream. Three
/// different leagues, none of them the one the game ships.
///
/// A world is a fold over generation, in the order below, and every stage draws from its
/// own labelled substream ([ADR-0003](../../../../docs/adr/0003-deterministic-seeded-simulation.md)).
/// Labelled rather than sequential so that a stage added later — name ledgers, rookies,
/// draft history — shifts nothing that was generated before it.
public enum WorldGenerator {

    /// The optional parts of a world.
    ///
    /// A league, its teams, their rosters and depth charts are what a world *is* and are
    /// always built. A draft pipeline and a set of rivalries are worth about as much
    /// generation again, and a caller that wants to simulate one game — a play-by-play
    /// printer, a resolver test — has no use for either. Asking for less is not a second
    /// way to build a world; it is the same world with parts of it not drawn.
    public struct Parts: OptionSet, Sendable, Hashable {

        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let draftPipeline = Parts(rawValue: 1 << 0)
        public static let rivalries = Parts(rawValue: 1 << 1)

        /// Everything. The default, and what a career starts from.
        public static let all: Parts = [.draftPipeline, .rivalries]

        /// The league, its teams and their rosters, and nothing else.
        public static let teamsAndRosters: Parts = []
    }

    /// Why a world could not be generated.
    ///
    /// One case today. It is an enum rather than a typealias because the stages after the
    /// league — rosters, the pipeline, rivalries — will acquire their own ways to fail,
    /// and a caller that switches over this should have to say what it does about them.
    public enum GenerationFailure: Error, Sendable, Hashable {
        case league(LeagueGenerator.GenerationFailure)

        public var explanations: [String] {
            switch self {
            case .league(let failure): return failure.explanations
            }
        }
    }

    /// Everything a generated world is made of.
    ///
    /// Membership is by identifier throughout, and the lookups are dictionaries — but
    /// nothing here is ever *iterated* to produce output. `teams` is the ordered list, by
    /// identifier, and every consumer walks that ([rule 2](../../../../CLAUDE.md)).
    public struct GeneratedWorld: Sendable {

        /// The seed the whole world came from. Carried so a caller can print what it is
        /// looking at, and so a saved world can say what would regenerate it.
        public let seed: UInt64
        /// The season the world is generated *in*: ages, contracts and the draft pipeline
        /// are all relative to it.
        public let season: Int
        public let league: League
        /// Every team, ordered by identifier. The stable order everything else walks.
        public let teams: [Team]
        public let colleges: [College]
        public let draftPipeline: [DraftClassGenerator.GeneratedClass]
        /// Ordered by the pair's identifiers, as `RivalryGenerator` returns them.
        public let rivalries: [Rivalry]

        private let strengthsByTeam: [TeamID: RosterGenerator.Strength]
        private let identitiesByTeam: [TeamID: SchemeIdentity.Identity]
        private let rostersByTeam: [TeamID: [Player]]
        private let chartsByTeam: [TeamID: DepthChart]
        /// Every player in the league by identifier, which is the shape `GameSetup` wants.
        public let players: [PlayerID: Player]

        init(
            seed: UInt64,
            season: Int,
            league: League,
            teams: [Team],
            colleges: [College],
            strengths: [TeamID: RosterGenerator.Strength],
            identities: [TeamID: SchemeIdentity.Identity],
            rosters: [TeamID: [Player]],
            charts: [TeamID: DepthChart],
            players: [PlayerID: Player],
            draftPipeline: [DraftClassGenerator.GeneratedClass],
            rivalries: [Rivalry]
        ) {
            self.seed = seed
            self.season = season
            self.league = league
            self.teams = teams
            self.colleges = colleges
            self.strengthsByTeam = strengths
            self.identitiesByTeam = identities
            self.rostersByTeam = rosters
            self.chartsByTeam = charts
            self.players = players
            self.draftPipeline = draftPipeline
            self.rivalries = rivalries
        }

        public func team(_ id: TeamID) -> Team? { teams.first { $0.id == id } }

        /// The team at a position in the league's stable order. What a tool that says
        /// "the world at seed *n*, home team *i*, away team *j*" is actually asking for.
        public func team(at index: Int) -> Team? {
            index >= 0 && index < teams.count ? teams[index] : nil
        }

        public func roster(of id: TeamID) -> [Player] { rostersByTeam[id] ?? [] }
        public func depthChart(of id: TeamID) -> DepthChart { chartsByTeam[id] ?? DepthChart() }
        public func strength(of id: TeamID) -> RosterGenerator.Strength {
            strengthsByTeam[id] ?? .leagueAverage
        }
        /// The scheme a team plays and the one its roster was built for. `played` always
        /// equals `team.scheme`; the two differ on the minority of clubs that inherited a
        /// roster assembled for something else. `nil` for a team that is not in this world.
        public func identity(of id: TeamID) -> SchemeIdentity.Identity? { identitiesByTeam[id] }
    }

    // MARK: - Strength

    /// How far the best and worst clubs sit from the middle, in overall points.
    ///
    /// Eight either way. `RosterGenerator.Strength` already describes what the number
    /// means; this is how wide a *league* is drawn.
    public static let strengthSpread = 8.0

    /// One strength per team, drawn from the seed and centred on the league.
    ///
    /// Two properties, and both matter. The draw is uniform on ±`strengthSpread` rather
    /// than Gaussian, because a league wants genuine contenders and genuine rebuilds at
    /// its edges and a normal draw puts almost everyone in the middle. And the result is
    /// centred — the mean offset is subtracted from every team — so the league's overall
    /// mean does not wander with the seed and a calibration run at seed 7 is comparable
    /// with one at seed 11.
    ///
    /// Nothing here reads the team's index. The *n*-th draw belongs to the *n*-th team in
    /// identifier order, which is what makes the world reproducible, but the value owes
    /// nothing to the position — which is exactly the bug this replaces, where team 0 was
    /// always the worst club in the league and team 31 always the best.
    static func strengths(
        count: Int, using random: inout SplittableRandom
    )
        -> [RosterGenerator.Strength]
    {
        guard count > 0 else { return [] }
        var offsets: [Double] = []
        offsets.reserveCapacity(count)
        for _ in 0..<count {
            offsets.append(random.nextDouble(in: -strengthSpread..<strengthSpread))
        }
        let mean = offsets.reduce(0, +) / Double(count)
        return offsets.map { RosterGenerator.Strength(offset: $0 - mean) }
    }

    // MARK: - Generation

    /// Labels for the substreams. Each stage draws from `root.split(label)`, which depends
    /// only on the root seed and the label — so a stage may grow, or a new one be inserted,
    /// without moving anything else in the world.
    private enum Stream: UInt64 {
        case colleges = 1
        case league = 2
        case strength = 3
        case team = 4
        case draft = 5
        case rivalries = 6
    }

    /// The world at a seed.
    ///
    /// - Parameters:
    ///   - seed: the world seed. Everything below is derived from it and nothing else.
    ///   - shape: the league's structure. Validated before anything is generated.
    ///   - season: the season the world starts in.
    ///   - parts: which optional stages to draw. See `Parts`.
    ///   - collegeCount: how many colleges the world's players come from.
    ///   - draftShape: the shape of the draft classes in the pipeline.
    ///   - rivalrySettings: how much history the rivalries carry.
    /// - Returns: the world, or the reason the shape is not a league.
    public static func generate(
        seed: UInt64,
        shape: LeagueShape = .standard,
        season: Int,
        parts: Parts = .all,
        collegeCount: Int = 120,
        draftShape: DraftClassGenerator.ClassShape = .standard,
        rivalrySettings: RivalryGenerator.Settings = .standard
    ) -> Result<GeneratedWorld, GenerationFailure> {
        let root = SplittableRandom(seed: seed)

        var collegeRandom = root.split(Stream.colleges.rawValue)
        var colleges = NameGenerator.collegePool(count: collegeCount, using: &collegeRandom)
        if colleges.isEmpty {
            // A world with nowhere to have played is not a world, and a roster generator
            // that has to guess would be a second way to build one.
            colleges = [College(name: "Fallback State", profile: .midMajor)]
        }

        var leagueRandom = root.split(Stream.league.rawValue)
        let generatedLeague: LeagueGenerator.GeneratedLeague
        switch LeagueGenerator.league(shape: shape, using: &leagueRandom) {
        case .failure(let failure): return .failure(.league(failure))
        case .success(let value): generatedLeague = value
        }

        // Identifier order, explicitly, rather than the order the league generator happened
        // to append in. Everything downstream walks this array.
        let teams = generatedLeague.teams.sorted { $0.id.rawValue < $1.id.rawValue }

        var strengthRandom = root.split(Stream.strength.rawValue)
        let drawn = strengths(count: teams.count, using: &strengthRandom)

        var strengths: [TeamID: RosterGenerator.Strength] = [:]
        var identities: [TeamID: SchemeIdentity.Identity] = [:]
        var rosters: [TeamID: [Player]] = [:]
        var charts: [TeamID: DepthChart] = [:]
        var players: [PlayerID: Player] = [:]
        var playerIDs = IdentifierSequence<PlayerSubject>()

        for (index, team) in teams.enumerated() {
            let strength = drawn[index]
            strengths[team.id] = strength

            // The team's own substream, so a change to what a team draws cannot move the
            // team after it.
            var teamRandom = root.split(Stream.team.rawValue, UInt64(index))

            // The scheme the club plays is already the team's. What is drawn here is
            // whether the roster it inherited suits it.
            let builtFor = SchemeIdentity.builtFor(playing: team.scheme, using: &teamRandom)
            identities[team.id] = SchemeIdentity.Identity(played: team.scheme, builtFor: builtFor)

            // The board a roster's draft history is written against is this world's own
            // draft: as deep as its classes and as wide as its league.
            let roster = RosterGenerator.roster(
                strength: strength, builtFor: builtFor, season: season, colleges: colleges,
                board: DraftHistory.Board(
                    rounds: draftShape.rounds, picksPerRound: teams.count),
                ids: &playerIDs, using: &teamRandom)
            rosters[team.id] = roster
            charts[team.id] = RosterGenerator.depthChart(from: roster)
            for player in roster { players[player.id] = player }
        }

        var pipeline: [DraftClassGenerator.GeneratedClass] = []
        if parts.contains(.draftPipeline) {
            var draftRandom = root.split(Stream.draft.rawValue)
            pipeline = DraftClassGenerator.pipeline(
                firstDraftSeason: season, teams: teams.count, shape: draftShape,
                colleges: colleges, identifiers: &playerIDs, using: &draftRandom)
        }

        var rivalries: [Rivalry] = []
        if parts.contains(.rivalries) {
            var rivalryRandom = root.split(Stream.rivalries.rawValue)
            rivalries = RivalryGenerator.rivalries(
                league: generatedLeague.league, teams: teams, currentSeason: season,
                settings: rivalrySettings, using: &rivalryRandom)
        }

        return .success(
            GeneratedWorld(
                seed: seed,
                season: season,
                league: generatedLeague.league,
                teams: teams,
                colleges: colleges,
                strengths: strengths,
                identities: identities,
                rosters: rosters,
                charts: charts,
                players: players,
                draftPipeline: pipeline,
                rivalries: rivalries))
    }
}
