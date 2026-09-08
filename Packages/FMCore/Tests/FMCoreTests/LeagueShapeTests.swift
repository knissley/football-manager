import Testing

@testable import FMCore

@Suite("League shape presets")
struct LeagueShapePresetTests {

    @Test("The standard shape is the real one")
    func standard() {
        let shape = LeagueShape.standard
        #expect(shape.totalTeams == 32)
        #expect(shape.teamsPerConference == 16)
        #expect(shape.divisionCount == 8)
        #expect(shape.playoffField == 14)
        #expect(shape.wildCardsPerConference == 3)
        #expect(shape.isValid)
    }

    /// The smallest shape that still exercises everything structural. Three
    /// teams per division is the point: a division race needs a middle, and
    /// three-way ties have to be reachable for tiebreaker code to run at all.
    @Test("The compact shape keeps real division races")
    func compact() {
        let shape = LeagueShape.compact
        #expect(shape.totalTeams == 12)
        #expect(shape.conferences == 2)
        #expect(shape.teamsPerDivision == 3)
        #expect(shape.wildCardsPerConference == 1)
        #expect(shape.isValid)
    }

    /// Adequate for scheduling and brackets, deliberately not for standings.
    @Test("The minimal shape is still a league")
    func minimal() {
        let shape = LeagueShape.minimal
        #expect(shape.totalTeams == 8)
        #expect(shape.conferences == 2)
        #expect(shape.divisionsPerConference == 2)
        #expect(shape.isValid)
        // Every division winner qualifies and nobody else does.
        #expect(shape.wildCardsPerConference == 0)
    }

    @Test("Every preset validates")
    func allPresetsValid() {
        for shape in [LeagueShape.standard, .compact, .minimal] {
            #expect(
                shape.validationFailures.isEmpty, "\(shape) failed: \(shape.validationFailures)")
        }
    }
}

/// Customisation is a feature, but some shapes are not leagues. Each of these
/// asserts both the refusal and that it comes with a reason a player could act
/// on.
@Suite("League shape validation")
struct LeagueShapeValidationTests {

    private func shape(
        conferences: Int = 2, divisions: Int = 2, teams: Int = 3,
        games: Int = 12, playoffs: Int = 3
    ) -> LeagueShape {
        LeagueShape(
            conferences: conferences, divisionsPerConference: divisions,
            teamsPerDivision: teams, regularSeasonGames: games,
            playoffTeamsPerConference: playoffs)
    }

    /// The case that prompted the rule: collapse to one conference and the
    /// championship game has nobody to play.
    @Test("One conference is refused, and says why")
    func singleConference() {
        let single = shape(conferences: 1)
        #expect(!single.isValid)
        #expect(single.validationFailures.contains(.tooFewConferences(found: 1)))

        let explanation = single.validationFailures[0].explanation
        #expect(explanation.contains("championship"))
        #expect(explanation.contains("two conferences"))
    }

    @Test("A one-team division is refused")
    func singleTeamDivision() {
        let shape = shape(teams: 1, games: 4, playoffs: 2)
        #expect(shape.validationFailures.contains(.tooFewTeamsPerDivision(found: 1)))
    }

    @Test("A conference with no divisions is refused")
    func noDivisions() {
        #expect(shape(divisions: 0).validationFailures.contains(.tooFewDivisions(found: 0)))
    }

    @Test("An odd number of teams leaves somebody without an opponent")
    func oddTeams() {
        // 2 conferences x 1 division x 3 teams = 6, even. 3 x 1 x 3 = 9, odd —
        // but three conferences is legal, so this isolates the parity rule.
        let odd = shape(conferences: 3, divisions: 1, teams: 3, games: 8, playoffs: 1)
        #expect(odd.totalTeams == 9)
        #expect(odd.validationFailures.contains(.oddTeamCount(found: 9)))
    }

