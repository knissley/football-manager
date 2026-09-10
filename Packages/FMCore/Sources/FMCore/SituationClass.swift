/// The shared vocabulary for *what kind of moment this is*.
///
/// Football is situational before it is anything else: third and two is a
/// different sport from third and eleven, and both change again when you are
/// down four with ninety seconds left. Every part of this game needs to reason
/// about that — both play-callers, gameplan rules, tendency tables, the
/// analysis layer, and the news — and if each invents its own buckets they will
/// disagree, quietly, in ways nobody notices until a tendency report contradicts
/// a play-by-play.
///
/// So the classification lives here, once. **It decides nothing.** It is a
/// description that other systems key off, which is what lets a gameplan rule,
/// an AI policy and a post-game report all mean the same thing by "late and
/// long".
///
/// There is one of these per snap, not one per sideline. Like `Situation`, it
/// reads from the *offence's* point of view — `isMustPass` means the team with
/// the ball has to throw, whichever bench is asking. The defence reads the same
/// value and draws the opposite conclusion from it, which is the point: a
/// coordinator dialling up a coverage and the offence calling into it are
/// reasoning about one shared description of the moment, so they cannot
/// disagree about what the moment *is*. Never build a mirrored copy with the
/// differential flipped — that is two vocabularies again.
public struct SituationClass: Sendable, Hashable, Codable {

    public let downAndDistance: DownAndDistanceClass
    public let field: FieldZone
    public let score: ScoreState
    public let time: TimeState

    /// - Parameters:
    ///   - situation: the moment to classify.
    ///   - rules: the rules in force, which decide where the halves end and where the
    ///     two-minute threshold sits. The standard rules by default, so that a caller
    ///     with no variant in hand reads the same vocabulary as one with.
    public init(_ situation: Situation, rules: Rules = .standard) {
        downAndDistance = DownAndDistanceClass(situation)
        field = situation.fieldZone
        score = ScoreState(differential: situation.scoreDifferential)
        time = TimeState(situation, rules: rules)
    }
}

/// Down and distance, bucketed the way the sport talks about it.
///
/// One to three, four to six, seven or more — the same three widths on second, third
/// and fourth down. Seven is where the ground stops being a realistic answer to the
/// distance; a bucket that ran to seven put third and seven in with third and four,
/// which is a different down with a different menu.
public enum DownAndDistanceClass: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case firstDown = 0
    case secondShort = 1
    case secondMedium = 2
    case secondLong = 3
    case thirdShort = 4
    case thirdMedium = 5
    case thirdLong = 6
    case fourthShort = 7
    case fourthMedium = 8
    case fourthLong = 9
    case goalToGo = 10

    public init(_ situation: Situation) {
        if situation.isGoalToGo {
            self = .goalToGo
            return
        }
        switch situation.down {
        case .first:
            self = .firstDown
        case .second:
            self =
                situation.distance <= 3
                ? .secondShort
                : (situation.distance <= 6 ? .secondMedium : .secondLong)
        case .third:
            self =
                situation.distance <= 3
                ? .thirdShort
                : (situation.distance <= 6 ? .thirdMedium : .thirdLong)
        case .fourth:
            self =
                situation.distance <= 3
                ? .fourthShort
                : (situation.distance <= 6 ? .fourthMedium : .fourthLong)
        }
    }

    /// A down where failing gives the ball away, so the calculus changes
    /// entirely.
    public var isLastDown: Bool {
        self == .fourthShort || self == .fourthMedium || self == .fourthLong
    }

    /// Third or fourth and seven or more: far enough that the ground is not a realistic
    /// answer with the down on the line, which is what lets a defence stop honouring the
    /// run.
    ///
    /// It is still a *description*. Second and eight has a whole extra play behind it
    /// and third and four is a down the sport runs on constantly; reading either as a
    /// passing down told the defence something that was not true, and a caller that
    /// obeyed it never ran on them at all.
    public var isPassingDown: Bool {
        self == .thirdLong || self == .fourthLong
    }

    /// Short enough that a defence must respect the run.
    public var isShortYardage: Bool {
        self == .thirdShort || self == .fourthShort || self == .goalToGo
    }
}

/// The scoreboard, from the possessing team's point of view.
///
/// `isTrailing` therefore means the offence is behind, read from either
/// sideline.
///
/// Bucketed by *scores* rather than points, because that is how the decision
/// actually changes: down four and down seven are the same problem, down nine
/// is a different one.
public enum ScoreState: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case trailingThreeScores = 0
    case trailingTwoScores = 1
    case trailingOneScore = 2
    case tied = 3
    case leadingOneScore = 4
    case leadingTwoScores = 5
    case leadingThreeScores = 6

    public init(differential: Int16) {
        switch differential {
        case ..<(-16): self = .trailingThreeScores
        case ..<(-8): self = .trailingTwoScores
        case ..<0: self = .trailingOneScore
        case 0: self = .tied
        case ..<9: self = .leadingOneScore
        case ..<17: self = .leadingTwoScores
        default: self = .leadingThreeScores
        }
    }

    public var isTrailing: Bool { rawValue < ScoreState.tied.rawValue }
    public var isLeading: Bool { rawValue > ScoreState.tied.rawValue }

    /// Close enough that a single possession decides it.
    public var isOneScoreGame: Bool {
        self == .trailingOneScore || self == .tied || self == .leadingOneScore
    }
}

