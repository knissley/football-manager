/// The kind of play called, at the coarsest useful grain — and the one fact about the
/// call a record keeps by value.
///
/// A `PlayDesign` is the authored artifact: formation, routes, assignments, in a playbook
/// across seasons, editable in the play designer at M6. A concept is what the design
/// *is*, and it is stored on every `OffensiveCall` beside the design's identifier
/// ([ADR-0010](../../../../docs/adr/0010-plays-designs-and-calls.md), amended) — so that a
/// record still says what was called after the playbook that held the design has been
/// edited, replaced, or has yet to exist. Until M6 the identifier is `nil` and the concept
/// is the whole call; a caller decides on it and a resolver acts on it.
///
/// Seventeen cases, because the crude engine resolves seventeen kinds of snap. A play format
/// with routes in it does not retire these: a concept is what a tendency table, a box
/// score and a gameplan rule key off, and none of them wants a route tree. The crude read
/// order over the five pass families lives beside the resolver in `FMSimulation`
/// (`ReadProgression`) for the same reason, and not here.
public enum PlayConcept: UInt8, CaseIterable, Sendable, Hashable, Codable {
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
    /// A try thrown from the two. The rule allows a pass *or* a run (11-3-1), and the two
    /// are different plays with different personnel on both sides, so they are different
    /// concepts rather than one concept the resolver reinterprets.
    case twoPointPass = 13
    /// A kick deliberately kept short so the kicking team can fight for it. Its own
    /// concept because it is a different play, not a kickoff with a flag on it: different
    /// personnel, a different decision, and a different distribution of outcomes.
    case onsideKick = 14
    /// The other half of 11-3-1: a try carried in from the two.
    case twoPointRun = 15
    /// A kickoff struck to carry through the end zone, conceding the receiving team's 35
    /// (2025 rulebook, 6-1-5) rather than letting anybody return it.
    ///
    /// Its own concept for the same reason the onside kick is one: under the dynamic
    /// kickoff these are two different plays with two different aiming points, and which
    /// one the coordinator called is a fact about the call rather than a description of
    /// what happened to the ball. `kickoff` is the other — aimed at the landing zone,
    /// meant to be returned.
    case deepKickoff = 16

    public var isRun: Bool {
        self == .insideRun || self == .outsideRun || self == .twoPointRun
    }

    public var isPass: Bool {
        switch self {
        case .quickPass, .mediumPass, .deepPass, .screen, .playAction, .twoPointPass:
            return true
        default:
            return false
        }
    }

    /// Concepts the offence chooses from on a normal down.
    public static let scrimmage: [PlayConcept] = [
        .insideRun, .outsideRun, .quickPass, .mediumPass, .deepPass, .screen, .playAction,
    ]

    /// What kind of play a snap of this concept produces when it is not wiped out by a
    /// flag before the snap. A pass concept is a dropback, and a dropback may end as a
    /// sack or a scramble rather than a pass — `PlayKind.isDropback` is the grouping. A
    /// resolver that returns any other kind for it is lying in the way a fabricated
    /// causal chain would, and the contract tests say so.
    public var kind: PlayKind {
        switch self {
        case .insideRun, .outsideRun: return .rush
        case .quickPass, .mediumPass, .deepPass, .screen, .playAction: return .pass
        case .punt: return .punt
        case .fieldGoal: return .fieldGoal
        case .kneel: return .kneel
        case .spike: return .spike
        case .kickoff, .onsideKick, .deepKickoff: return .kickoff
        case .extraPoint: return .extraPoint
        case .twoPointPass, .twoPointRun: return .twoPointConversion
        }
    }
}
