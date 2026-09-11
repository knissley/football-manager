import FMCore
import FMRandom

/// Who got hurt, and for how long.
///
/// Drawn from the play's **participants** rather than inside the resolver, because an
/// injury is about who was involved in contact and not about how the contact was
/// modelled. That keeps it working unchanged when the spatial resolver replaces the
/// crude one ([ADR-0012](../../../../docs/adr/0012-play-resolver-seam.md)) — at which
/// point real contact severity can feed it instead of the play kind.
///
/// M1 models **availability only**: he is out, and for how many games. Severity,
/// rehabilitation, reaggravation and long-term effects are M3's, and building them
/// against a resolver that is being deleted would mean tuning them twice.
enum Injuries {

    /// Roughly how often a snap hurts somebody badly enough to cost him time.
    ///
    /// Set against the calibration target of 40–90 player-games lost per team per season,
    /// which is a couple of injuries a game across both teams once the length of an
    /// absence is folded in.
    static let baseRate = 0.0029

    /// How often a snap ends somebody's afternoon with nobody having touched him.
    ///
    /// Roughly a fifth of injuries in the sport are non-contact, and they are the ones
    /// that end seasons. A model that only hurts people who were tackled cannot produce
    /// a receiver planting on an incompletion, which is one of the more common ways a
    /// season actually ends.
    static let nonContactRate = 0.00055

    /// Anyone hurt on this play.
    ///
    /// At most one, because two players going down on the same snap is rare enough that
    /// modelling it would cost more than it is worth, and a crowd of them would read as
    /// a bug rather than a bad afternoon.
    static func drawn(
        on play: PlayRecord, context: PlayContext, random: inout SplittableRandom
    ) -> InjuryEvent? {
        guard somebodyCouldHaveBeenHurt(on: play) else { return nil }
        if let nonContact = nonContactInjury(on: play, context: context, random: &random) {
            return nonContact
        }
        return contactInjury(on: play, context: context, random: &random)
    }

    /// Whether this down is one anybody could have been hurt on.
    ///
    /// Both draws below read the record's *credits* as if they were physical facts, and
    /// on three kinds of down the two come apart.
    ///
    /// A knee and a spike are snaps taken to stop the game rather than to play it. One
    /// man is credited on each — the quarterback, down as a rusher on a knee because he
    /// carried the ball and not because he ran, and as a passer on a spike. Neither
    /// record carries a tackler, a blocker or a pass rusher, so there is nobody on it to
    /// have hit him, and neither carries anybody who changed direction at speed: a man
    /// standing on the ball is in a smaller phone booth than the guard who does not tear
    /// a knee in `nonContactInjury`. A down that was never snapped is not a down at all —
    /// a dead-ball foul replays it, and nobody has moved.
    ///
    /// A kick is not in the list. A field goal and a try are scrimmage downs with a rush
    /// to block, and they keep the small exposure `contactInjury` gives them.
    ///
    /// The cost of getting this wrong is not who limps off. After the two-minute warning
    /// an injury costs the injured player's team a charged team timeout (2025 rulebook,
    /// 4-5-4-a) and the game clock then waits for the next snap (4-3-2) — so a
    /// quarterback hurt taking a knee hands the clock back to the side that has just
    /// kneeled the half away, and a caller counting a clock that is no longer running
    /// plays the down after all.
    static func somebodyCouldHaveBeenHurt(on play: PlayRecord) -> Bool {
        switch play.outcome.kind {
        case .kneel, .spike, .penaltyOnly: return false
        default: return true
        }
    }

