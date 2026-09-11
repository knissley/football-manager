import FMCore
import FMRandom
import Testing

@testable import FMSimulation

/// The most-discussed decision in the modern game.
///
/// The baseline used to take any kick inside its maximum before asking whether to go,
/// which meant a fifty-five yarder on fourth and one from the opponent's thirty-eight,
/// and going for it at all required fourth and three or less in a six-yard strip of the
/// field. It went for it on 13% of its fourth-and-ones, in a sport where the figure is
/// nearer two-thirds.
@Suite("Fourth down")
struct FourthDownTests {

    private let caller = BaselineCaller()

    /// The league's median kicker, measured rather than chosen: the thirty-two starters a
    /// generated league carries have a median `kickPower` of 75 and 77 and a median
    /// `kickAccuracy` of 76 at world seeds 7 and 11.
    static let medianLeg: UInt8 = 75
    static let medianTouch: UInt8 = 76

    /// A club's context with its kicker given the leg and the touch named.
    ///
    /// A decision about a kick is a decision about a kicker, so the fixture names him.
    /// Passing `nil` leaves the specialist slot empty, which is what a club with nobody
    /// to kick fields.
    static func context(
        leg: UInt8?, touch: UInt8? = nil, weather: WeatherState = .clear
    ) -> PlayContext {
        let (_, chart, players) = TestWorld.team(seed: 7)
        var adjusted = players
        var rotation: [DepthChart.Rotation] = []
        if let leg, let kicker = chart.starter(at: .kicker), var man = adjusted[kicker] {
            man.ratings[.kickPower] = leg
            man.ratings[.kickAccuracy] = touch ?? leg
            adjusted[kicker] = man
            rotation = chart.rotation()
        } else {
            // Everybody but the kicker, which is the lineup a club with its only kicker
            // unavailable actually puts on the field.
            rotation = chart.rotation().filter { $0.position != .kicker }
        }
        return PlayContext(
            offense: TeamID(1), defense: TeamID(2), offenseRotation: rotation,
            defenseRotation: rotation, players: adjusted,
            offenseScheme: TeamScheme(offense: .westCoast, defense: .nickelMatch),
            defenseScheme: TeamScheme(offense: .airRaid, defense: .fourThreeUnder),
            weather: weather,
            rules: .standard)
    }

    /// `ballOn` is yards from the opponent's goal, so a high number is being backed up.
    private func decision(
        distance: UInt8, ballOn: UInt8, quarter: UInt8 = 2, clock: UInt16 = 600,
        differential: Int16 = 0, context: PlayContext? = nil
    ) -> PlayConcept {
        let situation = Situation(
            quarter: quarter, clockRemaining: clock, down: .fourth, distance: distance,
            ballOn: ballOn, possession: TeamID(1), scoreDifferential: differential)
        var random = SplittableRandom(seed: 4)
        let call = caller.offensiveCall(
            for: situation, classified: SituationClass(situation),
            context: context
                ?? Self.context(leg: Self.medianLeg, touch: Self.medianTouch),
            random: &random)
        return call.concept
    }

    private func goesForIt(_ concept: PlayConcept) -> Bool {
        concept != .punt && concept != .fieldGoal
    }

