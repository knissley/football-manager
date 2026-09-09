import FMCore
import FMRandom

/// What the afternoon is like.
///
/// `WeatherState` and `Climate` have existed since the world was first generated, and
/// nothing had ever produced one: every game the engine had ever simulated was played at
/// seventy degrees in still air, including the calibration runs the whole engine was
/// tuned against. So home-field advantage and weather were mechanisms with no evidence
/// behind them — not unimplemented, but never once measured.
///
/// Deterministic from the stadium, the week and the seed, because a game replayed is a
/// game played in the same conditions.
public enum WeatherGenerator {

    /// Where the season sits, from opening weekend to the last week of the regular
    /// season, in eighteenths.
    private static func lateness(_ week: Int) -> Int {
        max(0, min(18, week - 1))
    }

    /// September and January temperatures for each climate, in Fahrenheit. The season
    /// runs between them.
    private static func range(_ climate: Climate) -> (opening: Int, closing: Int) {
        switch climate {
        case .temperate: return (74, 34)
        case .cold: return (69, 21)
        case .hot: return (88, 58)
        case .arid: return (86, 48)
        case .coastal: return (71, 44)
        case .mountain: return (74, 30)
        }
    }

    /// How much air moves, and how often it really blows.
    private static func windBase(_ climate: Climate) -> (typical: Int, gusty: Double) {
        switch climate {
        case .coastal: return (11, 0.26)
        case .mountain: return (9, 0.18)
        case .arid: return (8, 0.14)
        case .temperate: return (7, 0.12)
        case .cold: return (8, 0.16)
        case .hot: return (6, 0.08)
        }
    }

    /// How often the weather turns up at all.
    private static func wetness(_ climate: Climate) -> Double {
        switch climate {
        case .coastal: return 0.30
        case .temperate: return 0.20
        case .cold: return 0.24
        case .mountain: return 0.18
        case .hot: return 0.14
        case .arid: return 0.05
        }
    }

    /// The conditions for one game.
    ///
    /// - Parameters:
    ///   - stadium: the home team's ground. A roof settles it regardless of the city.
    ///   - week: 1 through 18. Later is colder, wetter and likelier to be snow.
    ///   - random: the stream to draw the day from.
    /// - Returns: the conditions this game is played in.
    public static func forGame(
        stadium: Stadium, week: Int, using random: inout SplittableRandom
    ) -> WeatherState {
        guard stadium.weatherIsDecidedByClimate else {
            // Seventy degrees and still, which is the point of a roof.
            return WeatherState(
                temperature: 70, windSpeed: 0, precipitation: .none, isIndoors: true)
        }

        let season = lateness(week)
        let bounds = range(stadium.climate)
        // Straight-line through the season, then the day itself, which is the larger part
        // of the variation: a warm week in December is a real thing.
        let seasonal = bounds.opening + (bounds.closing - bounds.opening) * season / 18
        let swing = Int(random.next(upperBound: 25)) - 12
        // Thinner air up high runs colder whatever the map says.
        let altitude = Int(stadium.altitudeFeet) / 1_000
        let temperature = seasonal + swing - altitude

        let wind = windBase(stadium.climate)
        var windSpeed = wind.typical + Int(random.next(upperBound: 7)) - 3
        if random.nextBool(probability: wind.gusty) {
            windSpeed += 8 + Int(random.next(upperBound: 12))
        }

        var precipitation = Precipitation.none
        // Wetter as the season turns, and cold enough late on for it to be snow.
        let chance = wetness(stadium.climate) + Double(season) * 0.004
        if random.nextBool(probability: chance) {
            if temperature <= 33 {
                precipitation = .snow
            } else {
                precipitation = random.nextBool(probability: 0.28) ? .heavyRain : .rain
            }
        }

        return WeatherState(
            temperature: Int16(max(-10, min(105, temperature))),
            windSpeed: UInt8(max(0, min(45, windSpeed))),
            precipitation: precipitation,
            isIndoors: false)
    }
}
