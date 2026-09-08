/// The structural shape of a league.
///
/// Configuration, not a constant — the league is meant to be customisable
/// ([decision 15](../../../../docs/design-decisions.md)). But some shapes are
/// not leagues, and the validator says *why* rather than merely refusing.
///
/// ## What can be changed, and when
///
/// **Structure is fixed at world creation.** Conferences, divisions and team
/// counts determine the schedule, the playoff bracket, and every record in the
/// league's history. Changing them mid-career would invalidate all three, in the
/// same way and for the same reason that sliders lock at creation
/// ([decision 26](../../../../docs/design-decisions.md)).
///
/// **Cosmetics are editable at any time** — conference, division, team and city
/// names, colours and uniforms — because none of them mean anything to the
/// simulation. They are `AppearanceEvent`s like a player's gear, so a replay of
/// a game from four seasons ago shows the uniform worn then.
///
/// Adding a team to a running league is a different feature: expansion, with a
/// draft and a schedule rebuild. Deferred, and deliberately not the same thing
/// as editing configuration.
public struct LeagueShape: Sendable, Hashable, Codable {

    public let conferences: Int
    public let divisionsPerConference: Int
    public let teamsPerDivision: Int
    public let regularSeasonGames: Int
    /// How many teams from each conference reach the playoffs.
    public let playoffTeamsPerConference: Int

    public init(
        conferences: Int,
        divisionsPerConference: Int,
        teamsPerDivision: Int,
        regularSeasonGames: Int,
        playoffTeamsPerConference: Int
    ) {
        self.conferences = conferences
        self.divisionsPerConference = divisionsPerConference
        self.teamsPerDivision = teamsPerDivision
        self.regularSeasonGames = regularSeasonGames
        self.playoffTeamsPerConference = playoffTeamsPerConference
    }

    public var teamsPerConference: Int {
        divisionsPerConference * teamsPerDivision
    }

    public var totalTeams: Int {
        conferences * teamsPerConference
    }

    public var divisionCount: Int {
        conferences * divisionsPerConference
    }

    /// How many teams reach the playoffs in total.
    public var playoffField: Int {
        conferences * playoffTeamsPerConference
    }

    /// Wild cards are the playoff places not claimed by winning a division.
    public var wildCardsPerConference: Int {
        playoffTeamsPerConference - divisionsPerConference
    }

    // MARK: - Presets

    /// The real shape: 32 teams, two conferences of four divisions of four,
    /// seventeen games, seven playoff teams a side.
    public static let standard = LeagueShape(
        conferences: 2, divisionsPerConference: 4, teamsPerDivision: 4,
        regularSeasonGames: 17, playoffTeamsPerConference: 7)

    /// Twelve teams, and the smallest shape that still exercises everything
    /// structural: two conferences, two divisions each, and **three** teams per
    /// division so a division race has a genuine middle and tiebreakers between
    /// three-way ties are reachable.
    ///
    /// This is the default for tests that care about league structure.
    public static let compact = LeagueShape(
        conferences: 2, divisionsPerConference: 2, teamsPerDivision: 3,
        regularSeasonGames: 12, playoffTeamsPerConference: 3)

    /// Eight teams — the absolute floor at which the structure is still a
    /// league: two conferences, two divisions each, two teams per division.
    ///
    /// Fast, and adequate for scheduling and bracket mechanics. It is *not*
    /// adequate for tiebreakers: with two teams in a division, a division race
    /// is a single head-to-head pair and most tiebreaker rules never fire. Use
    /// `.compact` for anything that touches standings logic.
    public static let minimal = LeagueShape(
        conferences: 2, divisionsPerConference: 2, teamsPerDivision: 2,
        regularSeasonGames: 6, playoffTeamsPerConference: 2)
}

extension LeagueShape {

    /// Why a shape is not a league.
    ///
    /// Named cases rather than a boolean, because a player who has just tried to
    /// build a one-conference league deserves to be told that the championship
    /// game would have nobody to play — not that their input was invalid.
    public enum ValidationFailure: Sendable, Hashable, Codable {
        case tooFewConferences(found: Int)
        case tooFewDivisions(found: Int)
        case tooFewTeamsPerDivision(found: Int)
        case oddTeamCount(found: Int)
        case playoffFieldExcludesDivisionWinners(field: Int, divisions: Int)
        case playoffFieldExceedsConference(field: Int, teams: Int)
        case tooFewGames(found: Int, minimum: Int)
        case tooManyGames(found: Int, maximum: Int)

        /// Written for the player, not the log.
        public var explanation: String {
            switch self {
            case .tooFewConferences(let found):
                return
                    "A league needs at least two conferences — with \(found), the championship "
                    + "game would have nobody to play. What you have is a conference, not a league."
            case .tooFewDivisions(let found):
                return "Each conference needs at least one division; this has \(found)."
            case .tooFewTeamsPerDivision(let found):
                return
                    "A division needs at least two teams — with \(found), winning it means "
                    + "beating nobody."
            case .oddTeamCount(let found):
                return
                    "\(found) teams leaves someone without an opponent every week. Leagues need "
                    + "an even number of teams."
            case .playoffFieldExcludesDivisionWinners(let field, let divisions):
                return
                    "\(field) playoff places per conference cannot admit \(divisions) division "
                    + "winners. Winning a division has to be worth something."
            case .playoffFieldExceedsConference(let field, let teams):
                return
                    "\(field) playoff places per conference, but only \(teams) teams to fill "
                    + "them. Everyone would qualify."
            case .tooFewGames(let found, let minimum):
                return
                    "\(found) games is not enough to play every divisional rival home and away, "
                    + "which needs at least \(minimum)."
            case .tooManyGames(let found, let maximum):
                return
                    "\(found) games is more than there are opponents for. The most anyone can "
                    + "play is \(maximum), meeting every other team twice."
            }
        }
    }

    /// Everything wrong with this shape, in a stable order.
    ///
    /// Returns all failures rather than the first, so a player fixing a custom
    /// league is not led through them one at a time.
    public var validationFailures: [ValidationFailure] {
        var failures: [ValidationFailure] = []

        if conferences < 2 { failures.append(.tooFewConferences(found: conferences)) }
        if divisionsPerConference < 1 {
            failures.append(.tooFewDivisions(found: divisionsPerConference))
        }
        if teamsPerDivision < 2 {
            failures.append(.tooFewTeamsPerDivision(found: teamsPerDivision))
        }

        // Structural counts have to be sane before anything derived from them
        // is worth reporting on.
        guard failures.isEmpty else { return failures }

        if totalTeams % 2 != 0 { failures.append(.oddTeamCount(found: totalTeams)) }

        if playoffTeamsPerConference < divisionsPerConference {
            failures.append(
                .playoffFieldExcludesDivisionWinners(
                    field: playoffTeamsPerConference, divisions: divisionsPerConference))
        }
        if playoffTeamsPerConference > teamsPerConference {
            failures.append(
                .playoffFieldExceedsConference(
                    field: playoffTeamsPerConference, teams: teamsPerConference))
        }

        let minimumGames = 2 * (teamsPerDivision - 1)
        let maximumGames = 2 * (totalTeams - 1)
        if regularSeasonGames < minimumGames {
            failures.append(.tooFewGames(found: regularSeasonGames, minimum: minimumGames))
        }
        if regularSeasonGames > maximumGames {
            failures.append(.tooManyGames(found: regularSeasonGames, maximum: maximumGames))
        }

        return failures
    }

    public var isValid: Bool {
        validationFailures.isEmpty
    }
}
