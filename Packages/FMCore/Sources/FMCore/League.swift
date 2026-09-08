/// A division: the smallest competitive unit, and the one that grants a playoff place.
public struct Division: Sendable, Hashable, Codable, Identifiable {

    public let id: DivisionID
    /// Editable, like every other name in the world.
    public var name: String
    /// Membership, in a stable order. This is the **only** place a team's division is
    /// recorded — a team does not also carry its division, because two copies of one
    /// fact drift.
    public var teams: [TeamID]

    public init(id: DivisionID, name: String, teams: [TeamID]) {
        self.id = id
        self.name = name
        self.teams = teams
    }
}

public struct Conference: Sendable, Hashable, Codable, Identifiable {

    public let id: ConferenceID
    public var name: String
    public var divisions: [Division]

    public init(id: ConferenceID, name: String, divisions: [Division]) {
        self.id = id
        self.name = name
        self.divisions = divisions
    }

    public var teams: [TeamID] { divisions.flatMap(\.teams) }
}

/// The league's structure, and the teams filling it.
///
/// `shape` is fixed at world creation ([decision 105](../../../../docs/design-decisions.md)):
/// it determines the schedule, the bracket, and the meaning of every record in league
/// history, so it cannot move afterwards. Names can change whenever a player likes.
public struct League: Sendable, Hashable, Codable, Identifiable {

    public let id: LeagueID
    public var name: String
    public let shape: LeagueShape
    public var conferences: [Conference]

    public init(id: LeagueID, name: String, shape: LeagueShape, conferences: [Conference]) {
        self.id = id
        self.name = name
        self.shape = shape
        self.conferences = conferences
    }

    public var divisions: [Division] { conferences.flatMap(\.divisions) }
    public var teams: [TeamID] { conferences.flatMap(\.teams) }

    public func division(of team: TeamID) -> Division? {
        divisions.first { $0.teams.contains(team) }
    }

    public func conference(of team: TeamID) -> Conference? {
        conferences.first { $0.teams.contains(team) }
    }

    /// Two teams in the same division play twice a year and share a bracket. It is the
    /// sharpest structural relationship in the sport, and rivalry generation keys off it.
    public func areDivisionRivals(_ a: TeamID, _ b: TeamID) -> Bool {
        guard a != b, let division = division(of: a) else { return false }
        return division.teams.contains(b)
    }
}

extension League {

    /// Why a league does not match the shape it claims.
    ///
    /// `LeagueShape` validates the *shape*; this validates that the structure actually
    /// built matches it. Both exist because a valid shape filled in wrongly — a
    /// duplicated team, a short division — breaks the schedule just as thoroughly as an
    /// impossible shape, and fails much later and less legibly.
    public enum StructureFailure: Sendable, Hashable, Codable {
        case shapeIsInvalid([LeagueShape.ValidationFailure])
        case conferenceCountMismatch(found: Int, expected: Int)
        case divisionCountMismatch(conference: String, found: Int, expected: Int)
        case divisionSizeMismatch(division: String, found: Int, expected: Int)
        case teamInMultipleDivisions(TeamID)

        public var explanation: String {
            switch self {
            case .shapeIsInvalid(let failures):
                return failures.map(\.explanation).joined(separator: " ")
            case .conferenceCountMismatch(let found, let expected):
                return "The league has \(found) conferences but its shape calls for \(expected)."
            case .divisionCountMismatch(let conference, let found, let expected):
                return
                    "\(conference) has \(found) divisions but the shape calls for \(expected). "
                    + "Every conference has to be built the same way, or the bracket is unfair."
            case .divisionSizeMismatch(let division, let found, let expected):
                return
                    "\(division) has \(found) teams but the shape calls for \(expected). An "
                    + "uneven division means an uneven schedule."
            case .teamInMultipleDivisions(let team):
                return "Team \(team.rawValue) appears in more than one division."
            }
        }
    }

    /// Everything wrong with this league, in a stable order.
    ///
    /// All failures at once, for the same reason `LeagueShape` reports all of its
    /// ([decision 108](../../../../docs/design-decisions.md)).
    public var structureFailures: [StructureFailure] {
        let shapeFailures = shape.validationFailures
        guard shapeFailures.isEmpty else { return [.shapeIsInvalid(shapeFailures)] }

        var failures: [StructureFailure] = []

        if conferences.count != shape.conferences {
            failures.append(
                .conferenceCountMismatch(found: conferences.count, expected: shape.conferences))
        }

        for conference in conferences {
            if conference.divisions.count != shape.divisionsPerConference {
                failures.append(
                    .divisionCountMismatch(
                        conference: conference.name, found: conference.divisions.count,
                        expected: shape.divisionsPerConference))
            }
            for division in conference.divisions
            where division.teams.count != shape.teamsPerDivision {
                failures.append(
                    .divisionSizeMismatch(
                        division: division.name, found: division.teams.count,
                        expected: shape.teamsPerDivision))
            }
        }

        var seen: Set<TeamID> = []
        // Sorted so the report is stable regardless of how the league was assembled.
        for team in teams.sorted(by: { $0.rawValue < $1.rawValue })
        where !seen.insert(team).inserted {
            failures.append(.teamInMultipleDivisions(team))
        }

        return failures
    }

    public var isWellFormed: Bool { structureFailures.isEmpty }
}
