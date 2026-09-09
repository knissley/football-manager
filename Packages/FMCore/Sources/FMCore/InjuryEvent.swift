/// A player going down.
///
/// One of the streams [ADR-0009](../../../../docs/adr/0009-event-sourcing-by-default.md)
/// implies: an injury is a fact about a moment, and *was he available in week nine* has
/// to be answerable years later.
///
/// The injury is located by the play it happened on rather than by a stamped date. A
/// `PlayRef` names the game, the game names the week, and nothing has to agree with
/// anything — the same derived-identity rule that governs plays
/// ([ADR-0011](../../../../docs/adr/0011-derived-identity-for-regenerable-streams.md)).
public struct InjuryEvent: Sendable, Hashable, Codable {

    public let player: PlayerID
    /// The snap he was hurt on.
    public let occurredOn: PlayRef
    /// Games he will miss. Zero means he returned to this one.
    public let gamesOut: UInt8

    public init(player: PlayerID, occurredOn: PlayRef, gamesOut: UInt8) {
        self.player = player
        self.occurredOn = occurredOn
        self.gamesOut = gamesOut
    }

    /// Whether he is out of the game he was hurt in.
    ///
    /// A knock he plays through still belongs in the stream: *he was hurt in the third
    /// quarter and stayed in* is a real thing to be able to say, and it is the same
    /// event as one that ends a season, only smaller.
    public var leavesTheGame: Bool { gamesOut > 0 }
}
