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
    ///
    /// This reads the ending alone, and the ending alone cannot tell a fourth-down stop
    /// from a first-down tackle: both end `.tackled`. A change of possession stops the
    /// clock whatever the ending (4-4-i), and the overload that takes it is what the
    /// game state consults.
    public func clockBehavior(
        after ending: PlayEnding, quarter: UInt8, isPostseason: Bool, clockRemaining: UInt16
    ) -> ClockBehavior {
        switch ending {
        case .incomplete, .touchdown, .intercepted, .fumbleLost, .touchback, .safety,
            .fieldGoalGood, .fieldGoalMissed, .fairCatch, .blocked:
            return .stopsUntilSnap
        // A downed kick has changed hands, which is a stoppage in its own right (4-4-i).
        case .downed:
            return .stopsUntilSnap
        case .outOfBounds:
            return isInLateClockWindow(
                quarter: quarter, isPostseason: isPostseason, clockRemaining: clockRemaining)
                ? .stopsUntilSnap : .stopsUntilReadyForPlay
        // A tackle in bounds and a fumble recovered by the offence both leave the ball
        // live and the clock with it.
        case .tackled, .fumbleRecovered:
            return .keepsRunning
        // Enforcement stops the clock; whether it restarts on the ready signal or the
        // snap depends on the foul, which the enforcement layer decides.
        case .penaltyEnforced:
            return .stopsUntilReadyForPlay
        }
    }

    /// What the clock does after a play, given whether the ball changed hands.
    ///
    /// **Any change of possession stops the clock until the snap**, whatever the
    /// ending (2025 rulebook, 4-4-i, 4-3-2-a-1): a fourth-down stop, a returned punt
    /// and a fumble the defence recovers all end with the new offence's huddle free.
    /// Without this, a turnover on downs ended `.tackled` and cost the team taking over
    /// its whole play clock.
    public func clockBehavior(
        after ending: PlayEnding, possessionChanged: Bool, quarter: UInt8, isPostseason: Bool,
        clockRemaining: UInt16
    ) -> ClockBehavior {
        if possessionChanged { return .stopsUntilSnap }
        return clockBehavior(
            after: ending, quarter: quarter, isPostseason: isPostseason,
            clockRemaining: clockRemaining)
    }

    /// Whether the out-of-bounds rule is in its late-game form (4-3-2-a-2, a-3): inside
    /// the last two minutes of a period timed as a second, or the last five of one
    /// timed as a fourth — the fourth quarter, regular-season overtime (16-1-3-e), and
    /// the second and fourth postseason overtime periods, which end as the halves do
    /// (16-1-4-h). Which is which is `periodTiming`.
    ///
    /// The window is longer in the second half than the first, which is a real asymmetry
    /// and not a mistake.
    public func isInLateClockWindow(
        quarter: UInt8, isPostseason: Bool, clockRemaining: UInt16
    ) -> Bool {
        switch periodTiming(quarter: quarter, isPostseason: isPostseason) {
        case .firstOrThird: return false
        case .second: return clockRemaining <= outOfBoundsStopsClockFirstHalf
        case .fourth: return clockRemaining <= outOfBoundsStopsClockSecondHalf
        }
    }

    /// After a foul that stopped a running clock, whether the clock waits for the snap
    /// rather than restarting on the ready-for-play signal (2025 rulebook, 4-3-2-e).
    ///
    /// The clock restarts as though the foul had not occurred — on the ready, since it
    /// was running — except that it starts on the snap after the two-minute warning of
    /// the first half (e-1), inside the last five minutes of the second half (e-2), or
    /// for an offensive foul that stops the clock before a snap anywhere in the fourth
    /// period or regular-season overtime (e-3). The first two are the windows of the
    /// out-of-bounds rule (4-3-2-a), and are read the same way, in the postseason's
    /// overtime periods as in its halves (16-1-4-h); the third names its own periods,
    /// and a postseason overtime period is not among them. A clock that was stopped at
    /// the flag waits for the snap either way.
    ///
    /// The runoff's restart (4-3-2-g) and the offence's choice after a defensive foul
    /// inside two minutes (4-7-1 Item 2) are specific rules that prescribe otherwise
    /// (e-5), and are decided before this is asked.
    public func clockStartsOnTheSnapAfterFoul(
        byOffense: Bool, quarter: UInt8, isPostseason: Bool, clockRemaining: UInt16
    ) -> Bool {
        if isInLateClockWindow(
            quarter: quarter, isPostseason: isPostseason, clockRemaining: clockRemaining)
        {
            return true
        }
        return byOffense
            && isFourthPeriodOrRegularSeasonOvertime(quarter: quarter, isPostseason: isPostseason)
    }

    /// Whether this play crosses the two-minute warning, which stops the clock on its
    /// own regardless of how the play ended.
    public func crossesTwoMinuteWarning(
        quarter: UInt8, isPostseason: Bool, clockBefore: UInt16, clockAfter: UInt16
    ) -> Bool {
        guard isEndOfHalf(quarter: quarter, isPostseason: isPostseason) else { return false }
        return clockBefore > twoMinuteWarning && clockAfter <= twoMinuteWarning
    }
}

