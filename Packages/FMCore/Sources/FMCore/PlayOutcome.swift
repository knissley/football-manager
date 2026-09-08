/// Who chose a play.
public enum PlayCaller: Sendable, Hashable, Codable {
    case coordinator(PersonnelID)
    case player
    /// No call was made — a kneel, a spike, or an untimed administrative play.
    case automatic
}

public enum Tempo: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case hurryUp = 0
    case fast = 1
    case normal = 2
    case slow = 3
    case bleedClock = 4
}

/// What each side chose, and who chose it.
///
/// Recording the caller is what lets the gameplan layer measure plan against
/// execution, and what makes a replay of a game you called reproducible.
public struct Calls: Sendable, Hashable, Codable {

    public var offensivePlay: PlayID
    public var defensiveCall: DefensiveCallID
    public var offensiveCaller: PlayCaller
    public var defensiveCaller: PlayCaller
    public var tempo: Tempo
    public var usedMotion: Bool

    public init(
        offensivePlay: PlayID,
        defensiveCall: DefensiveCallID,
        offensiveCaller: PlayCaller,
        defensiveCaller: PlayCaller,
        tempo: Tempo = .normal,
        usedMotion: Bool = false
    ) {
        self.offensivePlay = offensivePlay
        self.defensiveCall = defensiveCall
        self.offensiveCaller = offensiveCaller
        self.defensiveCaller = defensiveCaller
        self.tempo = tempo
        self.usedMotion = usedMotion
    }
}

public enum PlayKind: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case rush = 0
    case pass = 1
    case sack = 2
    case scramble = 3
    case punt = 4
    case fieldGoal = 5
    case extraPoint = 6
    case twoPointConversion = 7
    case kickoff = 8
    case kneel = 9
    case spike = 10
    /// The snap produced nothing but a flag — a pre-snap foul, or a play wiped
    /// out entirely.
    case penaltyOnly = 11

    /// A sack is not a pass attempt but it is a dropback, and sack yardage
    /// counts against passing yards. Getting these denominators wrong makes
    /// calibration lie.
    public var isDropback: Bool {
        self == .pass || self == .sack || self == .scramble
    }

    public var isPassAttempt: Bool {
        self == .pass
    }

    public var isScrimmagePlay: Bool {
        switch self {
        case .rush, .pass, .sack, .scramble, .kneel, .spike: return true
        default: return false
        }
    }
}

public enum PlayEnding: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case tackled = 0
    case outOfBounds = 1
    case touchdown = 2
    case incomplete = 3
    case intercepted = 4
    case fumbleLost = 5
    case fumbleRecovered = 6
    case touchback = 7
    case safety = 8
    case fieldGoalGood = 9
    case fieldGoalMissed = 10
    case downed = 11
    case fairCatch = 12
    case blocked = 13
    case penaltyEnforced = 14

    public var isTurnover: Bool {
        self == .intercepted || self == .fumbleLost
    }

    public var stopsClock: Bool {
        switch self {
        case .incomplete, .touchdown, .outOfBounds, .safety, .touchback,
            .fieldGoalGood, .fieldGoalMissed, .intercepted, .fumbleLost:
            return true
        default:
            return false
        }
    }
}

public enum PlayRole: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case passer = 0
    case rusher = 1
    case target = 2
    case receiver = 3
    case blocker = 4
    case passRusher = 5
    case coverage = 6
    case tackler = 7
    case assistTackler = 8
    case kicker = 9
    case returner = 10
    case other = 11
}

/// A player's involvement in a play, and the slot the decision points reference.
///
/// **Only players who did something are credited.** A play has twenty-two
/// people on the field, but most of them contributed nothing worth recording;
/// listing all of them makes participants roughly three-quarters of a play
/// record's size for no analytical gain. The passer, the ball carrier, the
/// target, tacklers, and the blockers and rushers whose matchups actually
/// resolved — those are the record.
///
/// The team is not stored: slots 0...10 are the offence and 11...21 the
/// defence, so it follows from `slot.isOffense` and the situation's possession.
public struct Participation: Sendable, Hashable, Codable {