/// Where in the game this is, in the terms that change behaviour.
public enum TimeState: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case opening = 0
    case middle = 1
    /// Inside two minutes of the first half.
    case twoMinuteFirstHalf = 2
    case thirdQuarter = 3
    /// Fourth quarter, but not yet in the endgame.
    case fourthQuarter = 4
    /// The last five minutes, where a leading team starts thinking about the
    /// clock rather than the scoreboard.
    case clockBurn = 5
    /// Inside two minutes of the game.
    case twoMinuteGame = 6
    case overtime = 7

    /// The buckets are placed by the game's structure rather than by literal period
    /// numbers: the last period of the first half, the last period of regulation, and
    /// anything past regulation. `Rules.quarters` and `Rules.twoMinuteWarning` decide
    /// where those fall, so a two-period variant classifies correctly and a postseason
    /// sixth period is overtime like the fifth.
    ///
    /// The five-minute clock-burn threshold is a modelling convention about when a
    /// leading team starts playing the clock, not a rule, and stays a literal.
    public init(_ situation: Situation, rules: Rules = .standard) {
        let endOfFirstHalf = rules.quarters / 2
        let endOfRegulation = rules.quarters
        let twoMinutes = situation.clockRemaining <= rules.twoMinuteWarning

        if situation.quarter > endOfRegulation {
            self = .overtime
        } else if situation.quarter == endOfRegulation {
            if twoMinutes {
                self = .twoMinuteGame
            } else if situation.clockRemaining <= 300 {
                self = .clockBurn
            } else {
                self = .fourthQuarter
            }
        } else if situation.quarter == endOfFirstHalf {
            self = twoMinutes ? .twoMinuteFirstHalf : .middle
        } else if situation.quarter < endOfFirstHalf {
            self = .opening
        } else {
            self = .thirdQuarter
        }
    }

    /// Both two-minute situations, where the clock stops on an out-of-bounds
    /// play and every decision is about time as much as yards.
    public var isTwoMinute: Bool {
        self == .twoMinuteFirstHalf || self == .twoMinuteGame
    }

    /// Late enough that possessions are visibly finite.
    public var isEndgame: Bool {
        self == .clockBurn || self == .twoMinuteGame || self == .overtime
    }
}

extension SituationClass {

    /// The offence has to throw, and the defence knows it.
    ///
    /// Either the distance demands it — third or fourth and seven or more — or the
    /// clock does: inside two minutes, trailing, with the ball needed back. Tied inside
    /// two minutes of the game counts too, unless you are backed up, where a punt and
    /// overtime are a fine outcome.
    ///
    /// This is the single most useful situational read in the sport, and it belongs to
    /// both sides: the offence knows its menu has shrunk, and the defence knows it can
    /// stop honouring the run. It says the menu *shrank*, not that it is down to one
    /// item — a caller that never runs from here is one a defence can play the pass
    /// against for nothing.
    ///
    /// A passing down is a passing down whenever it happens. The endgame qualifier that
    /// used to hang off the first clause switched the read off inside the last five
    /// minutes, so third and fifteen with four minutes left classified as an ordinary
    /// down.
    public var isMustPass: Bool {
        if downAndDistance.isPassingDown { return true }
        if time.isTwoMinute && score.isTrailing { return true }
        return time == .twoMinuteGame && score == .tied && field != .ownDeep
    }

    /// The offence wants the clock to run, and the defence wants it stopped —
    /// the mirror image of a two-minute drill, and just as situational. Read off
    /// the same value as `isDesperation`, from the other bench.
    public var isClockBurn: Bool {
        time.isEndgame && score.isLeading
    }

    /// A drive that has to end in points now.
    public var isDesperation: Bool {
        guard time == .twoMinuteGame || time == .twoMinuteFirstHalf else { return false }
        return score.isTrailing
    }

    /// Fourth down where going for it is a live option rather than a stunt.
    ///
    /// A *description*, not a recommendation: the decision itself is a
    /// win-probability calculation the coach makes, and a conservative one will
    /// punt from here anyway.
    public var isFourthDownTerritory: Bool {
        guard downAndDistance.isLastDown else { return false }
        if downAndDistance == .fourthShort && field != .ownDeep { return true }
        return score.isTrailing && time.isEndgame
    }

    /// Close enough to attempt a kick, roughly.
    public var isFieldGoalRange: Bool {
        field == .goalLine || field == .redZone || field == .opponentTerritory
    }

    /// The situations a defence prepares for specifically, and where a
    /// coordinator's situational rating should bite hardest.
    public var isHighLeverageForDefense: Bool {
        if downAndDistance.isLastDown { return true }
        if downAndDistance == .thirdMedium || downAndDistance == .thirdLong { return true }
        if field == .goalLine || field == .redZone { return true }
        return time.isTwoMinute && score.isOneScoreGame
    }
}
