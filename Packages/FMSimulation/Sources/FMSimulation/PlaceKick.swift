import FMCore

/// What a place kick is worth, from where it is being taken and by whom.
///
/// **One model, read twice.** The resolver draws the kick against it and the caller
/// decides whether to send the unit out by it, so the coach's belief about his kicker and
/// the physics of the kick are the same arithmetic rather than two models of one ball.
/// They used to be two: the make draw read `kickAccuracy` and never `kickPower`, so a leg
/// was worth the same from twenty yards as from fifty-five, while the caller read neither
/// and kicked from a flat line whose own comment said it had no kicker to consult. A club
/// with a punter filling in therefore took the same fifty-two yarder as a club with a leg,
/// and the model then told it the kick was better than a coin flip.
///
/// Everything here is arithmetic over two ratings and the afternoon. No draws are made:
/// the one draw a kick needs is the resolver's, against the number this returns.
enum PlaceKick {

    // MARK: - Who is kicking

    /// The leg the curve is centred on.
    ///
    /// Measured rather than chosen: the thirty-two starting kickers a generated league
    /// carries have a median `kickPower` of 75 and 77, and a mean of 75.8 and 73.2, at
    /// world seeds 7 and 11. Centring here is what keeps the league's curve the curve it
    /// already was — an average leg's kick is the same number before and after this model
    /// existed, and only the spread around him is new.
    static let averageLeg = 75.0

    /// The accuracy the *level* is centred on, which is not the league's median: the
    /// kickers generated today sit some seven points above it, so the league's make rates
    /// run a little above this curve. Moving it moves every make row in the harness at
    /// once, which is a retune and not a fix, so it is left where it was and reported.
    static let averageAccuracy = 68.0

    /// The leg and the touch of the man who would kick for this side.
    ///
    /// Read from the same place the lineup will fill the specialist slot from: the
    /// rotation the game handed the context, which has already had everyone unavailable
    /// removed and everyone behind them moved up
    /// (`DepthChart.rotation(at:unavailable:)`). A kicker is a starter-only position, so
    /// the man highest on the chart who is still available takes it and no draw is made —
    /// which is why the caller can know who it is before the lineup exists.
    ///
    /// A side with nobody left to kick reads as `PlayContext.effective` reads an empty
    /// slot, so the caller and the resolver agree about that case too rather than the
    /// caller assuming a kicker who is not there.
    static func kicker(for context: PlayContext) -> (leg: Double, accuracy: Double) {
        var chosen: PlayerID?
        var chosenDepth = Int.max
        for entry in context.offenseRotation where entry.position == .kicker {
            guard entry.depth < chosenDepth else { continue }
            chosen = entry.player
            chosenDepth = entry.depth
        }
        if chosen == nil {
            // Nobody left who kicks. The lineup falls through to whoever lists it as a
            // second position, and this has to fall the same way or the caller would be
            // deciding about a different man from the one who takes the snap.
            for entry in context.offenseRotation {
                guard entry.depth < chosenDepth,
                    context.player(entry.player)?.secondaryPositions.contains(.kicker) == true
                else { continue }
                chosen = entry.player
                chosenDepth = entry.depth
            }
        }
        return (
            leg: context.effective(.kickPower, for: chosen, onOffense: true),
            accuracy: context.effective(.kickAccuracy, for: chosen, onOffense: true)
        )
    }

    // MARK: - How far the leg reaches

    /// The longest kick an average leg is sent out for.
    ///
    /// The flat number the caller used to carry as its maximum. It stays the average
    /// kicker's, which is what makes this change a spread around the league rather than a
    /// move of it: a median leg's range is the same before and after.
    static let averageReach = 55.0

    /// Yards of reach a rating point of leg is worth.
    ///
    /// Sets the whole spread: the starting kickers a generated league carries run from 55
    /// to 96 in `kickPower` at both seeds measured, so a third of a yard a point turns a
    /// forty-one point spread into thirteen and a half yards of range — 48 for the weakest
    /// leg in the league and 62 for the strongest, around the 55 the caller already used
    /// for everybody. Graded by `row:fieldGoalAttempts50plus` in
    /// `docs/reference/calibration-sources.md`; nothing sources a reach by leg directly,
    /// so this is a shape rather than a measurement and the row is what says whether the
    /// shape is right.
    static let reachPerLegPoint = 0.33

    /// The difference between the kick a side would take and the kick it will try.
    ///
    /// Not a new number: the caller already carried a four-yard gap between its routine
    /// range and its maximum, and that gap is now the kicker's rather than the league's.
    /// A coach at the gun asks for a kick from beyond where he would take one, because
    /// the ball is dead either way — but not from beyond where the leg gets it there.
    static let routineMargin = 4.0

    /// The longest kick this leg is sent out for at all, in yards.
    static func reach(leg: Double) -> Double {
        max(20.0, averageReach + (leg - averageLeg) * reachPerLegPoint)
    }

    /// The longest kick a rating of 99 reaches — the longest attempt anyone in a generated
    /// league can be sent out for, and what a test asserting nobody kicks a seventy-yarder
    /// reads.
    static var longestAttempt: Int { Int(reach(leg: 99)) }

    // MARK: - Whether it goes through