    @Test("Fourth and one is a play, not a formality", .tags(.unit))
    func fourthAndOne() {
        #expect(goesForIt(decision(distance: 1, ballOn: 50)), "fourth and one at midfield")
        #expect(goesForIt(decision(distance: 1, ballOn: 45)), "fourth and one in their half")
        #expect(
            !goesForIt(decision(distance: 1, ballOn: 85)),
            "fourth and one from your own fifteen is a punt")
    }

    /// Chasing the game moves the line back; protecting a lead moves it forward.
    @Test("Field position and the scoreboard both move the decision", .tags(.unit))
    func contextMoves() {
        #expect(
            !goesForIt(decision(distance: 1, ballOn: 62)),
            "fourth and one from your own thirty-eight, level, is a punt")
        #expect(
            goesForIt(decision(distance: 1, ballOn: 62, differential: -7)),
            "the same down, seven behind, is not")
    }

    /// No-man's land: too far for a kick worth taking, too close for a punt to buy much.
    @Test("Short yardage in no-man's land is a fourth-down attempt", .tags(.unit))
    func noMansLand() {
        #expect(goesForIt(decision(distance: 3, ballOn: 45)), "fourth and three from their 45")
        #expect(
            decision(distance: 3, ballOn: 25) == .fieldGoal,
            "fourth and three from their 25 is a kick")
        #expect(decision(distance: 12, ballOn: 30) == .fieldGoal)
        #expect(decision(distance: 12, ballOn: 60) == .punt)
    }

    /// A long kick is worth attempting when the alternative is nothing, and a bad trade
    /// against forty yards of field position when there is a game left to play.
    @Test("A fifty-five yarder is an endgame kick, not a first-half one", .tags(.unit))
    func longKicksAreSituational() {
        // Their 38 is a 55-yard attempt.
        #expect(
            decision(distance: 12, ballOn: 38, quarter: 1, clock: 800) == .punt,
            "a fifty-five yarder in the first quarter is a punt")
        #expect(
            decision(distance: 12, ballOn: 38, quarter: 4, clock: 100, differential: -2)
                == .fieldGoal,
            "the same kick to win it is worth taking")
    }

    /// Behind late, a punt is a surrender — and a field goal is only worth taking if it
    /// ties the game or wins it.
    @Test("Down late, you kick only when the kick is enough", .tags(.unit))
    func desperation() {
        #expect(
            decision(distance: 8, ballOn: 25, quarter: 4, clock: 40, differential: -3)
                == .fieldGoal,
            "down three, in range, with no time: take the tie")
        #expect(
            goesForIt(decision(distance: 8, ballOn: 25, quarter: 4, clock: 40, differential: -7)),
            "down seven, a field goal does not help")
    }

    /// Two minutes before halftime is not two minutes before the end.
    ///
    /// `SituationClass.isDesperation` is true inside two minutes of *either* half, which
    /// is right as a description — you are behind and time is short. Acting on it the same
    /// way in both halves is not: before the break there is a whole half left, and
    /// punting from your own twenty is still the right call. Reading the description as an
    /// instruction had teams going for it on fourth and long from their own end before
    /// halftime, which was half of every deep fourth-down attempt in the league.
    @Test("Being behind before halftime does not mean going for it from your own end", .tags(.unit))
    func firstHalfIsNotDesperation() {
        // Own 20, fourth and eight, down four, ninety seconds before the break.
        #expect(
            decision(distance: 8, ballOn: 80, quarter: 2, clock: 90, differential: -4) == .punt)
        // The same down and distance with ninety seconds left in the game is a different
        // question, and there the punt really is a surrender.
        #expect(
            goesForIt(decision(distance: 8, ballOn: 80, quarter: 4, clock: 90, differential: -4)),
            "down four with ninety seconds left in the game")

        // A first-half two-minute drill still behaves normally in good field position.
        #expect(
            decision(distance: 6, ballOn: 30, quarter: 2, clock: 90, differential: -4)
                == .fieldGoal,
            "in range before the half, take the points")
    }

    /// The chip shot is the safest three points in the sport and the most expensive
    /// four. Fourth and goal from inside the three is a yard or so for a touchdown, and
    /// a caller that takes the kick every single time turns a third of its field goal
    /// attempts into chip shots: the sourced share of attempts from inside thirty yards
    /// is 19.1-25.3% (2023-24, nflverse play-by-play; `row:fieldGoalAttemptsUnder30` in
    /// `docs/reference/calibration-sources.md`), and the harness row is what grades it.
    @Test("Fourth and goal inside the three is a play, not a formality", .tags(.unit))
    func fourthAndGoalInsideTheThree() {
        #expect(goesForIt(decision(distance: 1, ballOn: 1)), "fourth and goal from the one")
        #expect(goesForIt(decision(distance: 2, ballOn: 2)), "fourth and goal from the two")
        #expect(goesForIt(decision(distance: 3, ballOn: 3)), "fourth and goal from the three")

        // Protecting a lead with the clock running out, the three points are worth more
        // than the down.
        #expect(
            decision(distance: 2, ballOn: 2, quarter: 4, clock: 200, differential: 4)
                == .fieldGoal,
            "up four inside the last five minutes: take the points")

        // And it is inside the three, not anywhere goal-to-go: fourth and goal from the
        // eight is a kick.
        #expect(decision(distance: 8, ballOn: 8) == .fieldGoal)
    }

    /// The conversion chart, on both sides of the scoreboard. The differential is read
    /// *before* the try, so trailing by two means the conversion ties it.
    @Test("Two-point decisions follow the chart", .tags(.unit))
    func twoPointChart() {
        func goesForTwo(_ differential: Int16, quarter: UInt8) -> Bool {
            let situation = Situation(
                quarter: quarter, clockRemaining: 500, down: .first, distance: 1, ballOn: 2,
                possession: TeamID(1), scoreDifferential: differential)
            return caller.goesForTwo(situation: situation, classified: SituationClass(situation))
        }

        #expect(goesForTwo(-2, quarter: 3), "down two: the conversion ties it")
        #expect(goesForTwo(-5, quarter: 3), "down five: it makes it a field goal game")
        #expect(goesForTwo(-10, quarter: 3))
        #expect(goesForTwo(4, quarter: 4), "up four: the second point makes it a touchdown game")

        #expect(!goesForTwo(-2, quarter: 1), "not in the first quarter")
        #expect(!goesForTwo(-7, quarter: 3), "down seven: kick it and you are level")
        #expect(!goesForTwo(0, quarter: 3))
    }
}

