/// Points scored on a play, and by whom.
public enum Scoring: Sendable, Hashable, Codable {
    /// Scored by the team that had the ball.
    case touchdown
    case fieldGoal
    case extraPoint
    case twoPointConversion
    /// Scored by the team that did *not* have the ball — a pick six, or a fumble
    /// returned. The distinction matters because the wrong team gets the points and
    /// the wrong team kicks off.
    case defensiveTouchdown
    /// Also scored by the defence, and it is the one where the scoring team then
    /// *receives* rather than kicks.
    case safety
}

/// What the sport does next, given how the last play ended.
///
/// A pure function of the rules and the outcome — no randomness, no engine. Both
/// resolvers hand their outcome to the same arithmetic
/// ([ADR-0012](../../../../docs/adr/0012-play-resolver-seam.md)), because where the ball
/// is spotted after a missed field goal is not a matter of physics.
public struct Advancement: Sendable, Hashable {

    /// The new spot, in the frame of whoever has the ball next.
    public var ballOn: UInt8
    public var down: Down
    public var distance: UInt8
    /// Whether the ball changed hands.
    public var possessionChanged: Bool
    public var scoring: Scoring?
    public var points: Int16
    /// A try — extra point or two-point attempt — is owed before anything else.
    public var requiresTry: Bool
    /// A kickoff is owed. Following a safety it is the *scoring* team who receives.
    public var requiresKickoff: Bool

    public init(
        ballOn: UInt8,
        down: Down,
        distance: UInt8,
        possessionChanged: Bool = false,
        scoring: Scoring? = nil,
        points: Int16 = 0,
        requiresTry: Bool = false,
        requiresKickoff: Bool = false
    ) {
        self.ballOn = ballOn
        self.down = down
        self.distance = distance
        self.possessionChanged = possessionChanged
        self.scoring = scoring
        self.points = points
        self.requiresTry = requiresTry
        self.requiresKickoff = requiresKickoff
    }
}

extension Rules {

    /// A fresh set of downs at this spot.
    ///
    /// Inside the ten there is no first and ten: the marker would be past the goal line,
    /// so the distance is to the goal line instead.
    public func freshDowns(at ballOn: UInt8) -> (down: Down, distance: UInt8) {
        (.first, min(yardsToGain, max(1, ballOn)))
    }

    /// A try — the kick or the play after a touchdown.
    ///
    /// It is neither a field goal nor a touchdown, however it ends, and treating it as
    /// one was worth two extra points every time a team kicked: `advance` used to switch
    /// on the ending alone, so a made extra point paid three as a field goal and a
    /// successful conversion paid six as a touchdown. Nothing follows a try but a
    /// kickoff, whether it was good or not.
    private func advanceTry(_ outcome: Outcome) -> Advancement {
        let good =
            outcome.kind == .extraPoint
            ? outcome.endedIn == .fieldGoalGood
            : outcome.endedIn == .touchdown
        let isKick = outcome.kind == .extraPoint

        return Advancement(
            ballOn: ballOnFromOwnYard(kickoffFromOwnYard), down: .first, distance: yardsToGain,
            scoring: good ? (isKick ? .extraPoint : .twoPointConversion) : nil,
            points: good ? (isKick ? extraPoint : twoPointConversion) : 0,
            requiresKickoff: true)
    }

