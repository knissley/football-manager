import FMCore
import FMRandom

/// Builds the teams a world starts with.
///
/// Initial generation only, like `RosterGenerator`. Nothing here runs again once a
/// career is under way: a rebrand or a move is a `TeamIdentityEvent` the player or the
/// league causes, not something the generator does behind their back.
public enum TeamGenerator {

    /// Names already handed out in this world.
    ///
    /// Nicknames and stadium names both come from finite pools, and both are visible
    /// side by side in a standings table or a schedule. Rolling each team in isolation
    /// produces collisions a per-team test cannot see, so the ledger is threaded
    /// through generation rather than checked afterwards.
    public struct NameLedger: Sendable {

        public var nicknames: Set<String> = []
        public var stadiums: Set<String> = []
        public var abbreviations: Set<String> = []
        /// The part of a city name before its suffix. Tracked separately because four
        /// distinct names — Saltflat, Saltflat Ridge, Saltflat Landing, Saltflat Mills
        /// — read as one city with a stutter, and uniqueness of the full string does
        /// not catch it.
        public var cityStems: Set<String> = []

        public init() {}
    }

    // MARK: - Cities

    /// A city, drawn from the pools for its region.
    ///
    /// Market and climate follow from the city rather than being rolled separately, so
    /// a world does not produce a major market in a place nothing else suggests is big.
    public static func city(
        in region: Region, ledger: inout NameLedger, using random: inout SplittableRandom
    ) -> GeneratedCity {
        let stems = CityPools.stems[region] ?? []

        // A stem is used once per world where the pool allows it. Past that the pool is
        // exhausted and repetition is the honest outcome — better than a generator that
        // gives up on a large custom league.
        var stem = stems[Int(random.next(upperBound: UInt64(stems.count)))]
        for _ in 0..<12 {
            if ledger.cityStems.insert(stem).inserted { break }
            stem = stems[Int(random.next(upperBound: UInt64(stems.count)))]
        }

        var name = stem
        if !random.nextBool(probability: CityPools.bareNameProbability) {
            let suffix =
                CityPools.suffixes[Int(random.next(upperBound: UInt64(CityPools.suffixes.count)))]
            name = "\(stem) \(suffix)"
        }

        // Most teams play in a real market; a couple of small ones give the league
        // somewhere that struggles to keep its stars.
        let market: MarketSize
        switch random.next(upperBound: 100) {
        case ..<15: market = .small
        case ..<50: market = .medium
        case ..<85: market = .large
        default: market = .major
        }

        let climate = climate(for: region, using: &random)
        let altitude: Int16 =
            region == .west && random.nextBool(probability: 0.25)
            ? Int16(random.nextInt(in: 3_000...5_500)) : Int16(random.nextInt(in: 0...900))

        return GeneratedCity(
            name: name, region: region, market: market, climate: climate,
            altitudeFeet: altitude)
    }

    /// Climate follows region, with enough overlap that the map is not a lookup table.
    private static func climate(
        for region: Region, using random: inout SplittableRandom
    ) -> Climate {
        let roll = random.next(upperBound: 100)
        switch region {
        case .north:
            return roll < 65 ? .cold : .temperate
        case .south:
            return roll < 55 ? .hot : (roll < 80 ? .temperate : .coastal)
        case .east:
            return roll < 50 ? .temperate : (roll < 80 ? .coastal : .cold)
        case .west:
            return roll < 35 ? .arid : (roll < 65 ? .coastal : (roll < 85 ? .temperate : .mountain))
        }
    }

    /// A set of distinct cities from one region.
    ///
    /// The caller asks per region rather than for a mixed pool, because how many cities
    /// each region needs follows from the league's shape — a two-division conference
    /// draws from two regions, not four — and generating an even spread and then
    /// dealing from it leaves regions short.
    public static func cities(
        in region: Region, count: Int, ledger: inout NameLedger,
        using random: inout SplittableRandom
    ) -> [GeneratedCity] {
        precondition(count >= 0, "cannot generate a negative number of cities")

        var cities: [GeneratedCity] = []
        cities.reserveCapacity(count)
        var seen: Set<String> = []

        for _ in 0..<count {
            // Bounded attempts: the name space is finite, and a duplicate city name is
            // a better outcome than a generator that fails.
            for attempt in 0..<8 {
                let candidate = city(in: region, ledger: &ledger, using: &random)
                if seen.insert(candidate.name).inserted || attempt == 7 {
                    cities.append(candidate)
                    break
                }
            }
        }
        return cities
    }

    // MARK: - Identity

    /// Colours that can be told apart from across a stadium.
    ///
    /// Draws until the pairing reads, then falls back to bone — a light secondary
    /// against any dark primary always contrasts, so the loop cannot fail to terminate
    /// with something legible.
    public static func colors(using random: inout SplittableRandom) -> TeamColors {
        let primary = PalettePools.dark[
            Int(random.next(upperBound: UInt64(PalettePools.dark.count)))]

        for _ in 0..<6 {
            let secondary = PalettePools.light[
                Int(random.next(upperBound: UInt64(PalettePools.light.count)))]
            let accent = PalettePools.light[
                Int(random.next(upperBound: UInt64(PalettePools.light.count)))]
            let candidate = TeamColors(primary: primary, secondary: secondary, accent: accent)
            if candidate.hasReadableContrast { return candidate }
        }
        return TeamColors(
            primary: primary, secondary: PalettePools.light[0], accent: PalettePools.light[1])
    }

