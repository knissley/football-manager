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
    static let quarterback = PlayerSlot(0)
    static let back = PlayerSlot(1)
}

extension Personnel {

    /// Fill the field from both rotations.
    ///
    /// Who plays is drawn against each man's snap share, so a starter is usually out
    /// there and his backup sometimes is. Over a season that is what makes snap counts
    /// and backup statistics real rather than a starter taking everything.
    static func onField(
        _ context: PlayContext, random: inout SplittableRandom
    ) -> Personnel {
        var personnel = Personnel()
        fill(&personnel, layout: SlotLayout.offense, from: context.offenseRotation, random: &random)
        fill(&personnel, layout: SlotLayout.defense, from: context.defenseRotation, random: &random)
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