    @Test("A playoff field that shuts out a division winner is refused")
    func excludesDivisionWinners() {
        let shape = shape(divisions: 3, teams: 2, games: 8, playoffs: 2)
        #expect(
            shape.validationFailures.contains(
                .playoffFieldExcludesDivisionWinners(field: 2, divisions: 3)))
        #expect(shape.validationFailures[0].explanation.contains("Winning a division"))
    }

    @Test("A playoff field that admits everybody is refused")
    func admitsEveryone() {
        let shape = shape(divisions: 2, teams: 2, games: 6, playoffs: 5)
        #expect(
            shape.validationFailures.contains(
                .playoffFieldExceedsConference(field: 5, teams: 4)))
    }

    @Test("A season too short to play the division home and away is refused")
    func tooFewGames() {
        // Four teams in a division need six games just for the division.
        let shape = shape(teams: 4, games: 4, playoffs: 2)
        #expect(shape.validationFailures.contains(.tooFewGames(found: 4, minimum: 6)))
    }

    @Test("A season longer than there are opponents is refused")
    func tooManyGames() {
        // Eight teams can meet each other twice at most: fourteen games.
        let shape = shape(divisions: 2, teams: 2, games: 20, playoffs: 2)
        #expect(shape.validationFailures.contains(.tooManyGames(found: 20, maximum: 14)))
    }

    /// A player fixing a custom league should see everything wrong at once
    /// rather than being led through failures one at a time.
    @Test("Multiple problems are all reported")
    func reportsEverything() {
        let broken = LeagueShape(
            conferences: 2, divisionsPerConference: 3, teamsPerDivision: 2,
            regularSeasonGames: 40, playoffTeamsPerConference: 1)
        let failures = broken.validationFailures
        #expect(failures.count >= 2, "only reported \(failures)")
        #expect(failures.contains(.playoffFieldExcludesDivisionWinners(field: 1, divisions: 3)))
        #expect(failures.contains(.tooManyGames(found: 40, maximum: 22)))
    }

    /// Structural counts are checked first: reporting a broken playoff field for
    /// a league with zero divisions would be noise on top of the real problem.
    @Test("Structural failures are reported before derived ones")
    func structuralFailuresComeFirst() {
        let broken = LeagueShape(
            conferences: 1, divisionsPerConference: 0, teamsPerDivision: 1,
            regularSeasonGames: 99, playoffTeamsPerConference: 99)
        let failures = broken.validationFailures
        #expect(failures.count == 3)
        #expect(failures.contains(.tooFewConferences(found: 1)))
        #expect(failures.contains(.tooFewDivisions(found: 0)))
        #expect(failures.contains(.tooFewTeamsPerDivision(found: 1)))
    }

    @Test("Every failure explains itself in words a player could act on")
    func explanationsAreUseful() {
        let failures: [LeagueShape.ValidationFailure] = [
            .tooFewConferences(found: 1), .tooFewDivisions(found: 0),
            .tooFewTeamsPerDivision(found: 1), .oddTeamCount(found: 9),
            .playoffFieldExcludesDivisionWinners(field: 2, divisions: 4),
            .playoffFieldExceedsConference(field: 9, teams: 8),
            .tooFewGames(found: 2, minimum: 6), .tooManyGames(found: 40, maximum: 14),
        ]
        for failure in failures {
            let explanation = failure.explanation
            #expect(explanation.count > 40, "terse explanation: \(explanation)")
            #expect(explanation.hasSuffix("."))
            #expect(!explanation.lowercased().contains("invalid"))
        }
    }

    /// Unusual leagues that are still leagues. Customisation is the point; the
    /// validator exists to catch shapes that break the sport, not shapes that
    /// are merely unfamiliar.
    @Test("Unconventional but coherent leagues are allowed")
    func allowsUnusualLeagues() {
        // Four conferences of two divisions of four.
        #expect(shape(conferences: 4, divisions: 2, teams: 4, games: 14, playoffs: 2).isValid)
        // Two conferences, one big division each — the division race is the
        // conference race, which is a legitimate way to run a league.
        #expect(shape(divisions: 1, teams: 8, games: 16, playoffs: 4).isValid)
        // A very large league.
        #expect(shape(conferences: 2, divisions: 8, teams: 4, games: 17, playoffs: 8).isValid)
    }
}
