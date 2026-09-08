/// A change to the parts of a team that a player can rewrite.
///
/// Identity is event-sourced because a replay has to show the world as it was
/// ([ADR-0009](../../../../docs/adr/0009-event-sourcing-by-default.md)). Watching a
/// game from four seasons ago should show the name on the front of the jersey *then*,
/// not the one a rebrand gave the team since — the same argument that put a player's
/// gear on a stream.
///
/// `founded` is the origin, and it is an event like any other rather than a field
/// stored somewhere outside the log. That is what makes the fold total: every later
/// state is reachable by replaying from the beginning, so a projection is provably
/// faithful instead of merely plausible.
public enum TeamIdentityChange: Sendable, Hashable, Codable {
    case founded(identity: TeamIdentity, stadium: Stadium)
    case renamed(nickname: String)
    /// A move changes the city and the building together, which is why it is one
    /// event and not two — a fold that could interleave them could place a team in a
    /// stadium it never played in.
    case relocated(city: String, stadium: Stadium)
    case rebranded(TeamColors)
    case reabbreviated(String)
}

/// One identity change, stamped with the season it takes effect.
///
/// A season rather than a full world time, because teams do not change their name in
/// week nine — a rebrand or a move lands at an offseason boundary. If a mid-season
/// identity change ever becomes a real case this needs a finer stamp, and that should
/// be a deliberate change rather than an accident.
public struct TeamIdentityEvent: Sendable, Hashable, Codable {

    public var team: TeamID
    public var effectiveFrom: SeasonID
    public var change: TeamIdentityChange

    public init(team: TeamID, effectiveFrom: SeasonID, change: TeamIdentityChange) {
        self.team = team
        self.effectiveFrom = effectiveFrom
        self.change = change
    }
}

/// A team's editable state at one moment: what it was called and where it played.
///
/// The unit a replay or a record book asks for. `Team` caches the current one; this
/// is what you get by folding the stream to any other point.
public struct TeamSnapshot: Sendable, Hashable, Codable {

    public var identity: TeamIdentity
    public var stadium: Stadium

    public init(identity: TeamIdentity, stadium: Stadium) {
        self.identity = identity
        self.stadium = stadium
    }

    public mutating func apply(_ change: TeamIdentityChange) {
        switch change {
        case .founded(let identity, let stadium):
            self.identity = identity
            self.stadium = stadium
        case .renamed(let nickname):
            identity.nickname = nickname
        case .relocated(let city, let stadium):
            identity.city = city
            self.stadium = stadium
        case .rebranded(let colors):
            identity.colors = colors
        case .reabbreviated(let abbreviation):
            identity.abbreviation = abbreviation
        }
    }

    /// The team's state as it stood in `season`, folded from the founding event.
    ///
    /// Returns `nil` for a stream with no founding event — a team that was never
    /// founded has no state to report, and inventing a blank one would let the
    /// mistake travel.
    ///
    /// Events are applied in the order given. This deliberately does not sort them: a
    /// stream that needs sorting to fold correctly is a stream with a bug in it, and
    /// sorting here would hide it.
    public static func projected(
        at season: SeasonID, from events: some Sequence<TeamIdentityEvent>
    ) -> TeamSnapshot? {
        var snapshot: TeamSnapshot?
        for event in events where event.effectiveFrom.rawValue <= season.rawValue {
            if snapshot == nil {
                guard case .founded(let identity, let stadium) = event.change else { continue }
                snapshot = TeamSnapshot(identity: identity, stadium: stadium)
            } else {
                snapshot?.apply(event.change)
            }
        }
        return snapshot
    }
}

extension Team {

    /// The cached current state, in the shape a projection returns.
    public var snapshot: TeamSnapshot {
        TeamSnapshot(identity: identity, stadium: stadium)
    }

    /// The team as it was, for a replay or a record book.
    ///
    /// Everything outside the snapshot — the identifier, the market, the scheme —
    /// carries over unchanged, because those are not what a rebrand touches.
    public func projected(
        at season: SeasonID, from events: some Sequence<TeamIdentityEvent>
    ) -> Team? {
        guard let snapshot = TeamSnapshot.projected(at: season, from: events) else { return nil }
        var team = self
        team.identity = snapshot.identity
        team.stadium = snapshot.stadium
        return team
    }
}
