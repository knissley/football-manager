import FMCore
import Testing

@testable import FMSimulation

/// The weather belongs to the game, not to the down.
///
/// `Situation.weather` was copied onto every play, about a hundred and fifty times a
/// game, although nothing that reads a situation — the callers, the classification, the
/// rules — ever looked at it: the resolver did, and `PlayContext` already carried the same
/// value with a comment saying facts about the afternoon belong to the game. So the
/// situation is the down and the game's result carries the afternoon once.
@Suite("The weather belongs to the game")
struct GameWeatherTests {

    private static let blizzard = WeatherState(
        temperature: 12, windSpeed: 26, precipitation: .snow, isIndoors: false)

    @Test("A game's result carries the weather it was played in", .tags(.contract))
    func resultCarriesTheWeather() {
        let fine = TestWorld.game(seed: 3, weather: .clear)
        #expect(fine.weather == .clear)
        let snowed = TestWorld.game(seed: 3, weather: Self.blizzard)
        #expect(snowed.weather == Self.blizzard)
    }

    /// The conditions reach the resolver through the context. If the same seed played in
    /// a blizzard produced the same stream as in the sunshine, the weather would be a
    /// field nobody reads.
    @Test("The weather reaches the resolver through the context", .tags(.contract))
    func weatherReachesTheResolver() {
        let fine = TestWorld.game(seed: 3, weather: .clear)
        let snowed = TestWorld.game(seed: 3, weather: Self.blizzard)
        #expect(
            fine.plays.map(\.outcome) != snowed.plays.map(\.outcome),
            "a blizzard changed nothing about the game")
    }
}
