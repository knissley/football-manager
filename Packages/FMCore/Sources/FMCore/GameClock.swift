/// What the clock does after a play.
public enum ClockBehavior: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// Never stopped. The interval to the next snap runs off the clock.
    case keepsRunning = 0
    /// Stops, then restarts when the officials mark the ball ready. The offence loses
    /// the play clock but not the game clock.
    case stopsUntilReadyForPlay = 1
    /// Stops until the next snap. This is the one that makes a two-minute drill work.
    case stopsUntilSnap = 2

    public var stopsClock: Bool { self != .keepsRunning }
}

extension Rules {

    /// What the clock does after a play ends this way.
    ///
    /// **The out-of-bounds rule is the one most often modelled wrong**, and it is
    /// exactly the rule that decides whether a two-minute drill works. Going out of
    /// bounds normally stops the clock only until the ball is marked ready; inside the
    /// last two minutes of the first half, or the last five of the second, it stops
    /// until the snap. Get that backwards and either every drill is trivial or none of
    /// them are possible.
    ///
    /// Note what is absent: **gaining a first down does not stop the clock.** It runs
    /// while the chains move.
    public func clockBehavior(
        after ending: PlayEnding, quarter: UInt8, clockRemaining: UInt16
    ) -> ClockBehavior {
        switch ending {
        case .incomplete, .touchdown, .intercepted, .fumbleLost, .touchback, .safety,
            .fieldGoalGood, .fieldGoalMissed, .fairCatch, .blocked:
            return .stopsUntilSnap
        case .outOfBounds:
            return isInLateClockWindow(quarter: quarter, clockRemaining: clockRemaining)
                ? .stopsUntilSnap : .stopsUntilReadyForPlay
        // A punt downed in bounds and a fumble recovered by the offence both leave the
        // ball live and the clock with it.
        case .tackled, .fumbleRecovered, .downed:
            return .keepsRunning
        // Enforcement stops the clock; whether it restarts on the ready signal or the
        // snap depends on the foul, which the enforcement layer decides.
        case .penaltyEnforced:
            return .stopsUntilReadyForPlay
        }
    }

    /// Whether the out-of-bounds rule is in its late-game form.
    ///
    /// The window is longer in the second half than the first, which is a real asymmetry
    /// and not a mistake.
    public func isInLateClockWindow(quarter: UInt8, clockRemaining: UInt16) -> Bool {
        let half = quarters / 2
        if quarter == half {
            return clockRemaining <= outOfBoundsStopsClockFirstHalf
        }
        if quarter >= quarters {
            return clockRemaining <= outOfBoundsStopsClockSecondHalf
        }
        return false
    }

    /// Whether this play crosses the two-minute warning, which stops the clock on its
    /// own regardless of how the play ended.
    public func crossesTwoMinuteWarning(
        quarter: UInt8, clockBefore: UInt16, clockAfter: UInt16
    ) -> Bool {
        guard isEndOfHalf(quarter: quarter) else { return false }
        return clockBefore > twoMinuteWarning && clockAfter <= twoMinuteWarning
    }
}

/// How long the offence takes between snaps.
///
/// Live play is a handful of seconds; the rest of the interval is the offence spending
/// the play clock, and that spending is a *choice*. It is the mechanism behind both a
/// two-minute drill and a four-minute one.
extension Tempo {

    /// Seconds burned between the ball being ready and the next snap.
    public var secondsBetweenSnaps: UInt16 {
        switch self {
        case .hurryUp: return 8
        case .fast: return 16
        case .normal: return 29
        case .slow: return 34
        case .bleedClock: return 39
        }
    }
}

/// The game clock, and the rules for running it down.
public struct GameClock: Sendable, Hashable, Codable {

    public var quarter: UInt8
    /// Seconds remaining in the quarter.
    public var secondsRemaining: UInt16
    /// Whether the two-minute warning has already been taken this half.
    public var twoMinuteWarningTaken: Bool

    public init(quarter: UInt8 = 1, secondsRemaining: UInt16, twoMinuteWarningTaken: Bool = false) {
        self.quarter = quarter
        self.secondsRemaining = secondsRemaining
        self.twoMinuteWarningTaken = twoMinuteWarningTaken
    }

    public static func start(_ rules: Rules) -> GameClock {
        GameClock(quarter: 1, secondsRemaining: rules.quarterLength)
    }

    public var isExpired: Bool { secondsRemaining == 0 }
}

extension GameClock {

    /// What one snap costs the clock.
    public struct Elapsed: Sendable, Hashable {
        /// Seconds the play itself took.
        public let duringPlay: UInt16
        /// Seconds burned between the previous whistle and this snap.
        public let beforeSnap: UInt16

        public var total: UInt16 { duringPlay &+ beforeSnap }

        public init(duringPlay: UInt16, beforeSnap: UInt16) {
            self.duringPlay = duringPlay
            self.beforeSnap = beforeSnap
        }
    }

    /// Time consumed getting to and through the next snap.
    ///
    /// The pre-snap interval only costs the clock when the clock was running into it.
    /// A team down four with sixty seconds left and no timeouts lives entirely on this
    /// distinction: after an incompletion the huddle is free, and after a tackle in
    /// bounds it is not.
    public static func elapsed(
        playDuration: UInt16,
        tempo: Tempo,
        previousBehavior: ClockBehavior
    ) -> Elapsed {
        switch previousBehavior {
        case .stopsUntilSnap:
            return Elapsed(duringPlay: playDuration, beforeSnap: 0)
        case .stopsUntilReadyForPlay:
            // The officials' spot buys a few seconds back; the rest of the play clock
            // still runs.
            let saved: UInt16 = 6
            let burned = tempo.secondsBetweenSnaps > saved ? tempo.secondsBetweenSnaps - saved : 0
            return Elapsed(duringPlay: playDuration, beforeSnap: burned)
        case .keepsRunning:
            return Elapsed(duringPlay: playDuration, beforeSnap: tempo.secondsBetweenSnaps)
        }
    }

    /// Run the clock down, stopping at the two-minute warning if this play crosses it.
    ///
    /// Returns whether the warning was taken, because it is a stoppage in its own right
    /// and the caller has to know the clock is now stopped.
    public mutating func run(_ seconds: UInt16, rules: Rules) -> Bool {
        guard seconds > 0 else { return false }

        let target = secondsRemaining > seconds ? secondsRemaining - seconds : 0

        if !twoMinuteWarningTaken, rules.isEndOfHalf(quarter: quarter),
            secondsRemaining > rules.twoMinuteWarning, target <= rules.twoMinuteWarning
        {
            // The clock stops *at* two minutes, not past it. Letting the play run
            // through the warning is how a half quietly loses a snap.
            secondsRemaining = rules.twoMinuteWarning
            twoMinuteWarningTaken = true
            return true
        }

        secondsRemaining = target
        return false
    }

    /// Move to the next period. Returns `nil` when regulation is over.
    ///
    /// The two-minute warning resets at the half, not every quarter — it is a
    /// once-per-half stoppage.
    public func advancingPeriod(rules: Rules, isPostseason: Bool = false) -> GameClock? {
        let next = quarter + 1
        if next > rules.quarters {
            return GameClock(
                quarter: next, secondsRemaining: rules.overtimeLength(isPostseason: isPostseason),
                twoMinuteWarningTaken: true)
        }
        let entersSecondHalf = next == (rules.quarters / 2) + 1
        return GameClock(
            quarter: next, secondsRemaining: rules.quarterLength,
            twoMinuteWarningTaken: entersSecondHalf ? false : twoMinuteWarningTaken)
    }
}
