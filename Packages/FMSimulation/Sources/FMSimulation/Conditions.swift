import FMCore

/// What the weather does to a football game.
///
/// `WeatherState` had existed since the world was first generated and only the kicking
/// game had ever read it — so a game in driving snow threw and caught the ball exactly
/// like a game in a dome, and the first calibration run that included weather at all found
/// scoring *higher* in the rain than in the dry.
///
/// Gathered here rather than scattered through the resolver because these are facts about
/// conditions, not about how this particular engine models a play: they should survive the
/// spatial resolver replacing the crude one
/// ([ADR-0012](../../../../docs/adr/0012-play-resolver-seam.md)).
///
/// Deliberately modest. Weather in the sport is real and it is not decisive: a bad day
/// moves a passing offence by a few points of completion, not by half.
enum Conditions {

    /// How much harder the ball is to catch cleanly and hold on to, 0 upwards.
    ///
    /// Wet hands and cold hands are the two things that put a ball on the ground, and
    /// both of them do it to the catcher and the carrier alike.
    static func handling(_ weather: WeatherState) -> Double {
        guard !weather.isIndoors else { return 0 }
        var difficulty = 0.0
        switch weather.precipitation {
        case .none: difficulty += 0
        case .rain: difficulty += 0.35
        case .heavyRain: difficulty += 0.75
        case .snow: difficulty += 0.85
        }
        // Below freezing the ball goes hard and hands go numb.
        if weather.temperature <= 32 { difficulty += 0.30 }
        if weather.temperature <= 20 { difficulty += 0.25 }
        // A gale makes the ball move late.
        if weather.windSpeed >= 20 { difficulty += 0.25 }
        return difficulty
    }

    /// Accuracy lost on a throw, in the same units `placement` works in.
    ///
    /// Scaled by how far the ball has to travel, because that is how wind actually
    /// behaves: a three-step throw is barely affected and a deep ball is a different
    /// proposition entirely.
    static func throwing(_ weather: WeatherState, depthYards: Int) -> Double {
        guard !weather.isIndoors else { return 0 }
        let carry = Double(max(0, min(30, depthYards))) / 20.0
        // Modest on purpose. A larger penalty here pushes throws from "on target" into
        // "poor", and a poor ball into tight coverage is where interceptions come from —
        // so an over-weighted weather term shows up as a league throwing three picks a
        // game rather than as a hard day to throw in.
        var lost = Double(max(0, Int(weather.windSpeed) - 8)) * 0.004 * carry
        if weather.precipitation != .none { lost += 0.018 }
        if weather.temperature <= 25 { lost += 0.012 }
        return lost
    }

    /// Yards a kick effectively gains or loses before the curve is consulted.
    ///
    /// Thin air is the one condition that helps: a mile up, the ball carries. Altitude is
    /// generated for every stadium and had never reached a game.
    static func kickingAdjustment(_ weather: WeatherState, altitudeFeet: Int16) -> Double {
        var yards = Double(altitudeFeet) / 1_400.0
        guard !weather.isIndoors else { return yards }
        if weather.temperature <= 32 { yards -= 1.5 }
        if weather.temperature <= 15 { yards -= 1.5 }
        if weather.windSpeed >= 15 { yards -= Double(Int(weather.windSpeed) - 12) * 0.25 }
        if weather.precipitation == .snow { yards -= 2.0 }
        return yards
    }
}
