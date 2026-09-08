/// A position on the field.
///
/// `EDGE`, `LB` and `S` are deliberately single cases. Whether an edge rusher
/// fits a three- or four-man front, whether a safety plays deep or in the box,
/// and whether a linebacker is a Mike or a Will are **scheme fit** questions
/// resolved by ratings and traits — not separate positions. Keeping the list
/// short puts the interesting variation where it can actually be simulated.
public enum Position: UInt8, CaseIterable, Sendable, Hashable, Codable {

    // Offense
    case quarterback
    case runningBack
    case fullback
    case wideReceiver
    case tightEnd
    case leftTackle
    case leftGuard
    case center
    case rightGuard
    case rightTackle

    // Defense
    case edge
    case defensiveTackle
    case linebacker
    case cornerback
    case safety

    // Special teams
    case kicker
    case punter
    case longSnapper

    public var side: Side {
        switch self {
        case .quarterback, .runningBack, .fullback, .wideReceiver, .tightEnd,
            .leftTackle, .leftGuard, .center, .rightGuard, .rightTackle:
            return .offense
        case .edge, .defensiveTackle, .linebacker, .cornerback, .safety:
            return .defense
        case .kicker, .punter, .longSnapper:
            return .specialTeams
        }
    }

    /// The grouping used for roster construction, depth charts and scouting.
    public var group: PositionGroup {
        switch self {
        case .quarterback: return .quarterback
        case .runningBack, .fullback: return .backfield
        case .wideReceiver: return .receiver
        case .tightEnd: return .tightEnd
        case .leftTackle, .leftGuard, .center, .rightGuard, .rightTackle: return .offensiveLine
        case .edge: return .edge
        case .defensiveTackle: return .defensiveInterior
        case .linebacker: return .linebacker
        case .cornerback: return .cornerback
        case .safety: return .safety
        case .kicker, .punter, .longSnapper: return .specialist
        }
    }

    /// Exactly five offensive linemen are on the field for every scrimmage play.
    public var isOffensiveLine: Bool {
        group == .offensiveLine
    }

    /// Positions that can be targeted by a forward pass.
    public var isEligibleReceiver: Bool {
        switch self {
        case .runningBack, .fullback, .wideReceiver, .tightEnd: return true
        default: return false
        }
    }

    /// Roughly how much the market pays for the position, before considering
    /// the player. Quarterback dwarfs everything else; the premium positions
    /// then separate from the rest. The AI's contract and draft valuations must
    /// reflect this or the trade and free agency markets read as nonsense.
    ///
    /// A starting point for calibration, not a settled table.
    public var positionalValue: Double {
        switch self {
        case .quarterback: return 1.00
        case .edge: return 0.62
        case .leftTackle: return 0.58
        case .cornerback: return 0.56
        case .wideReceiver: return 0.54
        case .defensiveTackle: return 0.48
        case .rightTackle: return 0.44
        case .safety: return 0.36
        case .linebacker: return 0.34
        case .tightEnd: return 0.34
        case .leftGuard, .rightGuard: return 0.30
        case .center: return 0.30
        case .runningBack: return 0.26
        case .fullback: return 0.12
        case .kicker: return 0.10
        case .punter: return 0.08
        case .longSnapper: return 0.05
        }
    }
}

public enum Side: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case offense
    case defense
    case specialTeams
}

public enum PositionGroup: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case quarterback
    case backfield
    case receiver
    case tightEnd
    case offensiveLine
    case edge
    case defensiveInterior
    case linebacker
    case cornerback
    case safety
    case specialist

    public var positions: [Position] {
        Position.allCases.filter { $0.group == self }
    }

    /// The age at which the group's players are typically at their best.
    ///
    /// Real curves differ sharply by position — a back is finished around the
    /// age a quarterback is entering his prime — and flattening that would make
    /// roster building far less interesting than it should be.
    public var peakAge: Int {
        switch self {
        case .quarterback: return 30
        case .backfield: return 26
        case .receiver: return 27
        case .tightEnd: return 27
        case .offensiveLine: return 29
        case .edge: return 27
        case .defensiveInterior: return 28
        case .linebacker: return 27
        case .cornerback: return 26
        case .safety: return 27
        case .specialist: return 31
        }
    }

    /// Overall points lost per season past the peak, before individual
    /// durability and work ethic are applied.
    public var declinePerSeason: Double {
        switch self {
        case .backfield: return 2.4
        case .cornerback: return 2.0
        case .receiver, .edge: return 1.6
        case .linebacker, .safety, .tightEnd: return 1.5
        case .defensiveInterior: return 1.3
        case .offensiveLine: return 1.1
        case .quarterback: return 1.0
        case .specialist: return 0.7
        }
    }
}