/// How far a kicker's range reaches, and who decides it.
///
/// Range used to be two flat numbers on the caller, whose own comment said the baseline
/// "has no kicker to consult", while the make draw read the kicker's accuracy and never
/// his leg. So a club with a punter filling in took the same fifty-two yarder as a club
/// with a leg, and the model then told it the kick was better than a coin flip.
@Suite("Field goal range")
struct FieldGoalRangeTests {

    private let caller = BaselineCaller()

    /// The share of kicks from `ballOn` this kicker puts through, drawn against the
    /// resolver's own model rather than read off its arithmetic.
    ///
    /// A forced fixture, not a sample: the leg and the touch are set, so the rate is a
    /// property of the curve at that pair and not of whichever kicker a seed happened to
    /// generate.
    private func makeRate(
        from ballOn: UInt8, leg: UInt8, touch: UInt8, draws: Int = 20_000
    ) -> Double {
        let context = FourthDownTests.context(leg: leg, touch: touch)
        let situation = Situation(
            quarter: 2, clockRemaining: 600, down: .fourth, distance: 8, ballOn: ballOn,
            possession: TeamID(1), scoreDifferential: 0)
        let calls = Calls(
            offense: OffensiveCall(concept: .fieldGoal), defense: .preventShell,
            offensiveCaller: .coordinator(PersonnelID(1)), defensiveCaller: .automatic)
        var random = SplittableRandom(seed: 31)
        let onField = Lineup.onField(
            context, concept: .fieldGoal, situation: situation, random: &random)
        var good = 0
        for _ in 0..<draws {
            let resolved = CrudeResolver().resolve(
                situation: situation, calls: calls, onField: onField, context: context,
                random: &random)
            if resolved.outcome.endedIn == .fieldGoalGood { good += 1 }
        }
        return Double(good) / Double(draws)
    }

