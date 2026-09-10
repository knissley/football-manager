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

/// How a forward pass ended, as a pass (2025 rulebook, 8-1-3).
///
/// `PlayEnding` cannot say it: a ball caught for a loss ends `.tackled` exactly as a
/// run does, so a completion could only be inferred from the yards, and the harness
/// counted a pass caught for nothing as an incompletion for as long as it did.
public enum PassResult: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case complete = 0
    case incomplete = 1
    case intercepted = 2
}

/// What the play produced.
public struct Outcome: Sendable, Hashable, Codable {

    public var kind: PlayKind
    /// Net yards from the previous line of scrimmage. Negative on a sack or a
    /// loss.
    public var yards: Int16
    public var endedIn: PlayEnding
    /// How the pass ended, on a play that was one — a pass attempt, a two-point pass,
    /// a spike — and `nil` on every other play. A sack and a scramble are dropbacks,
    /// not attempts, and carry nothing here.
    public var passResult: PassResult?
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
    /// Where a kick was fielded, in the kicking team's frame — yards from the receiving
    /// team's goal line, the frame `finalSpot` uses on a kick — and negative inside its
    /// end zone. On a returned kick, where the returner caught it; on a fair catch, a
    /// downed punt or one run out of bounds, where it was dead, which is where it came
    /// to rest. `nil` on a touchback, which nobody fielded, on a blocked kick, and on
    /// every play that is not a kick.
    ///
    /// The one spot a returned kick was missing: with only where the ball came to rest,
    /// the gross of a returned punt, the return and the net could not be told apart.
    /// `PlayRecord.kickDistance`, `returnYards` and `netPuntDistance(rules:)` are the
    /// arithmetic over the three spots.
    public var fieldedAt: Int8?
    /// On a takeaway, the spot where possession was lost, in the offence's frame like
    /// `Situation.ballOn` and every other spot on the record: where the pass was
    /// intercepted, or where the ball came loose. `nil` on every other play.
    ///
    /// It is the basic spot for a foul during a **run** followed by a change of
    /// possession (2025 rulebook, 14-3-5-b), which is the one case `Rules.enforce` reads
    /// it for. On an interception it is a fact about the play and not an enforcement
    /// spot: a foul between the snap and the end of a forward pass thrown from behind the
    /// line is enforced from the previous spot, and the pass ends and a running play
    /// begins at the instant the ball is caught (14-4-5).
    public var possessionLostAt: UInt8?
    /// Seconds taken off the clock, live action and play clock together.
    public var clockRunoff: UInt16
    /// The points this play put on the board, and what kind of score they were.
    ///
    /// Written by the game once the rules have read the outcome, before the record is
    /// appended, so that a scoreboard is the stream summed and never the rules run a
    /// second time. `scoring` says who: a touchdown, field goal or try pays the side
    /// that had the ball, a safety or a defensive touchdown the side that did not. Zero
    /// and `nil` on a play that scored nothing — a resolver has no business writing
    /// either, and the game overwrites whatever it did.
    public var pointsScored: UInt8
    public var scoring: Scoring?