/// How long the offence takes between snaps.
///
/// Live play is a handful of seconds; the rest of the interval is the offence spending
/// the play clock, and that spending is a *choice*. It is the mechanism behind both a
/// two-minute drill and a four-minute one.
extension Tempo {

    /// The play clock the intervals below are written against: the ordinary forty of
    /// 4-6-1, counted from the end of the previous play. Against a shorter clock the
    /// offence keeps the same slack, scaled — see `PlayClock.remainingAtIntendedSnap`.
    public static let referencePlayClock: UInt16 = 40

    /// Seconds from the end of the previous play to the next snap, on the reference
    /// play clock.
    public var secondsBetweenSnaps: UInt16 {
        switch self {
        case .hurryUp: return 8
        case .fast: return 16
        case .normal: return 31
        case .slow: return 36
        case .bleedClock: return 39
        }
    }

    /// What the reference play clock reads when the offence means to snap: the slack
    /// it leaves itself, from most of the clock at hurry-up to a single second bleeding
    /// it.
    public var slack: UInt16 { Self.referencePlayClock - secondsBetweenSnaps }
}

/// The play clock in force before a snap (2025 rulebook, 4-6).
///
/// Two lengths, and two places to count from. The forty seconds after an ordinary play
/// start when that play ends (4-6-1); the twenty-five after an administrative stoppage
/// start on the Referee's whistle (4-6-2), and so does every reset — to thirty after a
/// runoff (4-7-1 Item 1, 4-6-3-c), and back to forty after a defensive act that
/// conserves time (4-7-1 Item 2, 4-6-3-b). `Rules` says which follows what; this is the
/// arithmetic of counting one down.
public struct PlayClock: Sendable, Hashable, Codable {

    /// Seconds on the clock when it starts.
    public var seconds: UInt8
    /// Whether it starts on the ready-for-play signal rather than when the previous
    /// play ended.
    public var startsOnTheReady: Bool

    public init(seconds: UInt8, startsOnTheReady: Bool) {
        self.seconds = seconds
        self.startsOnTheReady = startsOnTheReady
    }

    /// Seconds after the end of the previous play at which this clock expires. A clock
    /// that starts on the ready starts `GameClock.readyForPlayDelay` seconds later than
    /// one that starts when the play ends.
    public var expiresAfter: UInt16 {
        UInt16(seconds) + (startsOnTheReady ? GameClock.readyForPlayDelay : 0)
    }

    /// What this clock reads when an offence playing at `tempo` means to snap: the
    /// tempo's slack on the reference clock, scaled to this one, and never less than a
    /// second — so a team bleeding the clock snaps with one second left on a
    /// twenty-five as on a forty, and a hurry-up offence is on the ball either way.
    public func remainingAtIntendedSnap(at tempo: Tempo) -> UInt8 {
        let reference = Int(Tempo.referencePlayClock)
        let scaled = (Int(tempo.slack) * Int(seconds) + reference / 2) / reference
        return UInt8(max(1, min(Int(seconds), scaled)))
    }

