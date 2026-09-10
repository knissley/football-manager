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

        let reconciled = enforcingOneTitleGamePerSeason(seeded, using: &random)
        return enforcingTheCeiling(reconciled, in: currentSeason)
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

    /// A new world tops out at heated, and this is the last word on it.
    ///
    /// The seeded past gives texture; the first genuine blood feud should be one the
    /// player caused. Nothing in the draw enforces that — weighting a storied pair's years
    /// is not a ceiling, and measured over the first sixty seeds through
    /// `WorldGenerator.generate`, nine worlds opened with a bitter rivalry in them, the
    /// hottest at 76.042 against a `bitter` floor of 65.
    ///
    /// **Last, after the reconciliation above, and that ordering is the rule.** Applying
    /// the ceiling inside `history(for:)` looked equivalent and was not: the reconciliation
    /// demotes every title game after the first claim on a season, so a pair whose title
    /// game the ceiling had already dropped freed that season and the next claimant *kept*
    /// a title game it would otherwise have lost — four points of undecayed weight, on a
    /// pair the ceiling had already been past. On seed 51 that promoted pair 2-3's 2027
    /// event back to a title game and the pair from 51.356 to 53.812. Nothing crossed the
    /// band in those sixty worlds, but 13 of their 3,720 pairs sit in [61, 65), where a
    /// promotion crosses it — which would leave decision 170 true of a sample rather than
    /// true as a rule. Running last, no stage can raise a pair after the ceiling has
    /// spoken.
    private static func enforcingTheCeiling(
        _ rivalries: [Rivalry], in season: Int
    ) -> [Rivalry] {
        rivalries.map { rivalry in
            var result = rivalry
            result.history = cappedBelowBitter(rivalry, in: season)
            return result
        }
    }

    /// The least history that satisfies the ceiling.
    ///
    /// Applied to the invented log rather than to `heat(in:)`, and that is the whole
    /// point: clamping the projection would clamp lived history too, and the band the
    /// player is playing towards would be unreachable. Nothing downstream can tell a
    /// capped history from any other, because a capped history is just a shorter one.
    ///
    /// What goes is the *smallest* event that brings the pair under the band — the cut
    /// that leaves it hottest while still short of bitter — because the memorable years
    /// are what the seeded past is for, and taking the biggest one is the maximal cut:
    /// dropping the event doing the most work landed seed 48 at 51.284 and seed 15 at
    /// 56.101, mid-band, having removed exactly the event that made the pair worth
    /// reading about. Should no single event be enough — no drawn history has come close,
    /// the hottest being 76.042 against a heaviest single event of 20 — the heaviest goes
    /// and the search runs again, so the set grows from the largest and stays as small as
    /// the arithmetic allows. Ties go to the earliest event.
    ///
    /// Dropped rather than downgraded: a lighter event invented in place of a heavier one
    /// is a fabrication, where a shorter history is just a shorter history. The event that
    /// earned an earned origin is never dropped, or the origin becomes an assertion with
    /// nothing behind it — which also bounds the loop, since an origin's floor plus its
    /// founding event is 22 at most, well under the band.
    ///
    /// No draw happens here, so the substream is exactly where it would have been and a
    /// pair the ceiling does not reach keeps the history it already had.
    private static func cappedBelowBitter(_ rivalry: Rivalry, in season: Int) -> [RivalryEvent] {
        let founding = foundingKind(for: rivalry.origin)
        var kept = rivalry.history

        func folded(_ history: [RivalryEvent]) -> Rivalry {
            Rivalry(pair: rivalry.pair, origin: rivalry.origin, history: history)
        }

        while folded(kept).heat(in: season) == .bitter {
            let evidence = founding.flatMap { kind in kept.firstIndex { $0.kind == kind } }

            // Measured as what the log is worth without each event rather than by the
            // event's own weight, so decay is accounted for without a second copy of the
            // fold. `sufficient` keeps the gentlest cut that finishes the job — the one
            // leaving the pair hottest — and `heaviest` the one that makes the most
            // progress when nothing single is enough.
            var sufficient: (index: Int, intensity: Double)?
            var heaviest: (index: Int, intensity: Double)?
            for index in kept.indices where index != evidence {
                var without = kept
                without.remove(at: index)
                let trimmed = folded(without)
                let intensity = trimmed.intensity(in: season)

                if trimmed.heat(in: season) == .bitter {
                    if let best = heaviest, best.intensity <= intensity { continue }
                    heaviest = (index, intensity)
                } else {
                    if let best = sufficient, best.intensity >= intensity { continue }
                    sufficient = (index, intensity)
                }
            }

            // Unreachable given the floors above. Written as a stop rather than a
            // precondition because the alternative to being wrong about that is a
            // generator that never returns.
            guard let dropped = sufficient ?? heaviest else { break }
            kept.remove(at: dropped.index)
        }

        return kept
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
    ///
    /// Uncapped, deliberately: weighting the draw is not a ceiling, and a storied pair can
    /// come out of a decade of January hot enough to open `bitter`. What brings it back is
    /// `enforcingTheCeiling`, which runs after the whole league's history has been
    /// reconciled rather than here — see its note for why the ordering is the rule and not
    /// a detail.
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
