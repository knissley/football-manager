// The harness's derivations over the play stream, gathered in one place.
//
// Everything downstream of the engine is a *query* over the typed records it emits
// (ADR-0007), and the harness is downstream. Every function here reads what the record
// says; none of them recomputes a fact the record already carries. That distinction is
// not a style preference — the two disagree, and the recomputation is the one that is
// wrong:
//
//   - `yards >= distance` is not a first down. Goal-to-go is measured to the goal line
//     rather than to a marker, and a play that ends in a takeaway is not a new set of
//     downs for the side that lost the ball. `PlayRecord.gainedFirstDown` knows both.
//   - `yards > 0` is not a catch, and `.receiver` is not the catcher. A receiver who ran
//     a route *and* was thrown to is upgraded to `.target` (`PlayRole.outranks`), so
//     crediting `.receiver` credits every man on the play except the one who caught it.
//   - A snap is presence, not credit. `PlayRecord.onField` names the twenty-two men who
//     took it; the participants name only those who did something worth recording.
//
// These stay in the harness. `FMAnalysis` owns the real ones at M2, and a query written
// twice is better than a package the harness reaches into before it exists.

import FMCore

enum StreamQueries {

    // MARK: - Down and distance

    /// How many of these plays won the offence a new set of downs, as the record says.
    ///
    /// `PlayRecord.gainedFirstDown` is the reading: it knows that goal-to-go is measured
    /// to the goal line rather than to a marker, and that a takeaway is not a first down
    /// for the side that lost the ball. Neither of those follows from the yardage, and the
    /// row was counting both.
    ///
    /// Two guards sit in front of it, because it answers "did this play reach the line to
    /// gain" and the row asks "did the offence earn a first down". It returns `true` for
    /// **any** play that ended in a touchdown, before it looks at the kind of play or at
    /// who scored — so a kickoff returned for a score, a two-point try and a pick six all
    /// read as first downs through it. The kind guard drops the kicks and the try; the
    /// scoring guard drops the plays the defence finished.
    static func firstDownsEarned(in plays: [PlayRecord]) -> Int {
        plays.reduce(0) { count, play in
            guard play.outcome.kind.isScrimmagePlay else { return count }
            switch play.outcome.scoring {
            case .defensiveTouchdown, .safety: return count
            default: return count + (play.gainedFirstDown ? 1 : 0)
            }
        }
    }

    /// Designed runs, and the calls they were chosen from, in one bucket.
    struct CallSplit: Equatable {
        var runs = 0
        var calls = 0
    }

    /// The run/pass split by `DownAndDistanceClass`, from what was **called** rather than
    /// from what happened to the ball: a sack and a scramble are the pass they were called
    /// as, which is the question a run share asks of a coordinator.
    ///
    /// A kneel and a spike are in neither half — both are clock plays rather than a choice
    /// about the sport — and so is every play that is not a scrimmage down. First down is
    /// one class and goal-to-go is its own, so neither is split by distance and neither
    /// appears here.
    static func runShare(in plays: [PlayRecord]) -> [DownAndDistanceClass: CallSplit] {
        var split: [DownAndDistanceClass: CallSplit] = [:]
        for play in plays {
            let concept = play.calls.offense.concept
            guard concept.isRun || concept.isPass else { continue }
            let bucket = DownAndDistanceClass(play.situation)
            guard bucket != .firstDown, bucket != .goalToGo else { continue }
            split[bucket, default: CallSplit()].calls += 1
            if concept.isRun { split[bucket, default: CallSplit()].runs += 1 }
        }
        return split
    }

    // MARK: - Receiving

    /// Catches by the man who made them: the participant in the `.target` role on a play
    /// the record calls a completion.
    static func catches(in plays: [PlayRecord]) -> [PlayerID: Int] {
        var credited: [PlayerID: Int] = [:]
        for play in plays where play.outcome.kind.isPassAttempt && play.isCompletion {
            for participant in play.outcome.participants where participant.role == .target {
                credited[participant.player, default: 0] += 1
            }
        }
        return credited
    }

    // MARK: - Where a play ended

    /// Plays that ended with the ball dead in the field of play or out of bounds, and how
    /// many of those were out of bounds.
    ///
    /// A score, an incompletion and a takeaway are in neither count: none of them is a
    /// play the ball carrier could have taken to the sideline instead.
    static func endedOnTheSideline(in plays: [PlayRecord]) -> (outOfBounds: Int, ballDead: Int) {
        var out = 0
        var dead = 0
        for play in plays {
            switch play.outcome.endedIn {
            case .outOfBounds:
                out += 1
                dead += 1
            case .tackled:
                dead += 1
            default:
                break
            }
        }
        return (out, dead)
    }

    // MARK: - Punts

    /// How many of these kicks reached the end zone untouched (2025 rulebook, 11-6-2-c).
    static func touchbacks(in kicks: [PlayRecord]) -> (touchbacks: Int, kicks: Int) {
        (kicks.reduce(0) { $0 + ($1.outcome.endedIn == .touchback ? 1 : 0) }, kicks.count)
    }

    // MARK: - Pressure

    /// Dropbacks the record marks as pressured, and how many of those ended in a sack.
    ///
    /// Numerator and denominator come off the same plays on purpose: a sack on a dropback
    /// nobody pressured is a coverage sack and belongs to neither.
    static func pressure(in plays: [PlayRecord]) -> (pressured: Int, sacks: Int) {
        var pressured = 0
        var sacks = 0
        for play in plays where play.decisions.contains(where: { $0.kind == .pressureAllowed }) {
            pressured += 1
            if play.outcome.kind == .sack { sacks += 1 }
        }
        return (pressured, sacks)
    }

    // MARK: - The try

    /// Two-point tries by how they were called. The rule allows a pass *or* a run
    /// (2025 rulebook, 11-3-1) and the two are different plays, so they are counted
    /// separately rather than as a share of each other; a try called as neither is in
    /// neither count.
    static func twoPointTries(in plays: [PlayRecord]) -> (run: Int, pass: Int) {
        var run = 0
        var pass = 0
        for play in plays where play.outcome.kind == .twoPointConversion {
            switch play.calls.offense.concept {
            case .twoPointRun: run += 1
            case .twoPointPass: pass += 1
            default: break
            }
        }
        return (run, pass)
    }

    // MARK: - Snaps

    /// Player-snaps by the roster position group of each man on the field.
    ///
    /// Read off `PlayRecord.onField` through the game's roster table, so it counts the
    /// twenty-two men who took the snap rather than the handful the play credited. The
    /// credits alone could never produce this: a lineman is named on three snaps in five
    /// and a safety on a sixth of run plays.
    ///
    /// `group` resolves a man's position group; a man it cannot resolve is in no count.
    static func snapsByPositionGroup(
        in games: [(plays: [PlayRecord], rosters: [TeamID: [PlayerID]])],
        group: (PlayerID) -> PositionGroup?
    ) -> [PositionGroup: Int] {
        var counts: [PositionGroup: Int] = [:]
        for game in games {
            for play in game.plays {
                for index in 0..<PlayerSlot.count {
                    guard let player = play.player(at: PlayerSlot(index), rosters: game.rosters),
                        let position = group(player)
                    else { continue }
                    counts[position, default: 0] += 1
                }
            }
        }
        return counts
    }
}
