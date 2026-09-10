// The calibration targets, with the season and the source every band came from.
//
// Nothing here is typed from memory. Every sourced band was computed by
// scripts/calibration-sources.py from the nflverse play-by-play data set (built from the
// league's official play-by-play feed) and, for personnel, box counts and pressure, the
// nflverse participation data from Next Gen Stats. The script prints each row's value in
// every season and the band the policy produces; if a number below cannot be reproduced
// by the script, the script wins. The table in docs/match-engine.md#calibration is
// generated from this array (`simharness --targets-markdown`) and a test fails if the two
// disagree.
//
// Band policy (also in the script's header): a row's band spans the sourced seasons'
// values, widened on each side by the larger of 5% of the mean and twice the standard
// error of a 400-game harness run, the error measured by resampling whole games. Per-play
// and per-drive rates come from 2023 and 2024. A row that depends on a rule the 2025
// rulebook changed is sourced from 2025 alone, and the 2024 row is kept beside it so
// `--rulebook 2024` can check the mechanism against the season it was played in.

import FMCore

/// The rulebook season the engine is being calibrated to.
///
/// D1 (#41) moves this onto `Rules` as `Rules.rulebookSeason` and deletes this constant
/// along with `rules(forRulebook:)` below. Until then `Rules.standard` still carries 2024
/// values, so the rows sourced under 2024 kickoff rules warn at startup by design: that is
/// the list D2 (#46) has to make land.
let engineRulebookSeason = 2025

/// The seasons the harness can build rules for.
let supportedRulebooks = [2024, 2025]

/// The `Rules` in force under a season's rulebook, built here from data.
///
/// 2024 is today's `Rules.standard`. 2025 is `.standard` with the kickoff touchback at the
/// receiving team's 35 (2025 rulebook, Rule 6). The 2025 rulebook also permits a
/// declared onside kick whenever a team trails, at any point in the game; `Rules` has no
/// field for when an onside kick is permitted — the fourth-quarter-only gate lives in
/// `BaselineCaller.kicksOnside` — so the 2025 variant carries the touchback change alone.
/// The onside rows still pair a 2024 and a 2025 variant, and one of the pair is current
/// under each rulebook; what neither run does yet is play the 2025 onside rule, which
/// waits for D1 (#41) to add the field.
func rules(forRulebook season: Int) -> Rules? {
    switch season {
    case 2024:
        return .standard
    case 2025:
        var rules = Rules.standard
        rules.kickoffTouchbackOwnYard = 35
        return rules
    default:
        return nil
    }
}

/// A rule area a calibration row can depend on.
enum RuleArea: String, CaseIterable, Sendable {
    case kickoff
    case overtime
    case onsideKick
    case passInterference
    case tryAttempt
}

/// A change to a rule area, in the season it took effect, with the rulebook it is in.
struct RuleChange: Sendable {
    let area: RuleArea
    let season: Int
    let citation: String

    /// Every change that can invalidate a row. A row is stale under a rulebook when one of
    /// these falls between the season it was sourced from and the rulebook it is compared
    /// against — in either direction, because a 2025 band is as wrong for a 2024 run as a
    /// 2024 band is for a 2025 one.
    static let all: [RuleChange] = [
        RuleChange(
            area: .tryAttempt, season: 2015,
            citation: "2015 rulebook, Rule 11 (Scoring), Section 3 (Try): snap from the 15"),
        RuleChange(
            area: .kickoff, season: 2024,
            citation:
                "2024 rulebook, Rule 6 (Free Kicks): the dynamic kickoff, touchback to the 30"),
        RuleChange(
            area: .kickoff, season: 2025,
            citation: "2025 rulebook, Rule 6 (Free Kicks): touchback to the 35"),
        RuleChange(
            area: .onsideKick, season: 2025,
            citation:
                "2025 rulebook, Rule 6 (Free Kicks): a declared onside kick whenever trailing"),
        RuleChange(
            area: .overtime, season: 2025,
            citation:
                "2025 rulebook, Rule 16 (Overtime Procedures): both teams possess in the regular season"
        ),
    ]
}

/// The real-league season(s) a band was derived from, or the admission that none was.
enum TargetSeason: Sendable, Equatable {
    case seasons(ClosedRange<Int>)
    case unsourced

    static func season(_ year: Int) -> TargetSeason { .seasons(year...year) }

