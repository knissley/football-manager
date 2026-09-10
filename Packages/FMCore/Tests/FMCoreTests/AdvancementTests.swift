import Testing

@testable import FMCore

@Suite("Down and possession advancement")
struct AdvancementTests {

    private let rules = Rules.standard

    private func situation(
        down: Down = .first, distance: UInt8 = 10, ballOn: UInt8 = 75
    ) -> Situation {
        Situation(
            quarter: 2, clockRemaining: 600, down: down, distance: distance, ballOn: ballOn,
            possession: TeamID(1))
    }

    private func outcome(
        _ yards: Int16, _ ending: PlayEnding = .tackled, kind: PlayKind = .rush,
        finalSpot: UInt8? = nil
    ) -> Outcome {
        Outcome(kind: kind, yards: yards, endedIn: ending, finalSpot: finalSpot)
    }

    // MARK: - The ordinary down

    /// `ballOn` is yards from the *opponent's* goal, so a gain reduces it. Getting this
    /// backwards is the off-by-a-lot bug the convention exists to prevent.
    @Test("A gain moves the ball toward the opponent's goal")
    func gainMovesForward() {
        let next = rules.advance(from: situation(ballOn: 75), outcome: outcome(7))
        #expect(next.ballOn == 68)
        #expect(next.down == .second)
        #expect(next.distance == 3)
        #expect(next.possessionChanged == false)
    }

    @Test("A loss moves it back and adds to the distance")
    func lossMovesBack() {
        let next = rules.advance(from: situation(ballOn: 75), outcome: outcome(-4, kind: .sack))
        #expect(next.ballOn == 79)
        #expect(next.down == .second)
        #expect(next.distance == 14)
    }

    @Test("Reaching the marker is a new set of downs")
    func firstDown() {
        let next = rules.advance(from: situation(distance: 10, ballOn: 60), outcome: outcome(10))
        #expect(next.down == .first)
        #expect(next.distance == 10)
        #expect(next.ballOn == 50)

        let past = rules.advance(from: situation(distance: 3, ballOn: 60), outcome: outcome(12))
        #expect(past.down == .first)
        #expect(past.ballOn == 48)
    }

    /// There is no first and ten from the opponent's six. Inside the ten the distance
    /// is to the goal line.
    @Test("A first down inside the ten is first and goal")
    func firstAndGoal() {
        let next = rules.advance(from: situation(distance: 10, ballOn: 18), outcome: outcome(12))
        #expect(next.ballOn == 6)
        #expect(next.down == .first)
        #expect(next.distance == 6, "first and ten from the six is not a thing")
    }

    @Test("An incompletion costs a down and nothing else")
    func incompletion() {
        let next = rules.advance(
            from: situation(down: .second, distance: 7, ballOn: 40),
            outcome: outcome(0, .incomplete, kind: .pass))
        #expect(next.ballOn == 40)
        #expect(next.down == .third)
        #expect(next.distance == 7)
    }

    /// Fourth and short of the marker: the ball goes over where it lies, and the new
    /// offence's field position is the mirror of the old one's.
    @Test("Failing on fourth down hands the ball over at the spot")
    func turnoverOnDowns() {
        let next = rules.advance(
            from: situation(down: .fourth, distance: 3, ballOn: 55), outcome: outcome(1))
        #expect(next.possessionChanged)
        // The ball reached their 54 before the flip, so the new offence has it 46 yards
        // from the goal it is attacking.
        #expect(next.ballOn == 46)
        #expect(next.down == .first)
        #expect(next.distance == 10)
    }

    @Test("Converting on fourth down keeps the ball")
    func fourthDownConversion() {
        let next = rules.advance(
            from: situation(down: .fourth, distance: 1, ballOn: 55), outcome: outcome(4))
        #expect(next.possessionChanged == false)
        #expect(next.down == .first)
        #expect(next.ballOn == 51)
    }

    // MARK: - Scoring

    @Test("A touchdown scores six and owes a try")
    func touchdown() {
        let next = rules.advance(
            from: situation(ballOn: 8), outcome: outcome(8, .touchdown))
        #expect(next.scoring == .touchdown)
        #expect(next.points == 6)
        #expect(next.requiresTry)
        #expect(next.possessionChanged == false)
        #expect(next.ballOn == rules.extraPointSnapYard)
    }

    @Test("A made field goal scores three and owes a kickoff")
    func fieldGoal() {
        let next = rules.advance(
            from: situation(down: .fourth, ballOn: 25),
            outcome: outcome(0, .fieldGoalGood, kind: .fieldGoal))
        #expect(next.scoring == .fieldGoal)
        #expect(next.points == 3)
        #expect(next.requiresKickoff)
    }

    /// A miss from your own forty is worse field position than a punt, because the
    /// defence takes over at the spot of the kick rather than the line of scrimmage.
    @Test("A missed field goal gives the ball up at the spot of the kick")
    func missedFieldGoal() {
        let long = rules.advance(
            from: situation(down: .fourth, ballOn: 45),
            outcome: outcome(0, .fieldGoalMissed, kind: .fieldGoal))
        #expect(long.possessionChanged)
        // The kick was struck from 52 out; they take over at their own 48.
        #expect(long.ballOn == 48)

        // From close in, the touchback floor protects them instead.
        let short = rules.advance(
            from: situation(down: .fourth, ballOn: 10),
            outcome: outcome(0, .fieldGoalMissed, kind: .fieldGoal))
        #expect(short.ballOn == rules.puntTouchbackSpot)
    }

