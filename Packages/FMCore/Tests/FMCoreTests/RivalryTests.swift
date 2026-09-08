import Testing

@testable import FMCore

@Suite("Rivalries")
struct RivalryTests {

    private let pair = TeamPair(TeamID(3), TeamID(7))

    private func rivalry(
        origin: RivalryOrigin = .divisional, _ events: [(Int, RivalryEventKind)] = []
    ) -> Rivalry {
        Rivalry(
            pair: pair, origin: origin,
            history: events.map { RivalryEvent(pair: pair, season: $0.0, kind: $0.1) })
    }

    // MARK: - The pair

    /// Storing a rivalry twice under two orderings surfaces as a grudge only one side
    /// has heard of.
    @Test("A pair is the same however it is written")
    func pairIsUnordered() {
        #expect(TeamPair(TeamID(3), TeamID(7)) == TeamPair(TeamID(7), TeamID(3)))
        #expect(TeamPair(TeamID(7), TeamID(3)).lower == TeamID(3))

        var set: Set<TeamPair> = []
        set.insert(TeamPair(TeamID(3), TeamID(7)))
        set.insert(TeamPair(TeamID(7), TeamID(3)))
        #expect(set.count == 1)
    }

    @Test("A pair knows its members and the other one")
    func pairMembership() {
        #expect(pair.contains(TeamID(3)))
        #expect(pair.contains(TeamID(9)) == false)
        #expect(pair.opponent(of: TeamID(3)) == TeamID(7))
        #expect(pair.opponent(of: TeamID(7)) == TeamID(3))
        #expect(pair.opponent(of: TeamID(9)) == nil)
    }

    // MARK: - Intensity

    /// Two teams in a division care a little on principle; two who met once in January
    /// and never again should not.
    @Test("Origin sets a floor, and the floors are ordered correctly")
    func baseIntensity() {
        #expect(
            rivalry(origin: .divisional).baseIntensity > rivalry(origin: .regional).baseIntensity)
        #expect(
            rivalry(origin: .regional).baseIntensity > rivalry(origin: .postseason).baseIntensity)
        #expect(rivalry(origin: .divisional, []).intensity(in: 2030) == 22)
    }

    /// Without decay, intensity is a running total that only rises, and after twenty
    /// seasons every pairing in the league is a blood feud.
    @Test("A rivalry nobody feeds goes quiet")
    func intensityDecays() {
        let feud = rivalry(origin: .divisional, [(2020, .playoffElimination)])
        let atTheTime = feud.intensity(in: 2020)
        let aDecadeLater = feud.intensity(in: 2030)

        #expect(atTheTime > aDecadeLater)
        #expect(aDecadeLater > feud.baseIntensity, "a decade should not erase it entirely")
        #expect(aDecadeLater < feud.baseIntensity + 4, "a decade should mostly erase it")
    }

    @Test("Recent events count for more than old ones")
    func recencyDominates() {
        let recent = rivalry(origin: .divisional, [(2029, .controversialFinish)])
        let old = rivalry(origin: .divisional, [(2015, .controversialFinish)])
        #expect(recent.intensity(in: 2030) > old.intensity(in: 2030))
    }

    /// A blowout is a bad night; a playoff elimination is a decade. Without that spread,
    /// intensity is a win-loss record with a different name.
    @Test("Event weights are spread widely enough to matter")
    func weightsAreSpread() {
        let blowout = rivalry(origin: .divisional, [(2030, .blowout)])
        let elimination = rivalry(origin: .divisional, [(2030, .playoffElimination)])
        #expect(elimination.intensity(in: 2030) > blowout.intensity(in: 2030) + 10)
    }

    /// The future has not happened yet. A projection asked about 2025 must not read
    /// events from 2029.
    @Test("Events after the season asked about are not counted")
    func futureEventsAreIgnored() {
        let feud = rivalry(origin: .divisional, [(2029, .titleGame)])
        #expect(feud.intensity(in: 2025) == feud.baseIntensity)
        #expect(feud.intensity(in: 2029) > feud.baseIntensity)
    }

    @Test("Intensity is capped, so a long feud stays on the scale")
    func intensityIsCapped() {
        let events = (2020...2030).flatMap { season in
            [(season, RivalryEventKind.titleGame), (season, .playoffElimination)]
        }
        #expect(rivalry(origin: .divisional, events).intensity(in: 2030) <= 100)
    }

    @Test("Heat bands follow intensity")
    func heat() {
        #expect(RivalryHeat(intensity: 5) == .cold)
        #expect(RivalryHeat(intensity: 30) == .simmering)
        #expect(RivalryHeat(intensity: 50) == .heated)
        #expect(RivalryHeat(intensity: 90) == .bitter)
        #expect(rivalry(origin: .postseason).heat(in: 2030) == .cold)
    }

    // MARK: - History as something to cite

    /// The reason seeded history is an event log and not a number: a write-up has to be
    /// able to name what happened, and the most recent heavy thing is what it names.
    @Test("Live history surfaces the recent and the heavy")
    func liveHistory() {
        let feud = rivalry(
            origin: .divisional,
            [
                (2018, .titleGame), (2028, .blowout), (2029, .playoffElimination),
                (2029, .closeGame), (2031, .upset),
            ])

        let cited = feud.liveHistory(in: 2030, limit: 3)
        #expect(cited.count == 3)
        #expect(cited.allSatisfy { $0.season <= 2030 }, "a 2031 event was cited in 2030")
        #expect(cited[0].season == 2029)
        #expect(cited[0].kind == .playoffElimination, "the heavier 2029 event should lead")
    }

    @Test("An aggrieved team is recorded where the event has one")
    func aggrievedTeam() {
        let event = RivalryEvent(
            pair: pair, season: 2029, kind: .playoffElimination, aggrievedTeam: TeamID(3))
        #expect(event.aggrievedTeam == TeamID(3))
        #expect(pair.opponent(of: event.aggrievedTeam!) == TeamID(7))
    }
}
