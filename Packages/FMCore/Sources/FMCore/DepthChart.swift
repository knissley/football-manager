/// How a position's snaps are shared down the depth chart.
///
/// The shares are per *position*, not per group, because positions within a group
/// rotate nothing like each other: three running backs split a workload, five offensive
/// line spots each have one man who plays every snap, and a defensive line rotates
/// heavily enough that the fourth man is a real contributor.
///
/// A position's shares sum to roughly **how many of that position are on the field at
/// once** — about 2.7 for cornerback because nickel is the base defence now, 1 for each
/// offensive line spot, 2.2 for linebacker. That is the invariant worth holding: it is
/// what makes a season's snap counts add up to a season.
public enum RotationProfile {

    /// Whether a position shares its snaps at all.
    ///
    /// A share is not the same claim at every position. A defensive line's third man
    /// really does take four snaps in ten, drawn play by play; a left tackle's backup
    /// takes none until the left tackle cannot play. Drawing both the same way put the
    /// second quarterback on the field for one dropback in fifty, mid-drive, with the
    /// starter standing on the sideline for one snap and back for the next.
    public enum Kind: Sendable, Hashable {
        /// One man's job. He takes every snap he is available for, and the man behind him
        /// takes them only while he is not — which is what the ordering already says, so
        /// no draw is made at all.
        case starterOnly
        /// A group that splits the work, drawn against `shares(for:)` on every snap.
        case rotates
    }

    /// How this position's snaps are handed out.
    ///
    /// Starter-only is the quarterback, the five line spots and the three specialists:
    /// positions the sport substitutes at only for injury, ineffectiveness or the end of
    /// a game. Everything else rotates.
    ///
    /// Note what this does *not* change: `shares(for:)` still decides who is in the
    /// rotation at all, so the man behind a starter-only spot keeps a share above zero
    /// and is there to come on. Below the starter the number says he is next up, not how
    /// often he plays.
    public static func kind(for position: Position) -> Kind {
        switch position {
        case .quarterback, .leftTackle, .leftGuard, .center, .rightGuard, .rightTackle,
            .kicker, .punter, .longSnapper:
            return .starterOnly
        case .runningBack, .fullback, .wideReceiver, .tightEnd, .edge, .defensiveTackle,
            .linebacker, .cornerback, .safety:
            return .rotates
        }
    }

    /// Share of snaps for the player at `depth`, where 0 is the starter.
    ///
    /// Zero past the end of the rotation: a fourth tight end does not play on offence,
    /// and pretending otherwise puts statistics on players who never took the field.
    public static func snapShare(_ position: Position, depth: Int) -> Double {
        let shares = shares(for: position)
        guard depth >= 0, depth < shares.count else { return 0 }
        return shares[depth]
    }

    public static func shares(for position: Position) -> [Double] {
        switch position {
        case .quarterback: return [0.98, 0.02]
        // One back carries the load, a second is a real part of the offence, a third
        // exists for a change of pace and for when the first two are hurt.
        case .runningBack: return [0.58, 0.30, 0.12]
        case .fullback: return [0.20, 0.03]
        case .wideReceiver: return [0.92, 0.85, 0.60, 0.16, 0.04]
        case .tightEnd: return [0.78, 0.34, 0.08]
        // A lineman plays every snap or he is a backup. There is no rotation here, and
        // modelling one would put a false story in the box score.
        case .leftTackle, .leftGuard, .center, .rightGuard, .rightTackle:
            return [0.97, 0.03]
        // The heaviest rotation on the field: pass rushers are spent by the fourth
        // quarter and everybody knows it.
        case .edge: return [0.75, 0.62, 0.44, 0.19]
        case .defensiveTackle: return [0.72, 0.65, 0.44, 0.19]
        // About a third base and two thirds nickel, which is what puts the third
        // linebacker on the field a little under half the time.
        case .linebacker: return [0.90, 0.82, 0.48, 0.15]
        case .cornerback: return [0.94, 0.88, 0.60, 0.20]
        case .safety: return [0.92, 0.86, 0.25]
        case .kicker, .punter, .longSnapper: return [1.0]
        }
    }

    /// Roughly how many of this position are on the field at once.
    public static func expectedOnField(_ position: Position) -> Double {
        shares(for: position).reduce(0, +)
    }
}

/// Who plays, and in what order.
///
/// Ordering only — the chart says who is ahead of whom, and `RotationProfile` says what
/// that is worth in snaps. Keeping those apart means a coach reordering his chart does
/// not also have to decide a snap distribution, and the rotation curve stays one table
/// rather than a per-team number nobody can account for.
public struct DepthChart: Sendable, Hashable, Codable {

    /// Ordered best-to-worst, per position. A player may appear at more than one
    /// position if he can play both.
    private var order: [Position: [PlayerID]]

    public init(order: [Position: [PlayerID]] = [:]) {
        self.order = order
    }

    public subscript(position: Position) -> [PlayerID] {
        get { order[position] ?? [] }
        set { order[position] = newValue }
    }

    public var positions: [Position] {
        order.keys.sorted { $0.rawValue < $1.rawValue }
    }

    public func starter(at position: Position) -> PlayerID? {
        order[position]?.first
    }

    /// Where a player sits at a position, or `nil` if he is not on the chart there.
    public func depth(of player: PlayerID, at position: Position) -> Int? {
        order[position]?.firstIndex(of: player)
    }

    public func contains(_ player: PlayerID) -> Bool {
        order.values.contains { $0.contains(player) }
    }
}

extension DepthChart {

    /// One player's expected share of the snaps at a position.
    public struct Rotation: Sendable, Hashable {
        public let player: PlayerID
        public let position: Position
        public let depth: Int
        public let snapShare: Double
    }

    /// Who actually plays this week, in order, with everyone unavailable removed.
    ///
    /// **Next man up.** Removing an injured player does not leave a hole — everyone
    /// behind him moves up a place and inherits the share that comes with it. A starter
    /// going down turning his backup into a starter is the whole shape of the story, and
    /// it falls out of the ordering rather than needing a rule.
    public func rotation(
        at position: Position, unavailable: Set<PlayerID> = []
    ) -> [Rotation] {
        let available = (order[position] ?? []).filter { !unavailable.contains($0) }
        return available.enumerated().compactMap { depth, player in
            let share = RotationProfile.snapShare(position, depth: depth)
            guard share > 0 else { return nil }
            return Rotation(player: player, position: position, depth: depth, snapShare: share)
        }
    }

    /// Everyone who plays, across every position, in a stable order.
    public func rotation(unavailable: Set<PlayerID> = []) -> [Rotation] {
        positions.flatMap { rotation(at: $0, unavailable: unavailable) }
    }

    /// Positions with nobody left to play them.
    ///
    /// A real situation, not a defensive check: injuries do run a position group out of
    /// bodies, and the honest answer is to say so rather than to silently field ten men.
    public func unmannedPositions(unavailable: Set<PlayerID> = []) -> [Position] {
        positions.filter { rotation(at: $0, unavailable: unavailable).isEmpty }
    }
}
