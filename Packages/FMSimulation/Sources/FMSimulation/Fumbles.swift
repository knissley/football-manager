import FMCore
import FMRandom

/// The ball on the ground.
///
/// The crude engine modelled no ball security at all, which cost more than the turnovers
/// themselves: about half the sport's turnovers are fumbles, and a turnover is worth far
/// more than one possession because of where it hands the ball over. With interceptions
/// as the only way to lose it, defences could not create a short field, `hitPower` and
/// `carrying` were ratings nothing read, and a defensive touchdown was arithmetically
/// impossible.
///
/// Kept out of the resolver's play code for the same reason `Penalties` is: it is a fact
/// about a collision between two players, not about how this particular engine models a
/// run, so it survives the resolver being replaced.
enum Fumbles {

    /// How often a hit on a ball carrier knocks it loose.
    ///
    /// Around one touch in fifty-five across the sport, once the aborted snaps and
    /// exchange fumbles this engine does not model are set aside.
    static let onContact = 0.024

    /// A quarterback who never saw it coming is a different proposition, and the strip
    /// sack is the single most valuable defensive play that is not an interception.
    static let onSack = 0.085

    /// The ball is loose, and this is who ends up with it.
    struct Loose {
        /// Whether the defence came up with it.
        var lost: Bool
        /// Yards the recovering defender brought it back, in the offence's frame.
        var returnYards: Int
        /// Who forced it.
        var forcedBy: PlayerSlot
    }

    /// Whether this hit put the ball on the ground, and what happened to it.
    ///
    /// A loose ball is close to a coin flip — the sport recovers about half its own
    /// fumbles, and that randomness is the point rather than a shortcoming. Nothing about
    /// who falls on it is a skill this engine models.
    static func drawn(
        carrier: PlayerSlot, tackler: PlayerSlot, isSack: Bool,
        personnel: Lineup, context: PlayContext, random: inout SplittableRandom
    ) -> Loose? {
        guard personnel[carrier] != nil, personnel[tackler] != nil else { return nil }

        let security = context.effective(.carrying, for: personnel[carrier], onOffense: true)
        let punch = context.effective(.hitPower, for: personnel[tackler], onOffense: false)

        // A wet or frozen ball is the other half of why it comes loose.
        let base = isSack ? onSack : onContact
        let weather = 1.0 + Conditions.handling(context.weather) * 0.22
        let chance = base * weather * (1.0 + (punch - security) * 0.014)
        guard random.nextBool(probability: min(base * 2.5, max(base * 0.25, chance))) else {
            return nil
        }

        // A quarterback stripped from behind is the one everybody scoops, because he is
        // the deepest man on the field and the ball is behind the line.
        let defenceRecovers = random.nextBool(probability: isSack ? 0.56 : 0.50)
        guard defenceRecovers else {
            return Loose(lost: false, returnYards: 0, forcedBy: tackler)
        }

        // Most recoveries are a man falling on it. Occasionally somebody has it in
        // stride, and that is where a fumble returned the distance comes from.
        let scooped = random.nextBool(probability: 0.32)
        let returned = scooped ? Int(random.next(upperBound: 62)) : Int(random.next(upperBound: 4))
        return Loose(lost: true, returnYards: returned, forcedBy: tackler)
    }
}