    public init(
        kind: PlayKind,
        yards: Int16,
        endedIn: PlayEnding,
        passResult: PassResult? = nil,
        participants: [Participation] = [],
        penalties: [PenaltyRecord] = [],
        finalSpot: UInt8? = nil,
        fieldedAt: Int8? = nil,
        possessionLostAt: UInt8? = nil,
        clockRunoff: UInt16 = 0,
        pointsScored: UInt8 = 0,
        scoring: Scoring? = nil
    ) {
        self.finalSpot = finalSpot
        self.fieldedAt = fieldedAt
        self.possessionLostAt = possessionLostAt
        self.kind = kind
        self.yards = yards
        self.endedIn = endedIn
        self.passResult = passResult
        self.participants = participants
        self.penalties = penalties
        self.clockRunoff = clockRunoff
        self.pointsScored = pointsScored
        self.scoring = scoring
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

    /// The shape a record written today has. Bumped when the record's layout or the
    /// meaning of a field changes, so that an old event can still be folded by whatever
    /// reads it ([ADR-0009](../../../../docs/adr/0009-event-sourcing-by-default.md)).
    public static let currentSchemaVersion: UInt8 = 1

    /// The index of a slot nobody stood in.
    public static let vacant: UInt8 = 255

    public var game: GameID
    /// Order within the game, starting at zero. Also the label used to split a
    /// per-play random stream, which is why it must be stable.
    public var index: UInt16
    /// Which shape this record was written under; see `currentSchemaVersion`. Declared
    /// here, after the index, where the padding before the situation absorbs it.
    public var schemaVersion: UInt8
    public var situation: Situation
    public var calls: Calls
    public var decisions: [DecisionPoint]
    public var outcome: Outcome
    /// Who was on the field: twenty-two roster indices in slot order.
    ///
    /// Offence in 0 through 10, indexing the possessing team's roster in the game's
    /// roster table, and defence in 11 through 21 indexing the other side's — the same
    /// convention `PlayerSlot` fixes, so on a kickoff the kicking team is the offence.
    /// `vacant` marks a slot nobody stood in, which happens only when a position has run
    /// out of men.
    ///
    /// Presence and credit are kept apart on purpose. Crediting all twenty-two made the
    /// participants three-quarters of a record and answered nothing the credits did not;
    /// what the credits could never answer is who took the snap, and a byte-wide index
    /// answers it for twenty-two bytes a play. A snap count is `snapCounts(rosters:)`.
    public var onField: [UInt8]

    public init(
        game: GameID,
        index: UInt16,
        situation: Situation,
        calls: Calls,
        decisions: [DecisionPoint] = [],
        outcome: Outcome,
        onField: [UInt8] = Array(repeating: PlayRecord.vacant, count: PlayerSlot.count),
        schemaVersion: UInt8 = PlayRecord.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.game = game
        self.index = index
        self.situation = situation
        self.calls = calls
        self.decisions = decisions
        self.outcome = outcome
        self.onField = onField
    }

    /// The player standing in `slot`, resolved through the game's roster table.
    ///
    /// `rosters` holds the two teams of the game; the offensive slots read the
    /// possessing team's and the defensive slots the other's. `nil` for a vacant slot,
    /// for `PlayerSlot.none`, and for a table that does not hold this play's teams.
    public func player(at slot: PlayerSlot, rosters: [TeamID: [PlayerID]]) -> PlayerID? {
        guard !slot.isNone, Int(slot.rawValue) < onField.count else { return nil }
        let index = onField[Int(slot.rawValue)]
        guard index != Self.vacant else { return nil }
        let team: TeamID?
        if slot.isOffense {
            team = situation.possession
        } else {
            // Two keys, one of them the possessing team, so which comes first when the
            // keys are walked cannot change the answer.
            team = rosters.keys.first { $0 != situation.possession }
        }
        guard let team, let roster = rosters[team], Int(index) < roster.count else { return nil }
        return roster[Int(index)]
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

    /// Whether a forward pass was caught by the passing team, however far it went.
    public var isCompletion: Bool {
        outcome.passResult == .complete
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

extension Sequence where Element == PlayRecord {

    /// How many of these plays each man was on the field for.
    ///
    /// The snap count is a query over presence, not over credit: a lineman who blocked
    /// nobody the record thought worth naming still took the snap.
    public func snapCounts(rosters: [TeamID: [PlayerID]]) -> [PlayerID: Int] {
        var counts: [PlayerID: Int] = [:]
        for play in self {
            for index in 0..<PlayerSlot.count {
                if let player = play.player(at: PlayerSlot(index), rosters: rosters) {
                    counts[player, default: 0] += 1
                }
            }
        }
        return counts
    }
}