    var printed: String {
        switch self {
        case .seasons(let range) where range.lowerBound == range.upperBound:
            return "\(range.lowerBound)"
        case .seasons(let range):
            return "\(range.lowerBound)-\(range.upperBound % 100)"
        case .unsourced:
            return "-"
        }
    }
}

/// One calibration row: what the sport does, in which season, according to whom.
struct CalibrationTarget: Sendable {
    /// Stable identifier. A rule-sensitive row has one variant per rulebook, `id.<season>`,
    /// and the harness prints every variant of an id it reports.
    let id: String
    let label: String
    /// `nil` for a row with no band at all.
    let low: Double?
    let high: Double?
    let season: TargetSeason
    /// The reference, named by title. Empty for an unsourced row.
    let source: String
    let rulesSensitiveTo: Set<RuleArea>
    /// Whether a miss counts as a failure. `false` for rows the harness cannot yet measure
    /// or whose sample is too thin to fail on.
    let gate: Bool
    let decimals: Int
    /// Printed after the value: `%` for a share, `x` for a ratio.
    let unit: String
    /// What the row measures when that is not obvious from the label, and any way the
    /// harness's measurement differs from the source's definition.
    let note: String

    init(
        id: String, label: String, low: Double?, high: Double?, season: TargetSeason,
        source: String, rulesSensitiveTo: Set<RuleArea>, gate: Bool, decimals: Int = 1,
        unit: String = "", note: String = ""
    ) {
        self.id = id
        self.label = label
        self.low = low
        self.high = high
        self.season = season
        self.source = source
        self.rulesSensitiveTo = rulesSensitiveTo
        self.gate = gate
        self.decimals = decimals
        self.unit = unit
        self.note = note
    }

    func format(_ value: Double) -> String {
        let scale = pow10(decimals)
        let scaled = Int((value * scale).rounded())
        // Format the magnitude and prefix the sign: a value in (-1, 0) has a whole part of
        // zero, which carries no sign of its own.
        let sign = scaled < 0 ? "-" : ""
        let magnitude = abs(scaled)
        let whole = magnitude / Int(scale)
        if decimals == 0 { return "\(sign)\(whole)\(unit)" }
        var digits = "\(magnitude % Int(scale))"
        while digits.count < decimals { digits = "0" + digits }
        return "\(sign)\(whole).\(digits)\(unit)"
    }

    var band: String {
        guard let low, let high else { return "none" }
        return "\(format(low).dropLast(unit.count))-\(format(high).dropLast(unit.count))"
    }

    private func pow10(_ power: Int) -> Double {
        var result = 1.0
        for _ in 0..<power { result *= 10 }
        return result
    }

    // MARK: - The table as a whole

    /// Source titles in order of first use, keyed `S1`, `S2`, … for the printed rows.
    static var sources: [(key: String, title: String)] {
        var seen: [String] = []
        for target in all where !target.source.isEmpty && !seen.contains(target.source) {
            seen.append(target.source)
        }
        return seen.enumerated().map { ("S\($0.offset + 1)", $0.element) }
    }

    static func sourceKey(for source: String) -> String {
        sources.first { $0.title == source }?.key ?? "-"
    }

    /// The rows whose band was sourced under a different rulebook than `rulebook`, with the
    /// change that separates them.
    static func stale(under rulebook: Int) -> [String: RuleChange] {
        var stale: [String: RuleChange] = [:]
        for target in all {
            guard case .seasons(let sourced) = target.season else { continue }
            let earliest = min(sourced.lowerBound, rulebook)
            let latest = max(sourced.upperBound, rulebook)
            for change in RuleChange.all
            where target.rulesSensitiveTo.contains(change.area) && change.season > earliest
                && change.season <= latest
            {
                stale[target.id] = change
                break
            }
        }
        return stale
    }