    /// Where the ball goes next, and who has it.
    public func advance(from situation: Situation, outcome: Outcome) -> Advancement {
        // What kind of play this was decides the rules that apply to it, and asking only
        // how it *ended* is why a try was scored as a field goal and a kickoff touchback
        // was spotted like a punt's.
        if outcome.kind == .extraPoint || outcome.kind == .twoPointConversion {
            return advanceTry(outcome)
        }

        // The offence's frame throughout: yards gained bring the ball closer to the
        // opponent's goal line, so a gain *reduces* `ballOn`.
        let restingSpot =
            outcome.finalSpot.map(Int.init)
            ?? (Int(situation.ballOn) - Int(outcome.yards))
        let spot = UInt8(max(0, min(100, restingSpot)))

        switch outcome.endedIn {
        case .touchdown:
            return Advancement(
                ballOn: extraPointSnapYard, down: .first, distance: 1,
                scoring: .touchdown, points: touchdown, requiresTry: true)

        case .safety:
            // The defence scores, and then *receives* the free kick. The team scored
            // upon kicks from its own twenty.
            return Advancement(
                ballOn: ballOnFromOwnYard(safetyKickoffOwnYard), down: .first,
                distance: yardsToGain, possessionChanged: true, scoring: .safety,
                points: safety, requiresKickoff: true)

        case .fieldGoalGood:
            return Advancement(
                ballOn: ballOnFromOwnYard(kickoffFromOwnYard), down: .first,
                distance: yardsToGain, scoring: .fieldGoal, points: fieldGoal,
                requiresKickoff: true)

        case .fieldGoalMissed:
            // The defence takes over at the spot of the kick, not the line of
            // scrimmage — a miss from your own forty is worse field position than a
            // punt. Never worse for them than a touchback.
            let kickSpot = Int(situation.ballOn) + Int(fieldGoalSnapDepth)
            let theirSpot = UInt8(max(1, min(Int(puntTouchbackSpot), 100 - kickSpot)))
            let downs = freshDowns(at: theirSpot)
            return Advancement(
                ballOn: theirSpot, down: downs.down, distance: downs.distance,
                possessionChanged: true)

        case .touchback:
            // A kickoff into the end zone and a punt into it are not spotted alike: the
            // kickoff comes out to the thirty and the punt to the twenty. Both used the
            // punt's spot, which cost the receiving team ten yards on every possession
            // after a score.
            let spot = outcome.kind == .kickoff ? kickoffTouchbackSpot : puntTouchbackSpot
            let downs = freshDowns(at: spot)
            return Advancement(
                ballOn: spot, down: downs.down, distance: downs.distance,
                possessionChanged: true)

        case .intercepted, .fumbleLost, .blocked, .fairCatch, .downed:
            // The ball is at `spot` in the old offence's frame; flipping it is what
            // makes the new offence's field position read correctly.
            let theirSpot = 100 - Int(spot)
            if theirSpot <= 0 {
                return Advancement(
                    ballOn: ballOnFromOwnYard(kickoffFromOwnYard), down: .first,
                    distance: yardsToGain, possessionChanged: true,
                    scoring: .defensiveTouchdown, points: touchdown,
                    requiresTry: true, requiresKickoff: false)
            }
            let clamped = UInt8(max(1, min(99, theirSpot)))
            let downs = freshDowns(at: clamped)
            return Advancement(
                ballOn: clamped, down: downs.down, distance: downs.distance,
                possessionChanged: true)

        case .penaltyEnforced:
            // Enforcement decides the spot and the down; nothing advances here.
            return Advancement(
                ballOn: situation.ballOn, down: situation.down, distance: situation.distance)

        case .incomplete:
            // An incompletion never moves the ball, whatever yardage the resolver
            // reported. This is a rule, not a resolver responsibility.
            return advanceDown(from: situation, gained: 0, restingAt: situation.ballOn)

        case .tackled, .outOfBounds, .fumbleRecovered:
            return advanceDown(from: situation, gained: outcome.yards, restingAt: spot)
        }
    }

    /// The ordinary case: did they get it, and if not is there another down?
    private func advanceDown(
        from situation: Situation, gained: Int16, restingAt spot: UInt8
    )
        -> Advancement
    {
        // The ball is never spotted in an end zone — a spot of zero is a touchdown and a
        // hundred is a safety, and both are endings the resolver was supposed to report.
        // Clamping keeps the situation legal without reinterpreting the play: a
        // contradiction between yardage and ending is the resolver's bug to fix, and
        // silently turning a tackle into a score would hide it
        // ([ADR-0012](../../../../docs/adr/0012-play-resolver-seam.md)).
        let ballOn = max(1, min(99, spot))

        if gained >= Int16(situation.distance) {
            let downs = freshDowns(at: ballOn)
            return Advancement(ballOn: ballOn, down: downs.down, distance: downs.distance)
        }

        guard let next = situation.down.next else {
            // Fourth down, short of the marker. The ball goes over where it lies.
            let theirSpot = UInt8(max(1, min(99, 100 - Int(ballOn))))
            let downs = freshDowns(at: theirSpot)
            return Advancement(
                ballOn: theirSpot, down: downs.down, distance: downs.distance,
                possessionChanged: true)
        }

        let remaining = Int(situation.distance) - Int(gained)
        return Advancement(
            ballOn: ballOn, down: next,
            distance: UInt8(max(1, min(Int(UInt8.max), remaining))))
    }
}
