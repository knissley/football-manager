/// How many players a team carries at each position, and how many of them start.
///
/// Configuration rather than a constant, so a four-team test league can run a
/// smaller roster and a season can be simulated in a blink
/// ([decision 15](../../../../docs/design-decisions.md)).
public struct RosterShape: Sendable, Hashable, Codable {

    public struct Requirement: Sendable, Hashable, Codable {
        public let position: Position
        /// How many are on the field at once in base personnel.
        public let starters: Int
        /// How many are carried in total.
        public let total: Int

        public init(position: Position, starters: Int, total: Int) {
            precondition(starters >= 0 && total >= starters, "invalid requirement")
            self.position = position
            self.starters = starters
            self.total = total
        }
    }

    public let requirements: [Requirement]

    public init(requirements: [Requirement]) {
        self.requirements = requirements
    }

    public var rosterSize: Int {
        requirements.reduce(0) { $0 + $1.total }
    }

    public var starterCount: Int {
        requirements.reduce(0) { $0 + $1.starters }
    }

    public func requirement(for position: Position) -> Requirement? {
        requirements.first { $0.position == position }
    }

    /// The 53-man roster the league runs by default.
    ///
    /// Eleven starters a side: one back, three receivers and a tight end behind
    /// five linemen; two edges, two interior, two linebackers, three corners and
    /// two safeties, which is nickel — the package defences actually spend most
    /// of their snaps in.
    public static let standard = RosterShape(requirements: [
        .init(position: .quarterback, starters: 1, total: 3),
        .init(position: .runningBack, starters: 1, total: 3),
        .init(position: .fullback, starters: 0, total: 1),
        .init(position: .wideReceiver, starters: 3, total: 6),
        .init(position: .tightEnd, starters: 1, total: 3),
        .init(position: .leftTackle, starters: 1, total: 2),
        .init(position: .leftGuard, starters: 1, total: 2),
        .init(position: .center, starters: 1, total: 2),
        .init(position: .rightGuard, starters: 1, total: 2),
        .init(position: .rightTackle, starters: 1, total: 1),
        .init(position: .edge, starters: 2, total: 5),
        .init(position: .defensiveTackle, starters: 2, total: 5),
        .init(position: .linebacker, starters: 2, total: 5),
        .init(position: .cornerback, starters: 3, total: 6),
        .init(position: .safety, starters: 2, total: 4),
        .init(position: .kicker, starters: 1, total: 1),
        .init(position: .punter, starters: 1, total: 1),
        .init(position: .longSnapper, starters: 1, total: 1),
    ])

    /// A minimal roster for tests: one player at every position that has to be
    /// on the field, and nothing else.
    public static let minimal = RosterShape(requirements: [
        .init(position: .quarterback, starters: 1, total: 1),
        .init(position: .runningBack, starters: 1, total: 1),
        .init(position: .wideReceiver, starters: 3, total: 3),
        .init(position: .tightEnd, starters: 1, total: 1),
        .init(position: .leftTackle, starters: 1, total: 1),
        .init(position: .leftGuard, starters: 1, total: 1),
        .init(position: .center, starters: 1, total: 1),
        .init(position: .rightGuard, starters: 1, total: 1),
        .init(position: .rightTackle, starters: 1, total: 1),
        .init(position: .edge, starters: 2, total: 2),
        .init(position: .defensiveTackle, starters: 2, total: 2),
        .init(position: .linebacker, starters: 2, total: 2),
        .init(position: .cornerback, starters: 3, total: 3),
        .init(position: .safety, starters: 2, total: 2),
        .init(position: .kicker, starters: 1, total: 1),
        .init(position: .punter, starters: 1, total: 1),
        .init(position: .longSnapper, starters: 1, total: 1),
    ])
}
