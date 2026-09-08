import FMCore
import FMRandom

/// Seeds the grudges a world starts with.
///
/// A new league is not a blank slate. These teams have been playing each other for
/// decades before you arrived, and the invented past is written as a **fabricated event
/// log in the same shape as a real one** — not as a starting intensity number. That is
/// what lets a pre-game write-up cite the history rather than report a figure nobody can
/// account for, and it means growth in M2 simply appends: nothing downstream can tell
/// invented history from lived history, because there is no difference.
public enum RivalryGenerator {

    /// How much history a world starts with.
    public struct Settings: Sendable, Hashable {

        /// Seasons of invented past. Long enough that a rivalry has a decade of decayed
        /// weight behind it, short enough that the log stays inspectable.
        public let seasonsOfHistory: Int
        /// Roughly how many events a divisional pair accumulates per season of history.
        public let eventsPerPairPerSeason: Double
        /// Cross-division pairs promoted to real rivalries, as a share of the league.
        public let extraRivalriesPerTeam: Double

        public init(
            seasonsOfHistory: Int = 12,
            eventsPerPairPerSeason: Double = 0.55,
            extraRivalriesPerTeam: Double = 0.8
        ) {
            self.seasonsOfHistory = seasonsOfHistory
            self.eventsPerPairPerSeason = eventsPerPairPerSeason
            self.extraRivalriesPerTeam = extraRivalriesPerTeam
        }

        public static let standard = Settings()
        /// Short history, for tests and for inspecting a log by eye.
        public static let brief = Settings(seasonsOfHistory: 4, extraRivalriesPerTeam: 0.4)
    }

