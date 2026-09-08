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
/// it a call: how fast, and whether anybody moved before the snap.
///
/// The counterpart to `DefensiveCall`, and the two are stored together by value in a
/// `PlayRecord` ([ADR-0010](../../../../docs/adr/0010-plays-designs-and-calls.md)), so
/// editing a design in the play designer never rewrites what happened three seasons ago.
///
/// Thin today because the play format itself is M6 work; `design` points into a playbook
/// that does not exist yet. What lands there belongs behind the identifier, not here —
/// this type holds only what varies snap to snap.
public struct OffensiveCall: Sendable, Hashable, Codable {

    public var design: PlayDesignID
    public var tempo: Tempo
    public var usedMotion: Bool

    public init(design: PlayDesignID, tempo: Tempo = .normal, usedMotion: Bool = false) {
        self.design = design
        self.tempo = tempo
        self.usedMotion = usedMotion
    }
}