    /// Two or three letters, derived from the name so it reads as that team's shorthand.
    ///
    /// Derived rather than drawn, because an abbreviation nobody can map back to the
    /// name is worse than a slightly awkward one. Collisions are real — two cities
    /// sharing initials is common — so candidates are tried in order of how well they
    /// read and the first unused one wins.
    public static func abbreviation(
        for city: String, nickname: String, ledger: inout NameLedger
    ) -> String {
        let words = city.split(separator: " ").map(String.init)
        let cityLetters = Array(city.uppercased().filter { $0 != " " })
        let nicknameLetters = Array(nickname.uppercased())

        var candidates: [String] = []

        if words.count >= 2 {
            candidates.append(words.prefix(3).map { $0.prefix(1).uppercased() }.joined())
        }
        if cityLetters.count >= 3 {
            candidates.append(String(cityLetters[0...2]))
        }
        if cityLetters.count >= 2, let initial = nicknameLetters.first {
            candidates.append(String(cityLetters[0...1]) + String(initial))
        }
        if let initial = cityLetters.first, nicknameLetters.count >= 2 {
            candidates.append(String(initial) + String(nicknameLetters[0...1]))
        }

        for candidate in candidates where ledger.abbreviations.insert(candidate).inserted {
            return candidate
        }

        // Everything readable is taken. Walk the city's own letters rather than
        // numbering, so the result still points back at the team.
        let base = String(cityLetters.prefix(2))
        for letter in nicknameLetters + cityLetters {
            let candidate = base + String(letter)
            if ledger.abbreviations.insert(candidate).inserted { return candidate }
        }

        let fallback = "T\(ledger.abbreviations.count + 1)"
        ledger.abbreviations.insert(fallback)
        return fallback
    }

    public static func stadium(
        for city: GeneratedCity, ledger: inout NameLedger, using random: inout SplittableRandom
    ) -> Stadium {
        let kind = StadiumPools.kinds[
            Int(random.next(upperBound: UInt64(StadiumPools.kinds.count)))]

        // A feature-led name reads better — most grounds were named for the place or
        // something in it — but the pool is small enough to collide across a league.
        // The city-led form is the fallback because cities are unique, so it cannot.
        var name = "\(city.name) \(kind)"
        if random.nextBool(probability: 0.55) {
            for _ in 0..<5 {
                let feature = StadiumPools.features[
                    Int(random.next(upperBound: UInt64(StadiumPools.features.count)))]
                let candidate = "\(feature) \(kind)"
                if !ledger.stadiums.contains(candidate) {
                    name = candidate
                    break
                }
            }
        }
        ledger.stadiums.insert(name)

        // Bigger markets build bigger, and a dome is far more likely where the weather
        // is a problem worth spending money on.
        let baseCapacity: Int
        switch city.market {
        case .small: baseCapacity = 58_000
        case .medium: baseCapacity = 65_000
        case .large: baseCapacity = 71_000
        case .major: baseCapacity = 78_000
        }
        let capacity = baseCapacity + random.nextInt(in: -4_000...4_000)

        let domeChance: Double = (city.climate == .cold || city.climate == .hot) ? 0.35 : 0.12
        let isIndoors = random.nextBool(probability: domeChance)

        let surface: PlayingSurface =
            isIndoors
            ? (random.nextBool(probability: 0.75) ? .artificial : .hybrid)
            : (random.nextBool(probability: 0.6)
                ? .grass : (random.nextBool(probability: 0.5) ? .artificial : .hybrid))

        // Noise is a stadium's own character, and it is the mechanism behind home field
        // advantage rather than a bonus applied on top of one (docs/penalties.md). A
        // dome keeps it in.
        var noise = random.nextInt(in: 35...85)
        if isIndoors { noise = min(100, noise + 12) }

        return Stadium(
            name: name,
            capacity: Int32(capacity),
            isIndoors: isIndoors,
            surface: surface,
            climate: isIndoors ? .temperate : city.climate,
            altitudeFeet: city.altitudeFeet,
            noise: UInt8(noise))
    }

    /// One team for a city.
    ///
    /// The ledger is passed in rather than rolled against, because two teams sharing a
    /// nickname — or a stadium name — is the kind of thing nobody notices in a test of
    /// one team and everybody notices in a standings table.
    public static func team(
        id: TeamID,
        city: GeneratedCity,
        ledger: inout NameLedger,
        using random: inout SplittableRandom
    ) -> Team {
        let categories = NicknamePools.categories(for: city.region)
        var nickname = ""
        for _ in 0..<24 {
            let category = categories[Int(random.next(upperBound: UInt64(categories.count)))]
            let candidate = category[Int(random.next(upperBound: UInt64(category.count)))]
            if ledger.nicknames.insert(candidate).inserted {
                nickname = candidate
                break
            }
        }
        if nickname.isEmpty {
            // The pools are finite. A numbered fallback is ugly, and it is still better
            // than two teams with one name.
            nickname = "Club \(ledger.nicknames.count + 1)"
            ledger.nicknames.insert(nickname)
        }

        let identity = TeamIdentity(
            city: city.name,
            nickname: nickname,
            abbreviation: abbreviation(for: city.name, nickname: nickname, ledger: &ledger),
            colors: colors(using: &random))

        return Team(
            id: id,
            region: city.region,
            identity: identity,
            stadium: stadium(for: city, ledger: &ledger, using: &random),
            market: city.market,
            scheme: SchemeIdentity.scheme(using: &random))
    }
}
