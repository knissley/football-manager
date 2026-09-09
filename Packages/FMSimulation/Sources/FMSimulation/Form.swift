import FMCore
import FMRandom

/// How a player is playing today, in rating points.
///
/// A rating is a central tendency, not a constant. Real players have good days and bad
/// ones for reasons no model captures — sleep, a knock nobody reported, confidence,
/// familiarity with the man across from them. Acknowledging that is not authoring
/// outcomes; pretending a 90 plays exactly 90 every Sunday is the less honest choice.
///
/// It matters mechanically, not just texturally. Independent per-play randomness
/// **concentrates**: a game is a sum of a hundred draws, and sums of independent draws
/// cluster tightly around their mean. That is why a first pass produced a maximum of
/// three passing touchdowns in four hundred team-games and could never have produced
/// four — narrower than pure chance, and with the record permanently out of reach.
///
/// Form is what correlates a player's plays *within* a game. It is the difference
/// between a distribution that has tails and one that does not, and therefore between a
/// league where records can fall and one where they cannot.
///
/// Deterministic: drawn once per game from the game's seed and the player's identifier,
/// so a replay shows the same day.
public enum Form {

    /// Ordinary day-to-day variation, in rating points.
    static let spread = 4.0

    /// How often somebody has a day well outside their normal range, in either
    /// direction. Rare, and the reason a generational player in the right situation can
    /// chase a number nobody should reach.
    static let outlierChance = 0.06

    /// Every player's day for one game.
    ///
    /// Built once per game rather than per play, because that is what makes it a *day*
    /// rather than more noise. Drawn per player from a stream split on his identifier,
    /// so adding a player to a roster cannot shift anybody else's form.
    public static func table(
        for players: some Sequence<PlayerID>, game: GameID, seed: UInt64
    ) -> [PlayerID: Double] {
        let root = SplittableRandom(seed: seed)
        var table: [PlayerID: Double] = [:]

        for player in players {
            var random = root.split(game.rawValue, player.rawValue)
            var offset = random.nextGaussian() * spread
            if random.nextBool(probability: outlierChance) {
                let magnitude = 4.0 + Double(random.next(upperBound: 6))
                offset += random.nextBool(probability: 0.5) ? magnitude : -magnitude
            }
            table[player] = offset
        }
        return table
    }
}