    public var slot: PlayerSlot
    public var player: PlayerID
    public var position: Position
    public var role: PlayRole

    public init(
        slot: PlayerSlot,
        player: PlayerID,
        position: Position,
        role: PlayRole
    ) {
        self.slot = slot
        self.player = player
        self.position = position
        self.role = role
    }

    /// Which team this player was on, given who had the ball.
    public func team(possessionTeam: TeamID, defendingTeam: TeamID) -> TeamID {
        slot.isOffense ? possessionTeam : defendingTeam
    }
}

public enum Foul: UInt8, CaseIterable, Sendable, Hashable, Codable {

    // Pre-snap, procedural
    case falseStart = 0
    case offside = 1
    case encroachment = 2
    case neutralZoneInfraction = 3
    case delayOfGame = 4
    case illegalFormation = 5
    case illegalMotion = 6
    case illegalShift = 7
    case tooManyMenOnField = 8
    case illegalSubstitution = 9

    // Blocking and the line of scrimmage
    case offensiveHolding = 20
    case illegalUseOfHands = 21
    case illegalBlockInTheBack = 22
    case illegalBlindsideBlock = 23
    case chopBlock = 24
    case tripping = 25
    case ineligibleReceiverDownfield = 26
    case illegalManDownfield = 27

    // Coverage and receiving
    case defensiveHolding = 40
    case defensivePassInterference = 41
    case offensivePassInterference = 42
    case illegalContact = 43

    // Contact
    case roughingThePasser = 60
    case facemask = 61
    case unnecessaryRoughness = 62
    case horseCollarTackle = 63
    case illegalUseOfHelmet = 64
    case lowBlock = 65

    // Kicking
    case roughingTheKicker = 80
    case runningIntoTheKicker = 81
    case illegalTouching = 82

    // Conduct
    case unsportsmanlikeConduct = 90
    case taunting = 91

    /// Called before the snap, so the play never happens and the situation is
    /// simply replayed from a new spot.
    public var isPreSnap: Bool {
        rawValue < 20
    }

    /// Fouls that give the offence a first down automatically when accepted.
    public var carriesAutomaticFirstDown: Bool {
        switch self {
        case .defensiveHolding, .defensivePassInterference, .illegalContact,
            .roughingThePasser, .unnecessaryRoughness, .facemask, .horseCollarTackle,
            .illegalUseOfHelmet, .roughingTheKicker, .lowBlock:
            return true
        default:
            return false
        }
    }

    /// Enforced from the spot of the foul rather than the previous line of
    /// scrimmage, which is what makes deep interference the highest-variance
    /// call in the sport.
    public var isSpotFoul: Bool {
        self == .defensivePassInterference
    }

    /// Standard yardage. Spot fouls are measured instead, and carry zero here.
    public var yards: UInt8 {
        switch self {
        case .falseStart, .offside, .encroachment, .neutralZoneInfraction, .delayOfGame,
            .illegalFormation, .illegalMotion, .illegalShift, .tooManyMenOnField,
            .illegalSubstitution, .defensiveHolding, .illegalContact, .illegalTouching,
            .runningIntoTheKicker, .illegalManDownfield:
            return 5
        case .offensiveHolding, .illegalUseOfHands, .illegalBlockInTheBack, .tripping,
            .ineligibleReceiverDownfield, .offensivePassInterference:
            return 10
        case .illegalBlindsideBlock, .chopBlock, .roughingThePasser, .facemask,
            .unnecessaryRoughness, .horseCollarTackle, .illegalUseOfHelmet, .lowBlock,
            .roughingTheKicker, .unsportsmanlikeConduct, .taunting:
            return 15
        case .defensivePassInterference:
            return 0
        }
    }

    /// Which side commits it, where only one side can.
    public var committedBy: Side? {
        switch self {
        case .falseStart, .delayOfGame, .illegalFormation, .illegalMotion, .illegalShift,
            .offensiveHolding, .illegalBlockInTheBack, .illegalBlindsideBlock, .chopBlock,
            .ineligibleReceiverDownfield, .illegalManDownfield, .offensivePassInterference:
            return .offense
        case .offside, .encroachment, .neutralZoneInfraction, .defensiveHolding,
            .defensivePassInterference, .illegalContact, .roughingThePasser,
            .roughingTheKicker, .runningIntoTheKicker:
            return .defense
        default:
            return nil
        }
    }
}

