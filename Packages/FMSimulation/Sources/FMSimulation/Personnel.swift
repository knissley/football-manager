import FMCore
import FMRandom

/// Who is on the field, by slot.
///
/// Slots 0–10 are the offence and 11–21 the defence, which is the convention
/// `PlayerSlot` and `Participation` already depend on: the team a player was on follows
/// from his slot rather than being stored on every credit.
public struct Personnel: Sendable {

    public private(set) var slots: [PlayerID?]
    public private(set) var positions: [Position?]

    public init() {
        slots = Array(repeating: nil, count: PlayerSlot.count)
        positions = Array(repeating: nil, count: PlayerSlot.count)
    }

    public subscript(slot: PlayerSlot) -> PlayerID? {
        guard !slot.isNone, Int(slot.rawValue) < slots.count else { return nil }
        return slots[Int(slot.rawValue)]
    }

    public func position(at slot: PlayerSlot) -> Position? {
        guard !slot.isNone, Int(slot.rawValue) < positions.count else { return nil }
        return positions[Int(slot.rawValue)]
    }

    mutating func place(_ player: PlayerID, position: Position, at slot: Int) {
        slots[slot] = player
        positions[slot] = position
    }

    /// Slots that were actually filled, offence first.
    public var occupied: [PlayerSlot] {
        (0..<PlayerSlot.count).compactMap { slots[$0] == nil ? nil : PlayerSlot($0) }
    }
}

/// The slot each position occupies in the crude engine's personnel.
///
/// Eleven and eleven, in a shape close to modern base personnel: three receivers and a
/// tight end against nickel. The spatial engine will place bodies by formation; this is
/// the smallest arrangement that lets a matchup have two named sides.
enum SlotLayout {

    static let offense: [(Position, Int)] = [
        (.quarterback, 0), (.runningBack, 1),
        (.wideReceiver, 2), (.wideReceiver, 3), (.wideReceiver, 4),
        (.tightEnd, 5),
        (.leftTackle, 6), (.leftGuard, 7), (.center, 8), (.rightGuard, 9), (.rightTackle, 10),
    ]

    static let defense: [(Position, Int)] = [
        (.edge, 11), (.edge, 12), (.defensiveTackle, 13), (.defensiveTackle, 14),
        (.linebacker, 15), (.linebacker, 16),
        (.cornerback, 17), (.cornerback, 18), (.cornerback, 19),
        (.safety, 20), (.safety, 21),
    ]

    static let blockers: [PlayerSlot] = [
        PlayerSlot(6), PlayerSlot(7), PlayerSlot(8), PlayerSlot(9), PlayerSlot(10),
    ]
    static let rushers: [PlayerSlot] = [
        PlayerSlot(11), PlayerSlot(12), PlayerSlot(13), PlayerSlot(14),
    ]
    static let receivers: [PlayerSlot] = [
        PlayerSlot(2), PlayerSlot(3), PlayerSlot(4), PlayerSlot(5), PlayerSlot(1),
    ]
    static let coverage: [PlayerSlot] = [
        PlayerSlot(17), PlayerSlot(18), PlayerSlot(19), PlayerSlot(20), PlayerSlot(21),
        PlayerSlot(15), PlayerSlot(16),
    ]
    /// The kicking unit, for the snaps the offence's eleven do not take.
    ///
    /// Rosters have carried a kicker, a punter and a long snapper since world generation
    /// existed, and none of them had ever been on the field: the kicking code read
    /// `.kickAccuracy` and `.puntPower` off slot 0 and got the *quarterback's*. So a
    /// team's kicker was irrelevant to whether it made kicks, and no specialist could
    /// take a snap, be credited, or get hurt.
    ///
    /// Slot 0 is the snap's principal — the quarterback on a play from scrimmage, the
    /// specialist on a kick — which keeps one eleven-slot arrangement rather than a
    /// second parallel one. The spatial engine places bodies by formation and this
    /// arrangement goes away with it.
    static let fieldGoalUnit: [(Position, Int)] = [
        (.kicker, 0), (.longSnapper, 8),
        (.leftTackle, 6), (.leftGuard, 7), (.rightGuard, 9), (.rightTackle, 10),
        (.tightEnd, 5), (.runningBack, 1),
    ]

    static let puntUnit: [(Position, Int)] = [
        (.punter, 0), (.longSnapper, 8),
        (.leftTackle, 6), (.leftGuard, 7), (.rightGuard, 9), (.rightTackle, 10),
        (.tightEnd, 5), (.runningBack, 1),
    ]