    /// The league makes 63.7-74.9% of its kicks from fifty and beyond (2023-24, nflverse
    /// play-by-play; `row:fieldGoals50plus` in `docs/reference/calibration-sources.md`).
    /// That band is over the men clubs employ to kick. A punter filling in is not one of
    /// them, and a model in which the leg is never read cannot say so: it moves him down
    /// by the same margin from twenty yards as from fifty-five, so he is a kicker with a
    /// worse day rather than a man who cannot get the ball there.
    ///
    /// `kickPower` 45 and `kickAccuracy` 45 are what generation gives a punter at both —
    /// the untrained kicking row, centre 45.
    @Test(
        "football · the league makes 63.7-74.9% from fifty and beyond (2023-24, S1, row:fieldGoals50plus); a punter's leg does not",
        .tags(.football))
    func aLegThatIsNotAKickersFallsAwayWithDistance() {
        // Their 33 is a fifty-yard attempt, their 38 a fifty-five.
        let leagueAtFifty = makeRate(from: 33, leg: 75, touch: 76)
        #expect(
            leagueAtFifty > 0.637 && leagueAtFifty < 0.749,
            "the median kicker's fifty-yarder is the league's, at \(leagueAtFifty)")

        let punterAtFifty = makeRate(from: 33, leg: 45, touch: 45)
        let punterAtFiftyFive = makeRate(from: 38, leg: 45, touch: 45)
        #expect(
            punterAtFifty < 0.637,
            "a punter's fifty-yarder is not the league's, at \(punterAtFifty)")
        #expect(
            punterAtFifty < 0.5,
            "a punter misses a fifty-yarder more often than he makes it, at \(punterAtFifty)")
        #expect(
            punterAtFiftyFive < 0.2,
            "a punter hardly ever reaches from fifty-five, at \(punterAtFiftyFive)")
    }

    /// The sport takes 19.2-27.6% of its field goal attempts from fifty and beyond
    /// (2023-24, nflverse play-by-play; `row:fieldGoalAttempts50plus`), so a fifty-two
    /// yarder is an ordinary attempt — for a club with a leg. The same down for a club
    /// whose kicker is a floor-rated man is a fourth-down attempt, because three points
    /// he cannot reach are not on offer.
    @Test(
        "football · a fifty-two yarder is an ordinary attempt for a leg and not for a floor-rated one (2023-24, S1, row:fieldGoalAttempts50plus)",
        .tags(.football))
    func rangeIsTheKickers() {
        // Their 35 is a fifty-two yard attempt. Fourth and three, level, in the second
        // quarter: no half is ending and nothing is desperate.
        func call(leg: UInt8?, touch: UInt8? = nil) -> PlayConcept {
            let situation = Situation(
                quarter: 2, clockRemaining: 600, down: .fourth, distance: 3, ballOn: 35,
                possession: TeamID(1), scoreDifferential: 0)
            var random = SplittableRandom(seed: 4)
            return caller.offensiveCall(
                for: situation, classified: SituationClass(situation),
                context: FourthDownTests.context(leg: leg, touch: touch),
                random: &random
            ).concept
        }

        #expect(call(leg: 82, touch: 80) == .fieldGoal, "a leg kicks a fifty-two yarder")
        #expect(
            call(leg: Ratings.untrainedFloor, touch: Ratings.untrainedFloor) != .fieldGoal,
            "a floor-rated man in the specialist slot is not sent out to kick one")
    }

    /// A kick a club would not take on a first-quarter fourth down is one it will try as a
    /// half runs out, because the alternative there is nothing at all. That difference
    /// belongs to the kicker too: for a weak leg the fifty-yarder is the kick on the far
    /// side of it, and for a strong one the fifty-yarder is routine.
    ///
    /// The band this reads against is `row:fieldGoalAttempts50plus` — 19.2-27.6% of
    /// attempts from fifty and beyond (2023-24, nflverse play-by-play). A league in which
    /// every club's fiftieth yard sits in the same place cannot produce a spread like
    /// that from a set of legs that do not.
    @Test(
        "football · a weak leg attempts from fifty only as a half ends, and a strong leg routinely (2023-24, S1, row:fieldGoalAttempts50plus)",
        .tags(.football))
    func aHalfEndingStretchesTheRange() {
        // Their 33 is a fifty-yard attempt. Fourth and eight, so going for it is not the
        // alternative on offer.
        func call(leg: UInt8, quarter: UInt8, clock: UInt16) -> PlayConcept {
            let situation = Situation(
                quarter: quarter, clockRemaining: clock, down: .fourth, distance: 8,
                ballOn: 33, possession: TeamID(1), scoreDifferential: 0)
            var random = SplittableRandom(seed: 4)
            return caller.offensiveCall(
                for: situation, classified: SituationClass(situation),
                context: FourthDownTests.context(leg: leg, touch: 70),
                random: &random
            ).concept
        }

        #expect(
            call(leg: 60, quarter: 1, clock: 800) == .punt,
            "a weak leg does not take a fifty-yarder with a game left to play")
        #expect(
            call(leg: 60, quarter: 2, clock: 40) == .fieldGoal,
            "the same weak leg tries it as the half runs out")
        #expect(
            call(leg: 88, quarter: 1, clock: 800) == .fieldGoal,
            "a strong leg takes the same fifty-yarder in the first quarter")
    }

    /// The caller's belief and the physics are one model or they are two, and two is how
    /// a coach ends up certain about a game nobody is playing. This is the test that
    /// would have caught it: the make model the ball is drawn against *is* the make model
    /// the decision was taken with, at the same distance, for the same man, in the same
    /// weather.
    ///
    /// Two halves, and both are needed. That the resolver's own draws land on the shared
    /// curve, so the curve is not a second opinion the caller keeps to itself; and that
    /// every routine attempt the caller makes is one the shared curve puts at better than
    /// the routine odds, so no unit is sent out for a kick the model does not back.
    @Test(
        "contract · the caller's decision and the make draw are the same curve",
        .tags(.contract))
    func theDecisionAndTheDrawAreOneModel() {
        // The draws land on the curve. Twenty thousand kicks is about a third of a point
        // of standard error, so a hundredth and a half is loose enough not to flake and
        // tight enough that a second curve anywhere in the resolver shows up.
        for (leg, touch) in [
            (UInt8(45), UInt8(45)), (UInt8(75), UInt8(76)), (UInt8(92), UInt8(88)),
        ] {
            for ballOn in [UInt8(13), UInt8(23), UInt8(33)] {
                let context = FourthDownTests.context(leg: leg, touch: touch)
                let man = PlaceKick.kicker(for: context)
                let modelled = PlaceKick.makeChance(
                    rawLength: Rules.standard.fieldGoalDistance(ballOn: ballOn), leg: man.leg,
                    accuracy: man.accuracy, isTry: false, context: context)
                let drawn = makeRate(from: ballOn, leg: leg, touch: touch)
                #expect(
                    drawn > modelled - 0.015 && drawn < modelled + 0.015,
                    "from \(ballOn) with leg \(leg): drew \(drawn) against a model of \(modelled)"
                )
            }
        }

        // And nothing is sent out that the model does not back. Every spot on the field,
        // every leg a generated league can carry, on a routine down where no half is
        // ending.
        for leg in stride(from: UInt8(20), through: UInt8(99), by: 8) {
            let context = FourthDownTests.context(leg: leg, touch: 70)
            let man = PlaceKick.kicker(for: context)
            for ballOn in UInt8(1)...UInt8(70) {
                let situation = Situation(
                    quarter: 2, clockRemaining: 600, down: .fourth, distance: 8, ballOn: ballOn,
                    possession: TeamID(1), scoreDifferential: 0)
                var random = SplittableRandom(seed: 4)
                let concept = caller.offensiveCall(
                    for: situation, classified: SituationClass(situation), context: context,
                    random: &random
                ).concept
                guard concept == .fieldGoal else { continue }
                let length = Rules.standard.fieldGoalDistance(ballOn: ballOn)
                #expect(
                    PlaceKick.makeChance(
                        rawLength: length, leg: man.leg, accuracy: man.accuracy, isTry: false,
                        context: context) >= PlaceKick.routineOdds,
                    "sent the unit out for a \(length) yarder the model puts under even odds")
                #expect(
                    Double(length) <= PlaceKick.reach(leg: man.leg) - PlaceKick.routineMargin,
                    "sent the unit out for a \(length) yarder with a leg of \(man.leg)")
            }
        }
    }
}