    /// The calibration table for docs/match-engine.md, between its markers.
    static func markdownTable() -> String {
        var lines = [
            "| Row | Target | Season | Sensitive to | Source | Gate | Definition and notes |",
            "| --- | --- | --- | --- | --- | --- | --- |",
        ]
        for target in all {
            let sensitivity = target.rulesSensitiveTo.map(\.rawValue).sorted().joined(
                separator: ", ")
            lines.append(
                "| \(target.label) | \(target.band)\(target.unit) | "
                    + "\(target.season == .unsourced ? "unsourced" : target.season.printed) | "
                    + "\(sensitivity.isEmpty ? "—" : sensitivity) | "
                    + "\(target.source.isEmpty ? "—" : sourceKey(for: target.source)) | "
                    + "\(target.gate ? "yes" : "no") | \(target.note.isEmpty ? "—" : target.note) |"
            )
        }
        lines.append("")
        for source in sources {
            lines.append("- **\(source.key)** — \(source.title)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - The rows

    static let playByPlay = "nflverse play-by-play data, regular-season games"
    static let participation =
        "nflverse participation data from Next Gen Stats, regular-season games"

    static let all: [CalibrationTarget] = [
        // The passing and running game, per team per game.
        CalibrationTarget(
            id: "points", label: "points", low: 20.6, high: 24.1, season: .seasons(2023...2024),
            source: playByPlay, rulesSensitiveTo: [], gate: true),
        CalibrationTarget(
            id: "passingYards", label: "passing yards", low: 221.7, high: 248.1,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note: "Gross: yards on completions, sacks not deducted, which is what the harness sums."
        ),
        CalibrationTarget(
            id: "rushingYards", label: "rushing yards", low: 94.7, high: 110.4,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note:
                "Designed runs only, as the harness counts them; the league's figure adds scrambles and kneels."
        ),
        CalibrationTarget(
            id: "yardsPerCarry", label: "yards per carry", low: 3.9, high: 4.6,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note: "Designed runs only."),
        CalibrationTarget(
            id: "completionPercentage", label: "completion percentage", low: 61.2, high: 68.6,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note:
                "Completions over attempts, read from the record's pass result. Counted as a gain of a yard or more it read about three points low (2023–24 positive-only rate: 61.1–62.4); the zero-or-fewer row is the gap."
        ),
        CalibrationTarget(
            id: "sackRate", label: "sack rate per dropback", low: 6.1, high: 7.2,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true),
        CalibrationTarget(
            id: "interceptionRate", label: "interception rate", low: 1.9, high: 2.6,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note: "Per pass attempt."),
        CalibrationTarget(
            id: "thirdDownConversion", label: "third down conversion", low: 36.7, high: 41.7,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true),
        CalibrationTarget(
            id: "playsFromScrimmage", label: "plays from scrimmage", low: 59.0, high: 66.3,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note: "Rushes, passes, sacks, scrambles, kneels and spikes."),
        CalibrationTarget(
            id: "penaltiesPerGame", label: "penalties (both teams)", low: 10.8, high: 13.5,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note: "Accepted fouls per game."),
        CalibrationTarget(
            id: "thirdDownDistance", label: "average third down distance", low: 6.6, high: 7.4,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true),
        CalibrationTarget(
            id: "firstDownGain", label: "yards gained on first down", low: 5.1, high: 5.8,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note: "Scrimmage plays on first down."),
        CalibrationTarget(
            id: "yardsPerAttempt", label: "yards per pass attempt", low: 6.6, high: 7.5,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note: "Gross."),
        CalibrationTarget(
            id: "yardsPerPlay", label: "yards per play", low: 5.0, high: 5.8,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note:
                "The harness's definition: gross pass, designed-run and sack yards over every scrimmage play, scramble yards excluded. The league's net figure was 5.5–5.7."
        ),
        CalibrationTarget(
            id: "yardsPerCompletion", label: "yards per completion", low: 10.3, high: 11.5,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true),

        // The shape of the stream.
        CalibrationTarget(
            id: "playsPerGame", label: "plays per game", low: 152, high: 170,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            decimals: 0,
            note: "Every play including kicks, tries and flag-only snaps; not timeouts."),
        CalibrationTarget(
            id: "tiesPerGame", label: "ties per game", low: 0.000, high: 0.010,
            season: .season(2025), source: playByPlay, rulesSensitiveTo: [.overtime], gate: true,
            decimals: 3,
            note:
                "One tie in 272 games in 2025; the band is that rate widened by twice the resampled standard error of a 400-game run, per the policy."
        ),
        CalibrationTarget(
            id: "overtimeRate", label: "games reaching overtime", low: 3.0, high: 7.3,
            season: .season(2025), source: playByPlay, rulesSensitiveTo: [.overtime], gate: true,
            unit: "%", note: "Fourteen of 272 games in 2025."),
        CalibrationTarget(
            id: "overtimeLength", label: "seconds played per overtime", low: 355, high: 463,
            season: .season(2025), source: playByPlay, rulesSensitiveTo: [.overtime], gate: true,
            decimals: 0,
            note:
                "Game clock used by the last snap of the period. Both teams possessing lengthened it from about 345 in 2023–24."
        ),

        // Injuries.
        CalibrationTarget(
            id: "playerGamesLost", label: "player-games lost per season", low: 40, high: 90,
            season: .unsourced, source: "", rulesSensitiveTo: [], gate: false,
            note: "Nobody has cited this band; it is not in the play-by-play."),

        // The endgame.
        CalibrationTarget(
            id: "scramblesPerGame", label: "scrambles per game", low: 3.5, high: 4.2,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true),
        CalibrationTarget(
            id: "kneelsPerGame", label: "kneels per game", low: 1.3, high: 1.8,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true),
        CalibrationTarget(
            id: "spikesPerGame", label: "spikes per game", low: 0.1, high: 0.4,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true),
        CalibrationTarget(
            id: "timeoutsPerGame", label: "timeouts spent per game", low: 7.1, high: 8.2,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note: "Team timeouts, both teams."),

        // The season, which the harness cannot play until M3.
        CalibrationTarget(
            id: "winTotalSigma", label: "spread of team win totals (σ)", low: 2.5, high: 3.8,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: false,
            note:
                "Standard deviation of regular-season wins across the 32 teams, ties as a half. Not measurable before a schedule exists (M3)."
        ),

        // Where the points come from.
        CalibrationTarget(
            id: "pointsFromTouchdowns", label: "share of points from touchdowns", low: 62.6,
            high: 70.1, season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [],
            gate: true, unit: "%", note: "Six per touchdown; tries counted separately."),
        CalibrationTarget(
            id: "pointsFromFieldGoals", label: "share of points from field goals", low: 21.1,
            high: 24.6, season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [],
            gate: true, unit: "%"),

        // Who is on the field.
        CalibrationTarget(
            id: "personnel11", label: "snaps in 11 personnel", low: 62.3, high: 71.9,
            season: .seasons(2023...2024), source: participation, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "packageNickel", label: "snaps against nickel", low: 61.6, high: 69.2,
            season: .seasons(2023...2024), source: participation, rulesSensitiveTo: [], gate: true,
            unit: "%", note: "Five defensive backs on the field."),
        CalibrationTarget(
            id: "packageBase", label: "snaps against base", low: 20.2, high: 25.0,
            season: .seasons(2023...2024), source: participation, rulesSensitiveTo: [], gate: true,
            unit: "%", note: "Four defensive backs on the field."),
        CalibrationTarget(
            id: "ypcEvenCount", label: "yards per carry, even count", low: 4.3, high: 5.0,
            season: .seasons(2023...2024), source: participation, rulesSensitiveTo: [], gate: true,
            note:
                "First and ten, designed runs; blockers are five linemen plus tight ends plus extra backs, the box is eleven less the defensive backs, as the harness counts it. By defenders actually in the box the figure was 4.5–4.7."
        ),
        CalibrationTarget(
            id: "ypcOutnumberedByOne", label: "yards per carry, outnumbered by one", low: 3.9,
            high: 5.1, season: .seasons(2023...2024), source: participation, rulesSensitiveTo: [],
            gate: true,
            note:
                "Same construction, one more in the box than blockers. The sport's gap between even and outnumbered is small: 4.3–4.6 against 4.5–4.7."
        ),

        // Who took the snap: player-snaps per team-game on plays from scrimmage, by the
        // roster position group of each man the record says was on the field. Read off
        // `PlayRecord.onField` and the game's roster table, never off the credits.
        CalibrationTarget(
            id: "snaps.quarterback", label: "quarterback snaps per team-game", low: 58.9,
            high: 66.8, season: .seasons(2023...2024), source: participation, rulesSensitiveTo: [],
            gate: true,
            note:
                "Player-snaps on plays from scrimmage by roster position group, the source's participation feed scaled to plays from scrimmage. One a snap by construction on both sides."
        ),
        CalibrationTarget(
            id: "snaps.backfield", label: "backfield snaps per team-game", low: 64.2, high: 72.4,
            season: .seasons(2023...2024), source: participation, rulesSensitiveTo: [], gate: true,
            note: "Running backs and fullbacks."),
        CalibrationTarget(
            id: "snaps.receiver", label: "receiver snaps per team-game", low: 150.3, high: 171.0,
            season: .seasons(2023...2024), source: participation, rulesSensitiveTo: [], gate: true
        ),
        CalibrationTarget(
            id: "snaps.tightEnd", label: "tight end snaps per team-game", low: 77.1, high: 87.2,
            season: .seasons(2023...2024), source: participation, rulesSensitiveTo: [], gate: true
        ),
        CalibrationTarget(
            id: "snaps.offensiveLine", label: "offensive line snaps per team-game", low: 296.7,
            high: 332.9, season: .seasons(2023...2024), source: participation, rulesSensitiveTo: [],
            gate: true,
            note:
                "Five a snap by construction in the engine; the source has a sixth now and then."
        ),
        CalibrationTarget(
            id: "snaps.frontSeven", label: "front seven snaps per team-game", low: 363.7,
            high: 405.1, season: .seasons(2023...2024), source: participation, rulesSensitiveTo: [],
            gate: true,
            note:
                "Edge, interior and linebacker together: the source lists a four-man front's edge rushers as ends and a three-man front's as outside linebackers, so a narrower split would follow the scheme rather than the job."
        ),
        CalibrationTarget(
            id: "snaps.defensiveBack", label: "defensive back snaps per team-game", low: 285.5,
            high: 323.9, season: .seasons(2023...2024), source: participation, rulesSensitiveTo: [],
            gate: true, note: "Cornerbacks and safeties."),

        // The shape of a carry.
        CalibrationTarget(
            id: "carriesStuffed", label: "carries stuffed (0 or fewer)", low: 17.5, high: 19.9,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "carries2orFewer", label: "carries of 2 or fewer", low: 40.6, high: 46.5,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "carries10plus", label: "carries of 10 or more", low: 9.6, high: 11.2,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "carries20plus", label: "carries of 20 or more", low: 2.0, high: 2.5,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),

        // The shape of a dropback.
        CalibrationTarget(
            id: "dropbackLoss", label: "dropbacks losing yards", low: 7.2, high: 8.6,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%", note: "Sacks and completions or scrambles behind the line."),
        CalibrationTarget(
            id: "dropbackNoGain", label: "dropbacks with no gain", low: 30.3, high: 34.6,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%", note: "Almost all incompletions."),
        CalibrationTarget(
            id: "dropback10plus", label: "dropbacks of 10 or more", low: 23.8, high: 27.8,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "dropback20plus", label: "dropbacks of 20 or more", low: 7.7, high: 8.6,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "dropback40plus", label: "dropbacks of 40 or more", low: 1.0, high: 1.5,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "pressureRate", label: "pressure rate per dropback", low: 27.8, high: 32.3,
            season: .seasons(2023...2024), source: participation, rulesSensitiveTo: [], gate: true,
            unit: "%",
            note:
                "Next Gen Stats' pressure flag over attempts, sacks and scrambles. The harness counts a dropback on which a blocker lost."
        ),
        CalibrationTarget(
            id: "completionsZeroOrFewer", label: "completions for 0 or fewer yards", low: 4.0,
            high: 5.6, season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [],
            gate: true, unit: "%", note: "Share of all completions."),

        // How drives end.
        CalibrationTarget(
            id: "driveEndPunt", label: "drives ending in a punt", low: 32.8, high: 39.0,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "driveEndTouchdown", label: "drives ending in a touchdown", low: 19.2, high: 23.8,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "driveEndDowns", label: "drives ending on downs", low: 4.7, high: 6.3,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "drivesPerTeamGame", label: "drives per team-game", low: 10.2, high: 11.7,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true),
        CalibrationTarget(
            id: "playsPerDrive", label: "plays per drive", low: 5.3, high: 6.1,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note: "Offensive plays; the punt or kick that ends a drive is not one."),
        CalibrationTarget(
            id: "firstDownsPerTeamGame", label: "first downs per team-game", low: 16.6, high: 18.9,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note:
                "By rush or pass, as the harness counts; with penalty first downs the league had 17.8–18.3."
        ),
        CalibrationTarget(
            id: "drives3orFewer", label: "drives of 3 plays or fewer", low: 33.3, high: 39.0,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "drives4to7", label: "drives of 4 to 7", low: 33.7, high: 38.4,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "drives8plus", label: "drives of 8 or more", low: 25.9, high: 29.7,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "threeAndOut", label: "three and out", low: 19.1, high: 22.5,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%",
            note: "Drives of three offensive plays or fewer that end in a punt, over all drives."),
        CalibrationTarget(
            id: "redZoneTouchdownRate", label: "red zone touchdown rate", low: 51.1, high: 59.1,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%", note: "Drives with a snap inside the 20 that end in the offence's touchdown."
        ),

        // Field position. Where a drive starts follows from the kickoff, so the rows have a
        // variant per rulebook.
        CalibrationTarget(
            id: "averageStart.2025", label: "average start (own yard)", low: 29.1, high: 32.3,
            season: .season(2025), source: playByPlay, rulesSensitiveTo: [.kickoff], gate: true,
            note:
                "First snap of each drive. The 2025 touchback at the 35 moved this half a yard from 2024."
        ),
        CalibrationTarget(
            id: "averageStart.2024", label: "average start (own yard)", low: 28.6, high: 31.7,
            season: .season(2024), source: playByPlay, rulesSensitiveTo: [.kickoff], gate: true,
            note: "Kept for --rulebook 2024."),
        CalibrationTarget(
            id: "ownHalfStarts.2025", label: "drives starting in own half", low: 85.2, high: 94.2,
            season: .season(2025), source: playByPlay, rulesSensitiveTo: [.kickoff], gate: true,
            unit: "%", note: "Strictly inside the drive's own half; midfield is not."),
        CalibrationTarget(
            id: "ownHalfStarts.2024", label: "drives starting in own half", low: 85.6, high: 94.7,
            season: .season(2024), source: playByPlay, rulesSensitiveTo: [.kickoff], gate: true,
            unit: "%", note: "Kept for --rulebook 2024."),
        CalibrationTarget(
            id: "puntsPerTeamGame", label: "punts per team-game", low: 3.5, high: 4.4,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true),
        CalibrationTarget(
            id: "netPunt", label: "net punt (yards)", low: 39.4, high: 43.8,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note:
                "Distance less return yards, a touchback counted as a punt to the 20. The harness spots a punt touchback at the goal line, so its figure reads high on touchbacks; a harness fix, not a retune."
        ),
        CalibrationTarget(
            id: "twoPointTries", label: "two-point tries per team-game", low: 0.19, high: 0.29,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [.tryAttempt],
            gate: true, decimals: 2),
        CalibrationTarget(
            id: "twoPointConversion", label: "two-point conversion rate", low: 33.6, high: 62.3,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [.tryAttempt],
            gate: true, unit: "%",
            note: "Wide because the sport itself swung from 55% to 41% on about 130 tries a season."
        ),

        // Kicking.
        CalibrationTarget(
            id: "kickoffTouchbacks.2025", label: "kickoff touchbacks", low: 18.9, high: 22.4,
            season: .season(2025), source: playByPlay, rulesSensitiveTo: [.kickoff], gate: true,
            unit: "%", note: "Share of all kickoffs, onside kicks included in the denominator."),
        CalibrationTarget(
            id: "kickoffTouchbacks.2024", label: "kickoff touchbacks", low: 61.1, high: 67.6,
            season: .season(2024), source: playByPlay, rulesSensitiveTo: [.kickoff], gate: true,
            unit: "%", note: "Kept for --rulebook 2024."),
        CalibrationTarget(
            id: "fieldGoalsPerTeamGame", label: "field goals per team-game", low: 1.8, high: 2.2,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            note: "Attempts."),
        CalibrationTarget(
            id: "fieldGoalsUnder30", label: "field goals made, under 30", low: 92.1, high: 100.0,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "fieldGoals30to39", label: "field goals made, 30-39", low: 89.5, high: 99.3,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "fieldGoals40to49", label: "field goals made, 40-49", low: 72.4, high: 84.0,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "fieldGoals50plus", label: "field goals made, 50+", low: 63.7, high: 74.9,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "fieldGoalAttemptsUnder30", label: "attempts under 30, share", low: 19.1,
            high: 25.3, season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [],
            gate: true, unit: "%", note: "Share of field goal attempts by distance."),
        CalibrationTarget(
            id: "fieldGoalAttempts30to39", label: "attempts 30-39, share", low: 24.1, high: 31.9,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "fieldGoalAttempts40to49", label: "attempts 40-49, share", low: 23.8, high: 29.1,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "fieldGoalAttempts50plus", label: "attempts 50+, share", low: 19.2, high: 27.6,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "extraPointsMade", label: "extra points made", low: 91.0, high: 100.0,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [.tryAttempt],
            gate: true, unit: "%"),

        // Fourth down.
        CalibrationTarget(
            id: "fourthDownPunted", label: "fourth downs punted", low: 50.7, high: 58.6,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%", note: "Of fourth downs that ended in a punt, a field goal or a play."),
        CalibrationTarget(
            id: "fourthDownKicked", label: "fourth downs kicked", low: 23.1, high: 27.9,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "fourthDownWentForIt", label: "fourth downs gone for", low: 18.4, high: 21.3,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%", note: "Rising: 23.3% in 2025."),
        CalibrationTarget(
            id: "fourthDownAttempts", label: "fourth down attempts per team-game", low: 1.3,
            high: 1.6, season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [],
            gate: true),
        CalibrationTarget(
            id: "fourthDownConversion", label: "fourth down conversion rate", low: 48.3, high: 60.0,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "fourthAndOneWentForIt", label: "4th and 1: went for it", low: 62.8, high: 74.2,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%", note: "Rising: 76.3% in 2025."),

        // Turnovers and the return game.
        CalibrationTarget(
            id: "fumblesLost", label: "fumbles lost per team-game", low: 0.38, high: 0.55,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            decimals: 2, note: "On any play, kicks included."),
        CalibrationTarget(
            id: "fumblesKept", label: "fumbles kept per team-game", low: 0.46, high: 0.63,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            decimals: 2, note: "Fumbles the fumbling team recovered."),
        CalibrationTarget(
            id: "turnovers", label: "turnovers per team-game", low: 1.06, high: 1.37,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            decimals: 2, note: "Interceptions and fumbles lost; not downs."),
        CalibrationTarget(
            id: "nonOffensiveTouchdowns.2025", label: "touchdowns not by the offence", low: 0.09,
            high: 0.15, season: .season(2025), source: playByPlay, rulesSensitiveTo: [.kickoff],
            gate: true, decimals: 2, note: "Every return touchdown per team-game."),
        CalibrationTarget(
            id: "nonOffensiveTouchdowns.2024", label: "touchdowns not by the offence", low: 0.08,
            high: 0.14, season: .season(2024), source: playByPlay, rulesSensitiveTo: [.kickoff],
            gate: true, decimals: 2, note: "Kept for --rulebook 2024."),
        CalibrationTarget(
            id: "defensiveReturnTouchdowns", label: "interception and fumble return TDs", low: 0.05,
            high: 0.14, season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [],
            gate: true, decimals: 2, note: "Per team-game."),
        CalibrationTarget(
            id: "kickReturnTouchdowns.2025", label: "kickoff and punt return TDs", low: 0.02,
            high: 0.06, season: .season(2025), source: playByPlay, rulesSensitiveTo: [.kickoff],
            gate: true, decimals: 2, note: "Per team-game; 21 in 2025 against 14 in 2024."),
        CalibrationTarget(
            id: "kickReturnTouchdowns.2024", label: "kickoff and punt return TDs", low: 0.01,
            high: 0.04, season: .season(2024), source: playByPlay, rulesSensitiveTo: [.kickoff],
            gate: true, decimals: 2, note: "Kept for --rulebook 2024."),
        CalibrationTarget(
            id: "onsideKicks.2025", label: "onside kicks per game", low: 0.15, high: 0.24,
            season: .season(2025), source: playByPlay, rulesSensitiveTo: [.onsideKick], gate: true,
            decimals: 2, note: "Kicks described as onside in the official play description."),
        CalibrationTarget(
            id: "onsideKicks.2024", label: "onside kicks per game", low: 0.13, high: 0.23,
            season: .season(2024), source: playByPlay, rulesSensitiveTo: [.onsideKick], gate: true,
            decimals: 2, note: "Kept for --rulebook 2024."),
        CalibrationTarget(
            id: "onsideRecovery.2025", label: "onside kicks recovered", low: 2.8, high: 16.4,
            season: .season(2025), source: playByPlay, rulesSensitiveTo: [.onsideKick], gate: false,
            unit: "%", note: "Five of 52 in 2025; too few kicks a season to fail on."),
        CalibrationTarget(
            id: "onsideRecovery.2024", label: "onside kicks recovered", low: 0.5, high: 11.5,
            season: .season(2024), source: playByPlay, rulesSensitiveTo: [.onsideKick], gate: false,
            unit: "%", note: "Kept for --rulebook 2024."),
        CalibrationTarget(
            id: "kickoffsReturned.2025", label: "kickoffs returned", low: 72.3, high: 80.0,
            season: .season(2025), source: playByPlay, rulesSensitiveTo: [.kickoff], gate: true,
            unit: "%", note: "Share of all kickoffs."),
        CalibrationTarget(
            id: "kickoffsReturned.2024", label: "kickoffs returned", low: 30.9, high: 35.9,
            season: .season(2024), source: playByPlay, rulesSensitiveTo: [.kickoff], gate: true,
            unit: "%", note: "Kept for --rulebook 2024."),
        CalibrationTarget(
            id: "puntsReturned", label: "punts returned", low: 40.5, high: 45.3,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%",
            note:
                "Share of punts fielded and run back; fair catches, downed and touchbacks are not."),

        // Backed up.
        CalibrationTarget(
            id: "snapsInsideOwn10", label: "snaps inside own 10", low: 1.55, high: 1.84,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            decimals: 2, note: "Scrimmage plays per team-game."),
        CalibrationTarget(
            id: "safeties", label: "safeties per team-game", low: 0.01, high: 0.05,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            decimals: 2),

        // Home field and weather.
        CalibrationTarget(
            id: "preSnapRoadVsHome", label: "pre-snap fouls, road vs home", low: 0.94, high: 1.19,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            decimals: 2, unit: "x",
            note:
                "The offence's pre-snap fouls per snap, road over home. The sport's edge is about 6%, not the fifth the band once claimed; the home side won 53–56% of decided games and outscored by 2–3 points, most of which is not the crowd."
        ),
        CalibrationTarget(
            id: "heavyRainPoints", label: "combined points, heavy rain vs dry", low: 2, high: 4,
            season: .unsourced, source: "", rulesSensitiveTo: [], gate: false,
            note:
                "Points lower in heavy rain. The play-by-play does not grade rain, so nobody has cited this; needs --games 1000."
        ),

        // Scoreboard.
        CalibrationTarget(
            id: "gamesWithin3", label: "games within 3", low: 19.6, high: 29.3,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "gamesWithin7", label: "games within 7", low: 44.5, high: 57.0,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            unit: "%"),

        // The ten most common accepted fouls, per game, both teams.
        CalibrationTarget(
            id: "penalty.offensiveHolding", label: "offensive holding per game", low: 1.89,
            high: 2.68, season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [],
            gate: true, decimals: 2),
        CalibrationTarget(
            id: "penalty.falseStart", label: "false start per game", low: 2.10, high: 2.66,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            decimals: 2),
        CalibrationTarget(
            id: "penalty.defensivePassInterference", label: "defensive pass interference per game",
            low: 0.88, high: 1.24, season: .seasons(2023...2024), source: playByPlay,
            rulesSensitiveTo: [.passInterference], gate: true, decimals: 2),
        CalibrationTarget(
            id: "penalty.defensiveHolding", label: "defensive holding per game", low: 0.55,
            high: 0.74, season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [],
            gate: true, decimals: 2),
        CalibrationTarget(
            id: "penalty.unnecessaryRoughness", label: "unnecessary roughness per game", low: 0.51,
            high: 0.73, season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [],
            gate: true, decimals: 2),
        CalibrationTarget(
            id: "penalty.delayOfGame", label: "delay of game per game", low: 0.48, high: 0.71,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            decimals: 2),
        CalibrationTarget(
            id: "penalty.offside", label: "defensive offside per game", low: 0.46, high: 0.66,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            decimals: 2),
        CalibrationTarget(
            id: "penalty.illegalFormation", label: "illegal formation per game", low: 0.13,
            high: 0.55, season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [],
            gate: true, decimals: 2, note: "Wide because 2024 called it twice as often as 2023."),
        CalibrationTarget(
            id: "penalty.roughingThePasser", label: "roughing the passer per game", low: 0.27,
            high: 0.43, season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [],
            gate: true, decimals: 2),
        CalibrationTarget(
            id: "penalty.neutralZoneInfraction", label: "neutral zone infraction per game",
            low: 0.27, high: 0.41, season: .seasons(2023...2024), source: playByPlay,
            rulesSensitiveTo: [], gate: true, decimals: 2),
    ]
}