    /// Rewritten for A3 (#16). This test asserted `possessionChanged`, with a comment
    /// warning against exactly the outcome that produced: under the engine's convention
    /// the possessing team kicks, so flipping possession at the safety had the team
    /// that *scored* free-kicking from its own 20 and the team that conceded receiving.
    /// The sport: the team scored upon keeps the ball to put it in play with a free kick
    /// from its own 20, and that kick changes hands like every kickoff does.
    @Test(
        "football · Rule 11-1-2-c, 11-5-2, 6-1-1-b · a safety is two points to the defence, and the team scored upon keeps the ball to free-kick from its own 20"
    )
    func safety() {
        let next = rules.advance(
            from: situation(ballOn: 98), outcome: outcome(-3, .safety, kind: .sack))
        #expect(next.scoring == .safety)
        #expect(next.points == 2)
        #expect(next.possessionChanged == false, "the team scored upon keeps the ball to kick")
        #expect(next.requiresKickoff)
        #expect(
            next.ballOn == rules.ballOnFromOwnYard(rules.safetyKickoffOwnYard),
            "the free kick is from its own 20")
    }

    // MARK: - Turnovers

    /// `yards` is the offence's net, which says nothing useful once the defence has the
    /// ball. A play that changes hands reports the resting spot outright.
    @Test("An interception hands over at the spot it came to rest")
    func interception() {
        let next = rules.advance(
            from: situation(ballOn: 60),
            outcome: outcome(0, .intercepted, kind: .pass, finalSpot: 72))
        #expect(next.possessionChanged)
        #expect(next.ballOn == 28, "the spot flips into the new offence's frame")
        #expect(next.down == .first)
        #expect(next.distance == 10)
    }

    @Test("A return to the house is a defensive touchdown")
    func pickSix() {
        let next = rules.advance(
            from: situation(ballOn: 60),
            outcome: outcome(0, .intercepted, kind: .pass, finalSpot: 100))
        #expect(next.scoring == .defensiveTouchdown)
        #expect(next.points == 6)
        #expect(next.possessionChanged)
        #expect(next.requiresTry)
    }

    @Test("A fumble recovered by the offence is not a change of possession")
    func fumbleRecovered() {
        let next = rules.advance(
            from: situation(down: .second, distance: 8, ballOn: 50),
            outcome: outcome(3, .fumbleRecovered))
        #expect(next.possessionChanged == false)
        #expect(next.down == .third)
        #expect(next.distance == 5)
    }

    @Test("A punt fair caught or downed hands over at the spot")
    func punts() {
        let fairCatch = rules.advance(
            from: situation(down: .fourth, ballOn: 70),
            outcome: outcome(0, .fairCatch, kind: .punt, finalSpot: 25))
        #expect(fairCatch.possessionChanged)
        #expect(fairCatch.ballOn == 75)

        let touchback = rules.advance(
            from: situation(down: .fourth, ballOn: 60),
            outcome: outcome(0, .touchback, kind: .punt))
        #expect(touchback.ballOn == rules.puntTouchbackSpot)
        #expect(touchback.possessionChanged)
    }

    // MARK: - Invariants

    /// Every path has to leave the ball somewhere legal. A spot of zero or a hundred is
    /// in an end zone, which is a score, not a place to snap from.
    @Test("Every advancement leaves the ball on a legal spot")
    func spotsAreAlwaysLegal() {
        let endings = PlayEnding.allCases
        let spots: [UInt8] = [1, 2, 10, 20, 50, 80, 95, 99]
        let gains: [Int16] = [-15, -3, 0, 1, 5, 12, 40, 99]

        for ending in endings {
            for ballOn in spots {
                for gain in gains {
                    for down in Down.allCases {
                        let result = rules.advance(
                            from: situation(down: down, distance: 10, ballOn: ballOn),
                            outcome: outcome(gain, ending))
                        #expect(
                            result.ballOn >= 1 && result.ballOn <= 99,
                            "\(ending) from \(ballOn) gaining \(gain) landed on \(result.ballOn)")
                        #expect(result.distance >= 1, "\(ending) produced a distance of zero")
                    }
                }
            }
        }
    }

    /// Points only ever come with a scoring play, and a scoring play always brings
    /// points. A mismatch would show up as a scoreboard that disagrees with the log.
    @Test("Points and scoring plays agree")
    func pointsMatchScoring() {
        for ending in PlayEnding.allCases {
            let result = rules.advance(
                from: situation(ballOn: 50), outcome: outcome(5, ending, finalSpot: 55))
            #expect(
                (result.points > 0) == (result.scoring != nil),
                "\(ending) scored \(result.points) with scoring \(String(describing: result.scoring))"
            )
        }
    }

    /// A penalty is enforced by the penalty layer, so advancement must leave the
    /// situation exactly as it found it rather than quietly consuming a down.
    @Test("An enforced penalty advances nothing")
    func penaltyAdvancesNothing() {
        let before = situation(down: .third, distance: 7, ballOn: 42)
        let next = rules.advance(
            from: before, outcome: outcome(0, .penaltyEnforced, kind: .penaltyOnly))
        #expect(next.ballOn == before.ballOn)
        #expect(next.down == before.down)
        #expect(next.distance == before.distance)
        #expect(next.possessionChanged == false)
    }
}
