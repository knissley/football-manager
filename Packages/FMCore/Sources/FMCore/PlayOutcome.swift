/// Who chose a play.
public enum PlayCaller: Sendable, Hashable, Codable {
    case coordinator(PersonnelID)
    case player
    /// No call was made — a kneel, a spike, or an untimed administrative play.
    case automatic
}

/// The two calls that met on this snap, and who made each.
///
/// Both are held **by value** rather than as references into a playbook
/// ([ADR-0010](../../../../docs/adr/0010-plays-designs-and-calls.md)). A design can be
/// edited in the play designer years later; what was called on a given snap cannot
/// change, and a replay has to show what actually happened.
///
/// Recording the caller is what lets the gameplan layer measure plan against execution,
/// and what makes a replay of a game you called reproducible.
public struct Calls: Sendable, Hashable, Codable {

    public var offense: OffensiveCall
    public var defense: DefensiveCall
    public var offensiveCaller: PlayCaller
    public var defensiveCaller: PlayCaller

    public init(
        offense: OffensiveCall,
        defense: DefensiveCall,
        offensiveCaller: PlayCaller,
        defensiveCaller: PlayCaller
    ) {
        self.offense = offense
        self.defense = defense
        self.offensiveCaller = offensiveCaller
        self.defensiveCaller = defensiveCaller
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
    /// A defender taking on a block against the run — the run's counterpart to
    /// `.passRusher`, and the assignment a run fit is made of. He is not credited with a
    /// tackle unless he makes one.
    case runDefender = 12
    case other = 11

    /// How specific this role is about what the player actually did.
    ///
    /// A player earns at most one credit per play, so when two apply the more specific
    /// one has to win: a corner who covered a route *and* made the tackle is a tackler,
    /// and a receiver who ran a route *and* was thrown to is a target. Resolving that by
    /// keeping whichever credit happened to be written first is how a sack once ended up
    /// attributable to nobody, and how targets stayed invisible for a while after.
    var specificity: UInt8 {
        switch self {
        case .other: return 0
        case .blocker, .coverage, .passRusher, .runDefender, .receiver: return 1
        case .passer, .rusher, .target, .returner, .kicker: return 2
        case .assistTackler: return 3
        case .tackler: return 4
        }
    }

    /// Whether this credit says more about the play than one already recorded.
    public func outranks(_ other: PlayRole) -> Bool {
        specificity > other.specificity
    }
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

/// Where a foul is walked off from (2025 rulebook, 14-3-4).
///
/// Three families, and the difference between them is the difference between a
/// facemask at the end of a twenty-yard run being worth thirty-five yards and being
/// declined: the engine used to measure every foul from the previous spot, so the
/// contact family offered fifteen yards from the old line against the run's own gain.
public enum EnforcementSpot: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// The spot the ball was last put in play from: every foul before the snap
    /// (14-4-1), the offence's fouls at or behind the line (14-3-6, exception 1), and
    /// the passing game until the catch — holding, illegal contact, interference by the
    /// offence (8-6-1).
    case previousSpot = 0
    /// Where the foul happened: interference by the defence (8-6-1-b), and a block by
    /// the team in possession beyond the line, which is behind the basic spot of a run
    /// that went on past it (14-3-6).
    case spotOfFoul = 1
    /// Where the ball will next be put in play — the dead-ball spot, with the play's
    /// gain counting: the contact fouls on a run (14-3-5-a, 14-3-6), a personal foul
    /// on a completed pass (8-6-1-d), and conduct after the whistle (12-3-1).
    case succeedingSpot = 2
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

    /// Thrown after the whistle, so the play *stands* and the yardage is walked off from
    /// where it ended.
    ///
    /// Neither a pre-snap foul (which cancels the snap) nor a live-ball one (which the
    /// other team may decline in favour of the play). There is nothing to decline: the
    /// play already counted and this is on top of it.
    public var isDeadBall: Bool {
        self == .unsportsmanlikeConduct || self == .taunting
    }

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

    /// Whether this is a personal foul (2025 rulebook, Rule 12 Section 2) or an
    /// unsportsmanlike conduct foul (12-3-1).
    ///
    /// The book asks this in one place that matters here: 14-2-3 carries a personal or
    /// unsportsmanlike foul to the succeeding free kick when the opponent scores a field
    /// goal or a safety, and leaves every other foul to be declined.
    ///
    /// **The article decides this, not the section heading it is printed under**, and
    /// 12-2-12 is where the two answers come apart: it prints two fouls with a penalty
    /// each, and each penalty says which it is in parentheses. Roughing the kicker is
    /// fifteen and is marked a personal foul; running into the kicker is five and is
    /// marked as not one. So a foul in the middle of Rule 12 Section 2 is not carried
    /// anywhere, and reading the heading alone puts a free kick five yards down the field
    /// on a play the offended team would have declined.
    ///
    /// By article: chop block 12-2-5, blindside block 12-2-7, unnecessary roughness
    /// 12-2-8, impermissible use of the helmet 12-2-10, roughing the passer 12-2-11,
    /// roughing the kicker 12-2-12 Item 1, tripping 12-2-14, facemask 12-2-15,
    /// horse-collar 12-2-16, blocking below the waist 12-2-4, and unsportsmanlike conduct
    /// and taunting 12-3-1. Holding, the use of hands and a block in the back are Rule 12
    /// Section 1, and pass interference is Rule 8, so none of them is one of these; nor
    /// is running into the kicker, 12-2-12 Item 2.
    public var isPersonalOrUnsportsmanlike: Bool {
        switch self {
        case .chopBlock, .illegalBlindsideBlock, .unnecessaryRoughness, .illegalUseOfHelmet,
            .roughingThePasser, .roughingTheKicker, .tripping,
            .facemask, .horseCollarTackle, .lowBlock, .unsportsmanlikeConduct, .taunting:
            return true
        default:
            return false
        }
    }

    /// Where this foul is walked off from. See `EnforcementSpot` for the three families
    /// and the articles behind them.
    public var enforcement: EnforcementSpot {
        switch self {
        case .defensivePassInterference, .illegalBlockInTheBack, .illegalBlindsideBlock,
            .lowBlock:
            return .spotOfFoul
        case .facemask, .unnecessaryRoughness, .horseCollarTackle, .illegalUseOfHelmet,
            .roughingThePasser, .unsportsmanlikeConduct, .taunting:
            return .succeedingSpot
        default:
            return .previousSpot
        }
    }

    /// Enforced from the spot of the foul rather than the previous line of scrimmage,
    /// which is what makes deep interference the highest-variance call in the sport.
    /// Interference is no longer the only one: a block in the back beyond the line is
    /// walked off from where it happened too.
    public var isSpotFoul: Bool {
        enforcement == .spotOfFoul
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
    /// Yards walked off. `foul.yards` as the resolver reports it; once enforced, the
    /// distance actually assessed, which half the distance to the goal can shorten and
    /// a spot foul measures.
    public var yards: UInt8
    public var wasAccepted: Bool
    public var awardedFirstDown: Bool
    /// Where a spot foul is walked off from, in the frame of the team that snapped —
    /// the same frame as `Situation.ballOn` and `Outcome.finalSpot` — with zero meaning
    /// the defence's end zone. The resolver measured it, so the resolver reports it;
    /// it is required for a `.spotOfFoul` foul and read for no other, because the
    /// previous spot is the situation's and the dead-ball spot follows from the play.
    public var enforcementSpot: UInt8?

    public init(
        foul: Foul,
        offender: PlayerSlot,
        offendingTeam: TeamID,
        yards: UInt8,
        wasAccepted: Bool,
        awardedFirstDown: Bool = false,
        enforcementSpot: UInt8? = nil
    ) {
        self.foul = foul
        self.offender = offender
        self.offendingTeam = offendingTeam
        self.yards = yards
        self.wasAccepted = wasAccepted
        self.awardedFirstDown = awardedFirstDown
        self.enforcementSpot = enforcementSpot
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
    /// Where the ball came to rest, measured from the **snapping team's** opponent
    /// goal line — the same frame as `Situation.ballOn`.
    ///
    /// `yards` is the offence's net gain, which says nothing useful once the defence
    /// has the ball: an interception returned thirty yards is not "minus thirty" for
    /// anybody. So a play that changes possession reports the spot outright, and a
    /// normal play leaves this `nil` and lets it follow from the yardage.
    public var finalSpot: UInt8?
    /// Seconds taken off the clock, live action and play clock together.
    public var clockRunoff: UInt16
    public var pointsScored: UInt8

    public init(
        kind: PlayKind,
        yards: Int16,
        endedIn: PlayEnding,
        participants: [Participation] = [],
        penalties: [PenaltyRecord] = [],
        finalSpot: UInt8? = nil,
        clockRunoff: UInt16 = 0,
        pointsScored: UInt8 = 0
    ) {
        self.finalSpot = finalSpot
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

/// A reference to one play, from outside the stream.
///
/// A highlight, a news item or a bookmark holds one of these. It is `(game, index)` and
/// nothing more, which is what makes it survive the retention tier: a play in a game
/// that was never stored resolves by replaying that game and indexing into it
/// ([ADR-0011](../../../../docs/adr/0011-derived-identity-for-regenerable-streams.md)).
///
/// Deliberately a struct rather than the two fields packed into a `UInt64`. Packing
/// would be flatter and two bytes smaller, at the cost of baking a ceiling on games per
/// career into the event contract — the worst place in the codebase to hide an
/// assumption.
public struct PlayRef: Sendable, Hashable, Codable, Comparable {

    public let game: GameID
    /// Order within the game. Plays are ordered within a game and not across games:
    /// a week's games are concurrent, so there is no global play order to appeal to.
    public let index: UInt16

    public init(game: GameID, index: UInt16) {
        self.game = game
        self.index = index
    }

    public static func < (lhs: PlayRef, rhs: PlayRef) -> Bool {
        (lhs.game.rawValue, lhs.index) < (rhs.game.rawValue, rhs.index)
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

    public var game: GameID
    /// Order within the game, starting at zero. Also the label used to split a
    /// per-play random stream, which is why it must be stable.
    public var index: UInt16
    public var situation: Situation
    public var calls: Calls
    public var decisions: [DecisionPoint]
    public var outcome: Outcome

    public init(
        game: GameID,
        index: UInt16,
        situation: Situation,
        calls: Calls,
        decisions: [DecisionPoint] = [],
        outcome: Outcome
    ) {
        self.game = game
        self.index = index
        self.situation = situation
        self.calls = calls
        self.decisions = decisions
        self.outcome = outcome
    }

    /// How anything outside the stream refers to this play.
    ///
    /// Derived rather than stored, and there is no allocator
    /// ([ADR-0011](../../../../docs/adr/0011-derived-identity-for-regenerable-streams.md)):
    /// most games are never retained, and a play in one of them has to be addressable
    /// after the game is regenerated from its seed.
    public var id: PlayRef { PlayRef(game: game, index: index) }

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
