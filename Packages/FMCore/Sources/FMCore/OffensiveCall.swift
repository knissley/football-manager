/// How fast the offence intends to play, which is a call-level choice rather than a
/// property of the design: the same concept can be run on the ball or with thirty
/// seconds burned off the clock first.
public enum Tempo: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case hurryUp = 0
    case fast = 1
    case normal = 2
    case slow = 3
    case bleedClock = 4
}

/// What the offence chose on this snap.
///
/// A `PlayDesign` is the authored artifact — formation, routes, blocking rules — and
/// lives in a playbook across seasons. This is that design plus the wrapper that makes
/// it a call: what it is, how fast, and whether anybody moved before the snap.
///
/// The counterpart to `DefensiveCall`, and the two are stored together by value in a
/// `PlayRecord` ([ADR-0010](../../../../docs/adr/0010-plays-designs-and-calls.md)), so
/// editing a design in the play designer never rewrites what happened three seasons ago.
///
/// The concept is held by value and the design by reference, and the reference is `nil`
/// until M6 gives it a playbook to point into. For a while the design pointed into a
/// stand-in playbook whose identifiers were the concept's raw value plus one — an
/// identifier space that would have dangled the day a real playbook existed, so the M1
/// stream could not have been read by the M6 engine. A record carries what was called,
/// whatever becomes of the playbook it was called from.
public struct OffensiveCall: Sendable, Hashable, Codable {

    /// What was called, at the coarsest grain the record keeps.
    public var concept: PlayConcept
    public var tempo: Tempo
    public var usedMotion: Bool
    /// The authored design the concept was run from, once one exists to be named.
    /// Declared last because an optional identifier is nine bytes aligned to eight, and
    /// the three single-byte fields pack ahead of it rather than behind.
    public var design: PlayDesignID?

    public init(
        concept: PlayConcept, design: PlayDesignID? = nil, tempo: Tempo = .normal,
        usedMotion: Bool = false
    ) {
        self.concept = concept
        self.design = design
        self.tempo = tempo
        self.usedMotion = usedMotion
    }
}
