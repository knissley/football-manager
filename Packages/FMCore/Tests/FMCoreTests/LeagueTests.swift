import Testing

@testable import FMCore

@Suite("League structure")
struct LeagueTests {

    /// Builds a league that matches its shape, so each test can break exactly one thing.
    private func league(
        shape: LeagueShape = .compact, teamsPerDivision: Int? = nil
    ) -> League {
        let perDivision = teamsPerDivision ?? shape.teamsPerDivision
        var next: UInt64 = 1
        var conferences: [Conference] = []

        for conferenceIndex in 0..<shape.conferences {
            var divisions: [Division] = []
            for divisionIndex in 0..<shape.divisionsPerConference {
                var members: [TeamID] = []
                for _ in 0..<perDivision {
                    members.append(TeamID(next))
                    next += 1
                }
                divisions.append(
                    Division(
                        id: DivisionID(UInt64(conferenceIndex * 10 + divisionIndex + 1)),
                        name: "Division \(divisionIndex + 1)", teams: members))
            }
            conferences.append(
                Conference(
                    id: ConferenceID(UInt64(conferenceIndex + 1)),
                    name: "Conference \(conferenceIndex + 1)", divisions: divisions))
        }

        return League(
            id: LeagueID(1), name: "Continental Football League", shape: shape,
            conferences: conferences)
    }

    @Test("A league built to its shape is well formed", .tags(.unit))
    func wellFormed() {
        #expect(league().isWellFormed)
        #expect(league(shape: .standard).isWellFormed)
        #expect(league(shape: .minimal).isWellFormed)
    }

    @Test("Membership rolls up from divisions", .tags(.unit))
    func membership() {
        let compact = league(shape: .compact)
        #expect(compact.teams.count == LeagueShape.compact.totalTeams)
        #expect(compact.divisions.count == LeagueShape.compact.divisionCount)
        #expect(
            compact.conferences.allSatisfy {
                $0.teams.count == LeagueShape.compact.teamsPerConference
            })
    }

    @Test("A team's division and conference are found from the structure", .tags(.unit))
    func lookup() {
        let compact = league()
        let first = compact.teams[0]
        #expect(compact.division(of: first)?.teams.contains(first) == true)
        #expect(compact.conference(of: first)?.teams.contains(first) == true)
        #expect(compact.division(of: TeamID(9_999)) == nil)
    }

    /// Divisional opponents play twice a year and share a bracket. Rivalry generation
    /// keys off this, so it has to be exactly the teams in the same division.
    @Test("Division rivals are the other teams in the division, and never yourself", .tags(.unit))
    func divisionRivals() {
        let compact = league()
        guard let division = compact.divisions.first, division.teams.count >= 2 else {
            Issue.record("the fixture should have a division with members")
            return
        }
        let a = division.teams[0]
        let b = division.teams[1]

        #expect(compact.areDivisionRivals(a, b))
        #expect(compact.areDivisionRivals(b, a))
        #expect(compact.areDivisionRivals(a, a) == false, "a team is not its own rival")

        let elsewhere = compact.divisions.last!.teams[0]
        #expect(compact.areDivisionRivals(a, elsewhere) == false)
    }

    // MARK: - Structure validation

    /// A valid shape filled in wrongly breaks the schedule just as thoroughly as an
    /// impossible shape, and fails much later and less legibly. Hence two validators.
    @Test("A short division is caught even though the shape is legal", .tags(.unit))
    func shortDivision() {
        var broken = league()
        broken.conferences[0].divisions[0].teams.removeLast()

        let failures = broken.structureFailures
        #expect(broken.isWellFormed == false)
        #expect(failures.count == 1)
        if case .divisionSizeMismatch(_, let found, let expected) = failures[0] {
            #expect(found == LeagueShape.compact.teamsPerDivision - 1)
            #expect(expected == LeagueShape.compact.teamsPerDivision)
        } else {
            Issue.record("expected a division size failure, got \(failures)")
        }
    }

    @Test("A missing conference is reported against the shape", .tags(.unit))
    func missingConference() {
        var broken = league()
        broken.conferences.removeLast()
        #expect(
            broken.structureFailures.contains {
                if case .conferenceCountMismatch = $0 { return true }
                return false
            })
    }

    @Test("A missing division is named by its conference", .tags(.unit))
    func missingDivision() {
        var broken = league()
        broken.conferences[0].divisions.removeLast()
        #expect(
            broken.structureFailures.contains {
                if case .divisionCountMismatch(let conference, _, _) = $0 {
                    return conference == "Conference 1"
                }
                return false
            })
    }

    /// A duplicated team plays itself and inflates a division. It is the one structural
    /// error the counts alone would miss.
    @Test("A team in two divisions is caught", .tags(.unit))
    func duplicatedTeam() {
        var broken = league()
        let stolen = broken.conferences[0].divisions[0].teams[0]
        broken.conferences[0].divisions[1].teams[0] = stolen

        #expect(broken.structureFailures.contains { $0 == .teamInMultipleDivisions(stolen) })
    }

    /// An impossible shape is reported once, as a shape problem, rather than as the
    /// dozen structural symptoms it produces.
    @Test("An invalid shape short-circuits structural checks", .tags(.unit))
    func invalidShapeShortCircuits() {
        let oneConference = LeagueShape(
            conferences: 1, divisionsPerConference: 2, teamsPerDivision: 4,
            regularSeasonGames: 14, playoffTeamsPerConference: 4)
        let broken = League(
            id: LeagueID(1), name: "Half a league", shape: oneConference, conferences: [])

        let failures = broken.structureFailures
        #expect(failures.count == 1)
        if case .shapeIsInvalid(let inner) = failures[0] {
            #expect(inner.isEmpty == false)
        } else {
            Issue.record("expected the shape failure to be reported, got \(failures)")
        }
    }

    /// Written for the player, not the log — the same standard `LeagueShape` holds to.
    @Test("Structural failures explain themselves in plain language", .tags(.unit))
    func explanations() {
        var broken = league()
        broken.conferences[0].divisions[0].teams.removeLast()
        let explanation = broken.structureFailures[0].explanation
        #expect(explanation.contains("uneven"))
        #expect(explanation.isEmpty == false)
    }
}