    /// Seconds after the end of the previous play at which an offence playing at
    /// `tempo` means to snap. On the reference clock this is the tempo's own interval.
    public func intendedSnap(at tempo: Tempo) -> UInt16 {
        expiresAfter - UInt16(remainingAtIntendedSnap(at: tempo))
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

    /// Seconds between a play ending and the officials marking the ball ready for play.
    ///
    /// A modelling convention, not a rule: the interval between snaps is measured from
    /// the end of the previous play, and a game clock that restarts on the ready signal
    /// restarts this much later than one that never stopped. It is also where a play
    /// clock that starts on the whistle (4-6-2) starts.
    public static let readyForPlayDelay: UInt16 = 6

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

    /// Time consumed getting to and through the next snap, the snap coming `snapAfter`
    /// seconds after the previous play ended.
    ///
    /// The pre-snap interval only costs the clock when the clock was running into it.
    /// A team down four with sixty seconds left and no timeouts lives entirely on this
    /// distinction: after an incompletion the huddle is free, and after a tackle in
    /// bounds it is not.
    public static func elapsed(
        playDuration: UInt16,
        snapAfter: UInt16,
        previousBehavior: ClockBehavior
    ) -> Elapsed {
        switch previousBehavior {
        case .stopsUntilSnap:
            return Elapsed(duringPlay: playDuration, beforeSnap: 0)
        case .stopsUntilReadyForPlay:
            // The officials' spot buys a few seconds back; the rest of the interval
            // still runs.
            let saved = readyForPlayDelay
            return Elapsed(
                duringPlay: playDuration, beforeSnap: snapAfter > saved ? snapAfter - saved : 0)
        case .keepsRunning:
            return Elapsed(duringPlay: playDuration, beforeSnap: snapAfter)
        }
    }

    /// The same, for an offence at `tempo` against the play clock in force: the snap
    /// comes when the tempo means it to, which on the reference clock is
    /// `tempo.secondsBetweenSnaps`.
    public static func elapsed(
        playDuration: UInt16,
        tempo: Tempo,
        playClock: PlayClock,
        previousBehavior: ClockBehavior
    ) -> Elapsed {
        elapsed(
            playDuration: playDuration, snapAfter: playClock.intendedSnap(at: tempo),
            previousBehavior: previousBehavior)
    }

    /// Run the clock through one snap: the interval before it, then the play.
    ///
    /// The two-minute warning is a stoppage *between* downs (3-41, 4-4-h). When the
    /// clock reaches 2:00 in the huddle it stops there, the snap restarts it, and the
    /// play then runs from 2:00. When a down is under way as the clock passes 2:00, the
    /// down finishes and the clock is dead after it, at whatever it reads. Running the
    /// whole interval as one lump and clamping it at 2:00 did neither: it swallowed a
    /// play snapped just before the warning and cut short a down that was under way.
    ///
    /// Which periods have a warning in them is `Rules.isEndOfHalf`: the second and the
    /// fourth (3-41), regular-season overtime (16-1-3-e), and in the postseason a
    /// second or fourth overtime period (16-1-4-h).
    ///
    /// Returns whether the warning was taken, because it is a stoppage in its own right
    /// and the caller has to know the clock is now stopped.
    public mutating func run(_ elapsed: Elapsed, rules: Rules, isPostseason: Bool) -> Bool {
        let warningApplies =
            !twoMinuteWarningTaken
            && rules.isEndOfHalf(quarter: quarter, isPostseason: isPostseason)
        var taken = false

        if elapsed.beforeSnap > 0 {
            let afterHuddle =
                secondsRemaining > elapsed.beforeSnap ? secondsRemaining - elapsed.beforeSnap : 0
            if warningApplies, secondsRemaining > rules.twoMinuteWarning,
                afterHuddle <= rules.twoMinuteWarning
            {
                secondsRemaining = rules.twoMinuteWarning
                twoMinuteWarningTaken = true
                taken = true
            } else {
                secondsRemaining = afterHuddle
            }
        }

        if elapsed.duringPlay > 0 {
            let afterPlay =
                secondsRemaining > elapsed.duringPlay ? secondsRemaining - elapsed.duringPlay : 0
            if !taken, warningApplies, secondsRemaining > rules.twoMinuteWarning,
                afterPlay <= rules.twoMinuteWarning
            {
                twoMinuteWarningTaken = true
                taken = true
            }
            secondsRemaining = afterPlay
        }

        return taken
    }

    /// Run a down's worth of clock with nothing before the snap: a down under way, with
    /// the two-minute warning taken as it ends if the clock passes 2:00 during it.
    public mutating func run(_ seconds: UInt16, rules: Rules, isPostseason: Bool) -> Bool {
        run(Elapsed(duringPlay: seconds, beforeSnap: 0), rules: rules, isPostseason: isPostseason)
    }

    /// Move to the next period: a quarter of regulation, or a period of overtime.
    ///
    /// The two-minute warning is a once-per-half stoppage, so it comes back when a half
    /// opens and not every period: at the third quarter, at the overtime period, and in
    /// the postseason at every odd overtime period, whose pairs are halves (16-1-4-h).
    /// `Rules.opensHalf` says which.
    public func advancingPeriod(rules: Rules, isPostseason: Bool) -> GameClock? {
        let next = quarter + 1
        let length =
            next > rules.quarters
            ? rules.overtimeLength(isPostseason: isPostseason) : rules.quarterLength
        return GameClock(
            quarter: next, secondsRemaining: length,
            twoMinuteWarningTaken: rules.opensHalf(quarter: next) ? false : twoMinuteWarningTaken)
    }
}
