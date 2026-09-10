import Testing

@testable import FMCore

/// Where a free kick leaves the ball, which under the dynamic kickoff is four different
/// answers rather than one.
///
/// The engine had a single kickoff touchback spot and nothing else, so a kick that never
/// reached the receiving team was spotted as though it had been fielded and downed there
/// — the kicking team's own mistake handed to it as field position.
@Suite("Free kick spots")
struct FreeKickSpotTests {

    private let rules = Rules.standard

    /// The kickoff, in the kicking team's frame: its own 35 is 65 from the other goal.
    private func kickoff(from ownYard: UInt8 = 35) -> Situation {
        Situation(
            quarter: 1, clockRemaining: 900, down: .first, distance: 10,
            ballOn: rules.ballOnFromOwnYard(ownYard), possession: TeamID(1))
    }

    private func outcome(_ ending: PlayEnding, at spot: UInt8?) -> Outcome {
        Outcome(kind: .kickoff, yards: 0, endedIn: ending, finalSpot: spot)
    }

    /// The landing zone is the receiving team's 20 out to its goal line, so a kick short
    /// of it has not reached the zone at all.
    @Test(
        "football · Rule 6-1-2-e · the landing zone runs from the receiving team's 20 to its goal line",
        .tags(.football))
    func theLandingZoneIsTheLastTwenty() {
        #expect(rules.kickoffLandingZoneOwnYard == 20)
        #expect(rules.freeKickOutOfBoundsYards == 25)
    }

    /// 6-2-4 gives the receiving team a choice of three spots. Two of them are always
    /// worse for it than the third — the out-of-bounds spot is downfield of the 25, and
    /// the spot the ball came down at only beats the 25 when the kick was short — so the
    /// choice reduces to taking whichever of the two is nearer the kicking team.
    @Test(
        "football · Rule 6-2-4 · a free kick out of bounds gives the receiving team the ball 25 yards from the spot of the kick",
        .tags(.football))
    func aKickOutOfBoundsIsTwentyFiveYardsOn() {
        // Kicked out of bounds at the receiving team's 15 — sixty yards on, so the 25 is
        // what the receiving team takes: the kicking team's 40, which is its own 40.
        let advancement = rules.advance(
            from: kickoff(), outcome: outcome(.outOfBounds, at: 15))

        #expect(advancement.possessionChanged)
        #expect(advancement.ballOn == 60, "its own 40 is 60 from the kicking team's goal")
        #expect(advancement.down == .first)
        #expect(advancement.distance == rules.yardsToGain)
    }

    /// The same article's third option: the spot where the ball came down, when the kick
    /// travelled less than 25 yards. A kick that dribbles twenty yards is worth more to
    /// the receiving team where it lies than 25 yards on would be.
    @Test(
        "football · Rule 6-2-4, 3-20-7 · a kick that first touches down short of the landing zone gives the receiving team the better of 25 yards on and where it came down",
        .tags(.football))
    func aShortKickIsSpottedWhereItLiesWhenThatIsNearer() {
        // Twenty yards on, so it came down on the kicking team's 55 — the receiving
        // team's 45 — which beats the 25.
        let short = rules.advance(from: kickoff(), outcome: outcome(.downed, at: 45))
        #expect(short.possessionChanged)
        #expect(short.ballOn == 55, "its own 45 is 55 from the kicking team's goal")

        // Thirty yards on and still short of the zone: past the 25, so the 25 is better.
        let further = rules.advance(from: kickoff(), outcome: outcome(.downed, at: 35))
        #expect(further.ballOn == 60, "its own 40")
    }

    /// The kick spot is the kicking team's restraining line as a distance penalty has
    /// moved it, and everything 6-2-4 measures is measured from there.
    @Test(
        "football · Rule 6-1-2-a, 6-2-4 · the 25 yards are measured from the spot of the kick, so a penalty on the kicking team moves the award with it",
        .tags(.football))
    func theAwardIsMeasuredFromTheKick() {
        // Fifteen yards back: the kick is from the kicking team's 20, so 25 yards on is
        // the kicking team's 45 — which the receiving team is 45 yards from.
        let penalised = rules.advance(
            from: kickoff(from: 20), outcome: outcome(.outOfBounds, at: 10))
        #expect(penalised.ballOn == 45, "the kicking team's 45")

        // Fifteen yards forward: the kick is from the 50, and 25 on is the receiving
        // team's 25.
        let rewarded = rules.advance(
            from: kickoff(from: 50), outcome: outcome(.outOfBounds, at: 10))
        #expect(rewarded.ballOn == 75, "its own 25 is 75 from the kicking team's goal")
    }
}