    static let kickoffUnit: [(Position, Int)] = [
        (.kicker, 0),
        (.linebacker, 1), (.linebacker, 2), (.safety, 3), (.safety, 4),
        (.cornerback, 5), (.cornerback, 6), (.tightEnd, 7),
    ]

    /// The eleven facing a kick. Cover men and backs rather than a front seven.
    static let returnUnit: [(Position, Int)] = [
        (.linebacker, 11), (.linebacker, 12), (.edge, 13), (.edge, 14),
        (.safety, 15), (.safety, 16),
        (.cornerback, 17), (.cornerback, 18), (.cornerback, 19),
        (.runningBack, 20), (.wideReceiver, 21),
    ]

    /// Who has an angle on the ball carrier, and how likely each is to be the one who
    /// gets there.
    ///
    /// This was `coverage.prefix(3)` for every kind of play — the three cornerbacks — so
    /// a run up the middle was tackled by a corner and a linebacker never made a tackle
    /// all season. It is a weighted draw rather than a queue because a fixed order gives
    /// the first man in the list nine tackles in ten: pursuit depends on where the ball
    /// actually went, which a crude engine cannot see, so the spread stands in for it.
    static let insideRunPursuit: [(PlayerSlot, Double)] = [
        (PlayerSlot(15), 4), (PlayerSlot(16), 4),
        (PlayerSlot(13), 3), (PlayerSlot(14), 3),
        (PlayerSlot(11), 2), (PlayerSlot(12), 2),
        (PlayerSlot(20), 1), (PlayerSlot(21), 1),
    ]

    /// Outside, the edge sets it, the second level runs to it, and a safety is the last
    /// man before the sideline.
    static let outsideRunPursuit: [(PlayerSlot, Double)] = [
        (PlayerSlot(11), 3), (PlayerSlot(12), 3),
        (PlayerSlot(15), 3), (PlayerSlot(16), 3),
        (PlayerSlot(20), 2), (PlayerSlot(21), 2),
        (PlayerSlot(17), 1), (PlayerSlot(18), 1),
    ]

    /// A scramble is a run the front is late to, because they were rushing the passer.
    static let scramblePursuit: [(PlayerSlot, Double)] = [
        (PlayerSlot(15), 3), (PlayerSlot(16), 3),
        (PlayerSlot(20), 2), (PlayerSlot(21), 2),
        (PlayerSlot(11), 1), (PlayerSlot(12), 1),
    ]

    /// After a catch, the help behind whoever was covering him. The covering man himself
    /// is added at the call site, weighted heavily — he is right there.
    static let catchPursuit: [(PlayerSlot, Double)] = [
        (PlayerSlot(20), 2), (PlayerSlot(21), 2),
        (PlayerSlot(15), 1), (PlayerSlot(16), 1),
        (PlayerSlot(17), 1), (PlayerSlot(18), 1), (PlayerSlot(19), 1),
    ]

    static let quarterback = PlayerSlot(0)
    static let back = PlayerSlot(1)
    /// Slot 0 again, named for what sits there on a kick. Reading `quarterback` in the
    /// kicking game is how the specialists went missing in the first place.
    static let specialist = PlayerSlot(0)
}

extension Personnel {

    /// Fill the field from both rotations.
    ///
    /// Who plays is drawn against each man's snap share, so a starter is usually out
    /// there and his backup sometimes is. Over a season that is what makes snap counts
    /// and backup statistics real rather than a starter taking everything.
    static func onField(
        _ context: PlayContext, family: PlayFamily, random: inout SplittableRandom
    ) -> Personnel {
        var personnel = Personnel()
        fill(
            &personnel, layout: family.offenseLayout, from: context.offenseRotation,
            random: &random)
        fill(
            &personnel, layout: family.defenseLayout, from: context.defenseRotation,
            random: &random)
        return personnel
    }

    private static func fill(
        _ personnel: inout Personnel,
        layout: [(Position, Int)],
        from rotation: [DepthChart.Rotation],
        random: inout SplittableRandom
    ) {
        var used: Set<PlayerID> = []

        for (position, slot) in layout {
            let candidates = rotation.filter {
                $0.position == position && !used.contains($0.player)
            }
            guard !candidates.isEmpty else { continue }

            // Weighted by snap share, so the man who plays most usually plays. A
            // depleted group falls through to whoever is left, which is the point of
            // next-man-up.
            let weights = candidates.map { max(0.01, $0.snapShare) }
            let index = random.weightedIndex(weights) ?? 0
            let chosen = candidates[index]
            used.insert(chosen.player)
            personnel.place(chosen.player, position: position, at: slot)
        }
    }
}