    /// Every rivalry a world starts with, in a stable order.
    ///
    /// Divisional pairs are rivalries by construction — they play twice a year and share
    /// a bracket. Everything else has to be earned by something that happened, which is
    /// why the extras carry an origin explaining themselves.
    public static func rivalries(
        league: League,
        teams: [Team],
        currentSeason: Int,
        settings: Settings = .standard,
        using random: inout SplittableRandom
    ) -> [Rivalry] {
        let regions = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0.region) })
        var rivalries: [TeamPair: Rivalry] = [:]

        // Structural rivalries: everyone in your division.
        for division in league.divisions {
            let members = division.teams.sorted { $0.rawValue < $1.rawValue }
            for (index, team) in members.enumerated() {
                for other in members[(index + 1)...] {
                    let pair = TeamPair(team, other)
                    rivalries[pair] = Rivalry(pair: pair, origin: .divisional)
                }
            }
        }

        // Earned rivalries: a neighbour in another division, a January meeting, or
        // somebody who took a coach.
        let extras = Rounding.toNearest(
            Double(teams.count) * settings.extraRivalriesPerTeam / 2,
            clampedTo: 0...max(0, teams.count * 4))
        let candidates = crossDivisionCandidates(league: league, regions: regions)

        // Allocated by quota, not by priority order. Taking the best-ranked candidates
        // first meant whichever origin had the most candidates took every slot: there
        // are far more cross-region pairs than neighbours, and then far more neighbours
        // than the quota, so the mix collapsed to one origin either way.
        var ranked: [RivalryOrigin: [TeamPair]] = [:]
        for origin in RivalryOrigin.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            var group = candidates.filter { $0.origin == origin }.map(\.pair)
            random.shuffle(&group)
            ranked[origin] = group
        }

        // Neighbours first, because the crosstown game explains itself; the rest are
        // grudges that had to come from somewhere.
        let quotas: [(RivalryOrigin, Double)] = [
            (.regional, 0.5), (.postseason, 0.35), (.personal, 0.15),
        ]
        for (origin, share) in quotas {
            let wanted = Rounding.toNearest(Double(extras) * share, clampedTo: 0...extras)
            var taken = 0
            for pair in ranked[origin] ?? [] where taken < wanted && rivalries[pair] == nil {
                rivalries[pair] = Rivalry(pair: pair, origin: origin)
                taken += 1
            }
        }

        // A few pairs have simply been at it longer than the rest. Without them a new
        // world has no blood feud in it at all, and nothing that happens later can raise
        // the stakes above where everything already sits.
        let divisionalPairs = rivalries.values.filter { $0.origin == .divisional }
            .map(\.pair).sorted()
        var storiedCandidates = divisionalPairs
        random.shuffle(&storiedCandidates)
        let storied = Set(storiedCandidates.prefix(max(1, divisionalPairs.count / 12)))

        // Sorted before history is drawn, so the same world always invents the same past.
        let ordered = rivalries.values.sorted { $0.pair < $1.pair }
        let seeded = ordered.map { rivalry -> Rivalry in
            var result = rivalry
            result.history = history(
                for: rivalry, currentSeason: currentSeason, settings: settings,
                isStoried: storied.contains(rivalry.pair), using: &random)
            return result
        }

        return enforcingOneTitleGamePerSeason(seeded, using: &random)
    }

    /// Only one pair can have met for the championship in a given season.
    ///
    /// History is invented per pair, so three rivalries independently decided they
    /// played in the same title game — which reads as fabricated the instant anybody
    /// looks at two of them together. The extras become playoff eliminations, which is
    /// the same story one round earlier and can legitimately happen several times a year.
    private static func enforcingOneTitleGamePerSeason(
        _ rivalries: [Rivalry], using random: inout SplittableRandom
    ) -> [Rivalry] {
        var claimed: Set<Int> = []
        var result = rivalries

        for index in result.indices {
            for eventIndex in result[index].history.indices
            where result[index].history[eventIndex].kind == .titleGame {
                let event = result[index].history[eventIndex]
                guard claimed.insert(event.season).inserted else {
                    result[index].history[eventIndex] = RivalryEvent(
                        pair: event.pair, season: event.season, kind: .playoffElimination,
                        aggrievedTeam: random.nextBool(probability: 0.5)
                            ? event.pair.lower : event.pair.higher)
                    continue
                }
            }
        }
        return result
    }

    /// Pairs that could plausibly become something, and why.
    private static func crossDivisionCandidates(
        league: League, regions: [TeamID: Region]
    ) -> [(pair: TeamPair, origin: RivalryOrigin)] {
        let teams = league.teams.sorted { $0.rawValue < $1.rawValue }
        var candidates: [(pair: TeamPair, origin: RivalryOrigin)] = []

        for (index, team) in teams.enumerated() {
            for other in teams[(index + 1)...] {
                guard !league.areDivisionRivals(team, other) else { continue }
                let pair = TeamPair(team, other)

                // A neighbour in another division is the crosstown game. Everything else
                // had to come from something that happened — a January meeting, or
                // somebody crossing the divide — and either is available to any pair.
                if let a = regions[team], let b = regions[other], a == b {
                    candidates.append((pair, .regional))
                }
                candidates.append((pair, .postseason))
                candidates.append((pair, .personal))
            }
        }
        return candidates.sorted {
            ($0.origin.rawValue, $0.pair) < ($1.origin.rawValue, $1.pair)
        }
    }

    /// An invented past for one rivalry.
    ///
    /// Weighted so that most of what happened was ordinary and the memorable things are
    /// rare. A history where every year produced a controversial finish is not a history,
    /// it is a highlight reel, and every pairing in the league would open as a blood feud.
    public static func history(
        for rivalry: Rivalry,
        currentSeason: Int,
        settings: Settings,
        isStoried: Bool = false,
        using random: inout SplittableRandom
    ) -> [RivalryEvent] {
        var events: [RivalryEvent] = []
        let firstSeason = currentSeason - settings.seasonsOfHistory

        // Teams who do not play twice a year have less to argue about. A storied pair
        // has been at it every year for as long as anyone can remember.
        var rate =
            rivalry.origin == .divisional
            ? settings.eventsPerPairPerSeason : settings.eventsPerPairPerSeason * 0.45
        if isStoried { rate = min(1.0, rate * 1.9) }

        for season in firstSeason..<currentSeason {
            guard random.nextBool(probability: min(1.0, rate)) else { continue }
            let kind = kind(for: rivalry.origin, isStoried: isStoried, using: &random)
            let aggrieved =
                needsAggrievedTeam(kind)
                ? (random.nextBool(probability: 0.5) ? rivalry.pair.lower : rivalry.pair.higher)
                : nil
            events.append(
                RivalryEvent(
                    pair: rivalry.pair, season: season, kind: kind, aggrievedTeam: aggrieved))
        }

        // A rivalry that began in January or over a defection needs the event that
        // began it, or its origin is an assertion with nothing behind it.
        if let founding = foundingKind(for: rivalry.origin),
            !events.contains(where: { $0.kind == founding })
        {
            let season = random.nextInt(in: firstSeason...max(firstSeason, currentSeason - 1))
            events.append(
                RivalryEvent(
                    pair: rivalry.pair, season: season, kind: founding,
                    aggrievedTeam: needsAggrievedTeam(founding)
                        ? (random.nextBool(probability: 0.5)
                            ? rivalry.pair.lower : rivalry.pair.higher) : nil))
        }

        return events.sorted { ($0.season, $0.kind.rawValue) < ($1.season, $1.kind.rawValue) }
    }

    private static func foundingKind(for origin: RivalryOrigin) -> RivalryEventKind? {
        switch origin {
        case .postseason: return .playoffElimination
        case .personal: return .coachDefection
        case .divisional, .regional: return nil
        }
    }

    private static func needsAggrievedTeam(_ kind: RivalryEventKind) -> Bool {
        switch kind {
        case .playoffElimination, .controversialFinish, .streak, .coachDefection,
            .playerPoached, .upset:
            return true
        case .closeGame, .blowout, .decidedOnFinalPlay, .titleGame:
            return false
        }
    }

    /// What happened, weighted so ordinary years stay ordinary.
    private static func kind(
        for origin: RivalryOrigin, isStoried: Bool, using random: inout SplittableRandom
    ) -> RivalryEventKind {
        // A storied pair's memorable years are likelier to have been genuinely
        // memorable; the ordinary ones are still ordinary.
        let roll = isStoried ? 25 + random.next(upperBound: 75) : random.next(upperBound: 100)
        switch roll {
        case ..<30: return .closeGame
        case ..<48: return .blowout
        case ..<62: return .upset
        case ..<74: return .decidedOnFinalPlay
        case ..<82: return .streak
        case ..<88: return .playerPoached
        case ..<92: return .playoffElimination
        case ..<96: return .controversialFinish
        case ..<99: return .coachDefection
        default: return .titleGame
        }
    }
}
