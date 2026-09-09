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

    /// Anyone hurt on this play.
    ///
    /// At most one, because two players going down on the same snap is rare enough that
    /// modelling it would cost more than it is worth, and a crowd of them would read as
    /// a bug rather than a bad afternoon.
    static func drawn(
        on play: PlayRecord, context: PlayContext, random: inout SplittableRandom
    ) -> InjuryEvent? {
        // Contact is what hurts people. A play nobody was tackled on rarely does.
        let exposure: Double
        switch play.outcome.kind {
        case .rush, .scramble: exposure = 1.35
        case .sack: exposure = 1.5
        case .pass: exposure = play.outcome.endedIn == .incomplete ? 0.5 : 1.0
        case .punt, .kickoff: exposure = 1.2
        case .kneel, .spike, .penaltyOnly, .extraPoint, .fieldGoal: exposure = 0.05
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

        return InjuryEvent(player: hurt.player, occurredOn: play.id, gamesOut: gamesOut)
    }
}
