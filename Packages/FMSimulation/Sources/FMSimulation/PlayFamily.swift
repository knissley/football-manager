import FMCore

/// The kind of play called, at the coarsest useful grain.
///
/// A stand-in for the play format, which is M6 work. A real `PlayDesign` carries
/// formation, routes and per-player assignments; until that exists, a family is enough
/// for a caller to make a decision and a resolver to act on it.
///
/// This is deliberately *not* in `FMCore`. It is scaffolding that goes away when the
/// play format lands, and putting it in the domain layer would make it permanent by
/// accident.
public enum PlayFamily: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case insideRun = 0
    case outsideRun = 1
    /// Three-step timing. Beats pressure, does not beat a defence sitting on the sticks.
    case quickPass = 2
    case mediumPass = 3
    case deepPass = 4
    case screen = 5
    /// Sells the run first. Devastating against a defence that bit, useless against one
    /// that did not.
    case playAction = 6
    case punt = 7
    case fieldGoal = 8
    case kneel = 9
    case spike = 10
    case kickoff = 11
    case extraPoint = 12
    case twoPointConversion = 13

    public var isRun: Bool { self == .insideRun || self == .outsideRun }

    public var isPass: Bool {
        switch self {
        case .quickPass, .mediumPass, .deepPass, .screen, .playAction, .twoPointConversion:
            return true
        default:
            return false
        }
    }

    /// Plays the offence chooses from on a normal down.
    public static let scrimmage: [PlayFamily] = [
        .insideRun, .outsideRun, .quickPass, .mediumPass, .deepPass, .screen, .playAction,
    ]

    public var kind: PlayKind {
        switch self {
        case .insideRun, .outsideRun: return .rush
        case .quickPass, .mediumPass, .deepPass, .screen, .playAction: return .pass
        case .punt: return .punt
        case .fieldGoal: return .fieldGoal
        case .kneel: return .kneel
        case .spike: return .spike
        case .kickoff: return .kickoff
        case .extraPoint: return .extraPoint
        case .twoPointConversion: return .twoPointConversion
        }
    }
}

/// A playbook with one entry per family.
///
/// `OffensiveCall` references a `PlayDesignID` into a playbook that does not exist yet.
/// This is that playbook, at the smallest size that lets the rest of the system be
/// built and tested — one design per family, with stable identifiers so a recorded play
/// still resolves after a reload.
///
/// It is replaced wholesale by the authored concept library at M6.
public enum CrudePlaybook {

    /// Identifiers start above zero so the sentinel stays available.
    public static func design(for family: PlayFamily) -> PlayDesignID {
        PlayDesignID(UInt64(family.rawValue) + 1)
    }

    public static func family(of design: PlayDesignID) -> PlayFamily? {
        guard design.rawValue >= 1 else { return nil }
        return PlayFamily(rawValue: UInt8(design.rawValue - 1))
    }

    public static func call(
        _ family: PlayFamily, tempo: Tempo = .normal, usedMotion: Bool = false
    ) -> OffensiveCall {
        OffensiveCall(design: design(for: family), tempo: tempo, usedMotion: usedMotion)
    }
}