    /// Yards the conditions add to the kick, which the length is read net of.
    ///
    /// Thin air carries it and cold, wind and snow hold it up. No `rounded()`: these
    /// modules link without libm, and `Tools/playsize` is the guard that proves it.
    static func effectiveLength(
        _ rawLength: Int, weather: WeatherState, altitudeFeet: Int16
    ) -> Int {
        let carry = Conditions.kickingAdjustment(weather, altitudeFeet: altitudeFeet)
        return rawLength - Int(carry + (carry < 0 ? -0.5 : 0.5))
    }

    /// The league-average fall in make chance per yard beyond the mid-forties.
    static let leagueFallPerYard = 0.017

    /// How much steeper that fall gets for each rating point of leg below the average.
    ///
    /// A punter filling in — `kickPower` 45, which is the centre generation gives a punter
    /// on the kicking row he does not train — is the case this is set from, and the sport
    /// is what sets it: he misses a fifty-yarder more often than he makes it, and from
    /// fifty-five he hardly ever gets it there. That pins the fall at his leg, and the
    /// average leg's fall is the league's, which pins it at the other end.
    static let fallPerLegPointBelowAverage = 0.0015

    /// The steepest the fall gets, which is where a punter's leg already sits.
    static let steepestFall = 0.060

    /// How fast the chance falls per yard past the mid-forties, for this leg.
    ///
    /// Flat at the league's fall for an average leg and every leg above it: a strong leg
    /// keeps a shallow curve, it does not buy a shallower one than the league's. What it
    /// buys is `reach`, which is the thing a leg is actually for.
    static func fallPerYard(leg: Double) -> Double {
        min(
            steepestFall,
            max(
                leagueFallPerYard,
                leagueFallPerYard + (averageLeg - leg) * fallPerLegPointBelowAverage))
    }

    /// The chance the kick is good, before the draw.
    ///
    /// Two segments and two ratings. Near-automatic inside thirty, a gentle slope through
    /// the range teams actually kick from, and a fall past the mid-forties that is the
    /// kicker's own — a single line from twenty-five was too steep in the middle, which
    /// made forty-somethings 69% against a real 82% and ran the extra point through the
    /// same slope.
    ///
    /// `length` is the kick's length net of the conditions, from
    /// `effectiveLength(_:weather:altitudeFeet:)`.
    static func makeChance(
        length: Int, leg: Double, accuracy: Double, isTry: Bool, isWet: Bool
    ) -> Double {
        var chance: Double
        if length <= 30 {
            chance = 0.95
        } else if length <= 45 {
            chance = 0.95 - Double(length - 30) * 0.010
        } else {
            chance = 0.80 - Double(length - 45) * fallPerYard(leg: leg)
        }
        // A try is kicked from the middle of the field by a kicker nobody is trying very
        // hard to block, and the sport converts it at a better rate than a field goal of
        // the same length. Running it through the field-goal curve unmodified is what
        // made extra points a coin-flip-adjacent 85%.
        if isTry { chance += 0.025 }
        chance += (accuracy - averageAccuracy) * 0.004
        if isWet { chance -= 0.03 }
        return min(0.99, max(0.02, chance))
    }

    /// The same number from the kick's raw length and the afternoon it is kicked in.
    static func makeChance(
        rawLength: Int, leg: Double, accuracy: Double, isTry: Bool, context: PlayContext
    ) -> Double {
        makeChance(
            length: effectiveLength(
                rawLength, weather: context.weather, altitudeFeet: context.altitudeFeet),
            leg: leg, accuracy: accuracy, isTry: isTry,
            isWet: context.weather.precipitation != .none)
    }

    // MARK: - Whether it is worth sending him out

    /// The odds a routine attempt is taken at: about even.
    ///
    /// A kick that is worse than a coin flip is three points a side is not going to get
    /// against forty yards of field position it is giving away for them. **As the curve
    /// stands this almost never binds** — an average leg is better than even money out to
    /// sixty-four yards, which is fifteen yards past where any leg is sent out for one —
    /// so `reach` is what decides nearly every attempt today. That is the make curve's
    /// *level* at long range reading high, which is a retune's to move and not a fix's;
    /// when it comes down this threshold starts to bite.
    static let routineOdds = 0.50

    /// The odds a kick is tried at when a half is ending, where the alternative is
    /// nothing at all. A third is enough to be worth the down that is about to stop
    /// existing.
    static let lastChanceOdds = 0.33

    /// Whether this side sends the unit out from here.
    ///
    /// Two questions, both the kicker's: can he get it there, and is it worth taking. A
    /// half ending moves both — it stretches him the four yards between the kick he would
    /// take and the kick he will try, and it drops what the kick has to be worth, because
    /// a punt buys nothing when there is no next drive to buy it for.
    ///
    /// The conditions arrive through the length: a wind in his face and the cold make a
    /// fifty-two yarder play longer than fifty-two, and shorten the range by exactly that
    /// much.
    static func isInRange(
        rawLength: Int, context: PlayContext, aHalfIsEnding: Bool
    ) -> Bool {
        let man = kicker(for: context)
        let length = effectiveLength(
            rawLength, weather: context.weather, altitudeFeet: context.altitudeFeet)
        let furthest = reach(leg: man.leg) - (aHalfIsEnding ? 0 : routineMargin)
        guard Double(length) <= furthest else { return false }
        let chance = makeChance(
            length: length, leg: man.leg, accuracy: man.accuracy, isTry: false,
            isWet: context.weather.precipitation != .none)
        return chance >= (aHalfIsEnding ? lastChanceOdds : routineOdds)
    }
}