    /// A knee or an achilles going on a cut, a plant or a landing.
    ///
    /// Drawn from who was **moving hard**, not from who was hit — so it is uncorrelated
    /// with how the play went, and it can happen on a snap where nobody was touched at
    /// all. That independence is the point: it is what makes it a different event rather
    /// than a heavier tackle.
    static func nonContactInjury(
        on play: PlayRecord, context: PlayContext, random: inout SplittableRandom
    ) -> InjuryEvent? {
        // Everyone who changed direction at speed. A lineman in a phone booth does not
        // tear an ACL the way a receiver coming out of a break does.
        let exposed = play.outcome.participants.filter { participation in
            switch participation.role {
            case .rusher, .receiver, .target, .coverage, .passRusher: return true
            case .passer: return play.outcome.kind == .scramble
            default: return false
            }
        }
        guard !exposed.isEmpty else { return nil }

        let chance = nonContactRate * Double(exposed.count)
        guard random.nextBool(probability: min(0.02, chance)) else { return nil }
        guard let index = random.weightedIndex(exposed.map { _ in 1.0 }) else { return nil }
        let hurt = exposed[index]

        // These skew long. An ACL or an achilles is most of a season, and a hamstring is
        // still weeks — so there is no walk-it-off branch here at all.
        let resilience = Double(context.players[hurt.player]?.hidden.durability ?? 60)
        let roll = random.nextDouble() - (resilience - 60) * 0.004
        let gamesOut: UInt8
        switch roll {
        case ..<0.30: gamesOut = UInt8(1 + random.next(upperBound: 2))
        case ..<0.62: gamesOut = UInt8(3 + random.next(upperBound: 4))
        default: gamesOut = UInt8(9 + random.next(upperBound: 11))
        }

        return InjuryEvent(
            player: hurt.player, occurredOn: play.id, cause: .nonContact, gamesOut: gamesOut)
    }

    /// Somebody was hit.
    static func contactInjury(
        on play: PlayRecord, context: PlayContext, random: inout SplittableRandom
    ) -> InjuryEvent? {
        // Contact is what hurts people. A play nobody was tackled on rarely does.
        let exposure: Double
        switch play.outcome.kind {
        case .rush, .scramble: exposure = 1.35
        case .sack: exposure = 1.5
        case .pass: exposure = play.outcome.endedIn == .incomplete ? 0.5 : 1.0
        case .punt, .kickoff: exposure = 1.2
        // A kick is a scrimmage down with a rush to block, and hurts somebody about as
        // often as you would expect from that: rarely, and not never.
        case .extraPoint, .fieldGoal: exposure = 0.05
        // Not reached through `drawn`, which turns these three away before either draw —
        // nobody was hit on them and nobody ran. They keep the number they had so that a
        // caller reaching past `drawn` gets the same answer it always did, rather than a
        // second exposure nobody can see.
        case .kneel, .spike, .penaltyOnly: exposure = 0.05
        default: exposure = 0.8
        }

        // Everyone credited was doing something; the ball carrier and the men who
        // brought him down were doing the most.
        let candidates = play.outcome.participants.filter { $0.role != .other }
        guard !candidates.isEmpty else { return nil }

        let weights = candidates.map { participation -> Double in
            switch participation.role {
            case .rusher, .receiver, .passer: return 2.2
            case .tackler, .assistTackler: return 1.8
            case .blocker, .passRusher: return 1.2
            default: return 0.7
            }
        }

        let chance = baseRate * exposure * Double(candidates.count) * 0.5
        guard random.nextBool(probability: min(0.05, chance)) else { return nil }

        guard let index = random.weightedIndex(weights) else { return nil }
        let hurt = candidates[index]

        // Durability and injury resistance are what separate a player who misses a
        // quarter from one who misses a month.
        let resilience =
            context.effective(.injuryResistance, for: hurt.player, onOffense: hurt.slot.isOffense)
            + Double(context.players[hurt.player]?.hidden.durability ?? 60)
        let sturdiness = (resilience / 2 - 60) * 0.025

        // Most knocks are brief. The tail is what takes a season apart.
        //
        // Subtracted, not added: a higher roll means a longer absence, so a durable
        // player has to be pushed *down* the table. Adding it gave the sturdiest players
        // the longest injuries and put player-games lost at 127 against a target of 90.
        let roll = random.nextDouble() - sturdiness
        //
        // Weighted from the calibration target rather than by feel: 40–90 player-games
        // lost per team per season, against roughly an injury a game, needs the average
        // absence to land near four. A table that averaged one produced a league where
        // nobody was ever really hurt.
        let gamesOut: UInt8
        switch roll {
        case ..<0.25: gamesOut = 0
        case ..<0.43: gamesOut = 1
        case ..<0.65: gamesOut = UInt8(2 + random.next(upperBound: 2))
        case ..<0.87: gamesOut = UInt8(4 + random.next(upperBound: 4))
        default: gamesOut = UInt8(8 + random.next(upperBound: 10))
        }

        return InjuryEvent(
            player: hurt.player, occurredOn: play.id, cause: .contact, gamesOut: gamesOut)
    }
}
