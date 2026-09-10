/// What a kick measured, and what happened before the snap — queries over the record,
/// stored nowhere.
///
/// A kick has three spots: where it was kicked from (`Situation.ballOn`), where it was
/// fielded (`Outcome.fieldedAt`) and where the ball came to rest (`Outcome.finalSpot`),
/// all in the kicking team's frame. Gross, return and net are arithmetic over them, and a
/// touchback — fielded nowhere — is measured to the goal line and netted to the touchback
/// spot, which is how the league scores one.
extension PlayRecord {

    private var isKick: Bool { outcome.kind == .punt || outcome.kind == .kickoff }

    /// How far the kick travelled: from the line to where it was fielded, to the goal
    /// line on a touchback. `nil` on a blocked kick and on anything that is not a kick.
    public var kickDistance: Int? {
        guard isKick, outcome.endedIn != .blocked else { return nil }
        guard let fielded = outcome.fieldedAt else {
            return outcome.endedIn == .touchback ? Int(situation.ballOn) : nil
        }
        return Int(situation.ballOn) - Int(fielded)
    }

    /// How far the kick was run back: from where it was fielded to where the ball came to
    /// rest, and zero on a kick that was fielded and not returned — a fair catch, a downed
    /// punt, a kick run out of bounds, a kick the kickers fell on. `nil` when nobody
    /// fielded it, and on anything that is not a kick.
    public var returnYards: Int? {
        guard isKick, let fielded = outcome.fieldedAt else { return nil }
        switch outcome.endedIn {
        case .tackled, .touchdown, .outOfBounds, .fumbleLost:
            guard let resting = outcome.finalSpot else { return 0 }
            return max(0, Int(resting) - Int(fielded))
        default:
            return 0
        }
    }

    /// The punt's net: the gross less the return, or the line to `rules`' punt touchback
    /// spot on a touchback. `nil` on anything that is not a punt, and on a blocked one.
    public func netPuntDistance(rules: Rules) -> Int? {
        guard outcome.kind == .punt, outcome.endedIn != .blocked else { return nil }
        if outcome.endedIn == .touchback {
            return Int(situation.ballOn) - Int(rules.puntTouchbackOwnYard)
        }
        guard let gross = kickDistance, let back = returnYards else { return nil }
        return gross - back
    }

    /// Whether this kick ended in the kicking team's touchdown: the ball carried to the
    /// receiving team's goal line, which is zero in the kicking team's frame. A kickoff
    /// or punt the returner fumbled and the kicking team carried in, which any player of
    /// either team may do with a fumble (2025 rulebook, 8-7-3 Item 1).
    public var isKickingTeamTouchdown: Bool {
        outcome.isKickingTeamTouchdown
    }

    /// The charged timeouts taken before this snap, by the side in possession at it and
    /// by the other.
    public var timeoutsBeforeTheSnap: (offense: Int, defense: Int) {
        var offense = 0
        var defense = 0
        for decision in decisions {
            guard let byOffense = decision.timeoutByOffense else { continue }
            if byOffense { offense += 1 } else { defense += 1 }
        }
        return (offense, defense)
    }

    /// Whether the two-minute warning was taken before this snap.
    public var hasTwoMinuteWarningBeforeTheSnap: Bool {
        decisions.contains(where: \.isTwoMinuteWarning)
    }
}

extension Outcome {

    /// See `PlayRecord.isKickingTeamTouchdown`.
    public var isKickingTeamTouchdown: Bool {
        (kind == .kickoff || kind == .punt) && endedIn == .touchdown && finalSpot == 0
    }
}