/// A flag on a play.
///
/// Declined penalties are recorded too. A penalty that was thrown and waved off
/// is part of what happened, and discarding it would make the play log disagree
/// with what a viewer saw.
public struct PenaltyRecord: Sendable, Hashable, Codable {

    public var foul: Foul
    public var offender: PlayerSlot
    public var offendingTeam: TeamID
    /// Yards enforced. Usually `foul.yards`, but a spot foul is measured.
    public var yards: UInt8
    public var wasAccepted: Bool
    public var awardedFirstDown: Bool

    public init(
        foul: Foul,
        offender: PlayerSlot,
        offendingTeam: TeamID,
        yards: UInt8,
        wasAccepted: Bool,
        awardedFirstDown: Bool = false
    ) {
        self.foul = foul
        self.offender = offender
        self.offendingTeam = offendingTeam
        self.yards = yards
        self.wasAccepted = wasAccepted
        self.awardedFirstDown = awardedFirstDown
    }
}

/// What the play produced.
public struct Outcome: Sendable, Hashable, Codable {

    public var kind: PlayKind
    /// Net yards from the previous line of scrimmage. Negative on a sack or a
    /// loss.
    public var yards: Int16
    public var endedIn: PlayEnding
    public var participants: [Participation]
    public var penalties: [PenaltyRecord]
    /// Seconds taken off the clock, live action and play clock together.
    public var clockRunoff: UInt16
    public var pointsScored: UInt8

    public init(
        kind: PlayKind,
        yards: Int16,
        endedIn: PlayEnding,
        participants: [Participation] = [],
        penalties: [PenaltyRecord] = [],
        clockRunoff: UInt16 = 0,
        pointsScored: UInt8 = 0
    ) {
        self.kind = kind
        self.yards = yards
        self.endedIn = endedIn
        self.participants = participants
        self.penalties = penalties
        self.clockRunoff = clockRunoff
        self.pointsScored = pointsScored
    }

    public func participant(at slot: PlayerSlot) -> Participation? {
        participants.first { $0.slot == slot }
    }

    public func participants(inRole role: PlayRole) -> [Participation] {
        participants.filter { $0.role == role }
    }
}

/// One play, as the engine emits it.
///
/// The engine's entire public output. Box scores, grades, tendencies,
/// highlights, news and causal breakdowns are all queries over a stream of
/// these — never accumulated alongside the simulation (ADR-0007).
///
/// Derived values are deliberately absent: win probability, leverage and grades
/// are computed by `FMAnalysis` rather than stored, so improving those models
/// improves history retroactively.
public struct PlayRecord: Sendable, Hashable, Codable, Identifiable {

    public var id: PlayID
    public var game: GameID
    /// Order within the game, starting at zero. Also the label used to split a
    /// per-play random stream, which is why it must be stable.
    public var index: UInt16
    public var situation: Situation
    public var calls: Calls
    public var decisions: [DecisionPoint]
    public var outcome: Outcome

    public init(
        id: PlayID,
        game: GameID,
        index: UInt16,
        situation: Situation,
        calls: Calls,
        decisions: [DecisionPoint] = [],
        outcome: Outcome
    ) {
        self.id = id
        self.game = game
        self.index = index
        self.situation = situation
        self.calls = calls
        self.decisions = decisions
        self.outcome = outcome
    }

    public func decisions(ofKind kind: DecisionKind) -> [DecisionPoint] {
        decisions.filter { $0.kind == kind }
    }

    /// Whether the play gained enough for a new set of downs.
    ///
    /// Goal-to-go is measured to the goal line rather than to a marker, so it
    /// is only a first down if it is a touchdown.
    public var gainedFirstDown: Bool {
        if outcome.endedIn == .touchdown { return true }
        guard outcome.kind.isScrimmagePlay, !outcome.endedIn.isTurnover else { return false }
        guard !situation.isGoalToGo else { return false }
        return outcome.yards >= Int16(situation.distance)
    }
}
