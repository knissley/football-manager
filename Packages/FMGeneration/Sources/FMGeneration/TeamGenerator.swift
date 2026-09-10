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
    ///
    /// It is threaded through a *curated* league too, even though nothing there is
    /// drawn: a league that takes its franchises from `FranchiseSet` and tops up a short
    /// region from the pools would otherwise draw a name the curated half already has.
    /// `record(_:)` is how the curated half gets into it.
    public struct NameLedger: Sendable {

        public var nicknames: Set<String> = []
        /// A nickname's root, lowercased and without its plural ending. The full names
        /// above are what a standings table shows; this is what makes two of them the
        /// same name — a pool that ever holds both "Kestrel" and "Kestrels" cannot hand
        /// out one of each.
        public var nicknameStems: Set<String> = []
        /// The word a feature-led ground is named for. Tracked because the collision
        /// that reads as a duplicate is the *word*: Lakeside Park, Lakeside Field
        /// and Lakeside Arena are three distinct strings and one ground written down
        /// three times.
        ///
        /// There is deliberately no set of whole stadium names beside it. One existed,
        /// was written on every draw and read by nothing, and a ledger nobody consults
        /// is a uniqueness rule that is not enforced (#65).
        public var stadiumFeatures: Set<String> = []
        public var abbreviations: Set<String> = []
        /// Whole city names, so "cities are unique in a world" is a property of the
        /// world and not of one region's batch. `stadium(for:ledger:using:)` relies on
        /// it: a city-led ground name can only be unique if the city is.
        public var cityNames: Set<String> = []
        /// The part of a city name before its suffix. Tracked separately because four
        /// distinct names — Saltflat, Saltflat Ridge, Saltflat Landing, Saltflat Mills
        /// — read as one city with a stutter, and uniqueness of the full string does
        /// not catch it.
        public var cityStems: Set<String> = []

        public init() {}

        /// Take a curated franchise's names out of circulation.
        ///
        /// The stadium's feature word is recognised rather than parsed: a curated ground
        /// named for a place — Drydock Field — spends no pool word, and one that happens
        /// to lead with a pool feature spends exactly that word.
        public mutating func record(_ franchise: Franchise) {
            nicknames.insert(franchise.nickname)
            nicknameStems.insert(TeamGenerator.stem(ofNickname: franchise.nickname))
            abbreviations.insert(franchise.abbreviation)
            cityNames.insert(franchise.city)
            cityStems.insert(TeamGenerator.stem(ofCity: franchise.city))
            for feature in StadiumPools.features
            where franchise.stadiumName.hasPrefix("\(feature) ") {
                stadiumFeatures.insert(feature)
            }
        }
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
            name: name, stem: stem, region: region, market: market, climate: climate,
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

        for _ in 0..<count {
            // Against the world's ledger rather than this batch's own set: the caller
            // asks region by region, and a name that is unique among the north's eight
            // is not unique in the league if the east has it too (#65).
            //
            // Bounded attempts: the name space is finite, and a duplicate city name is
            // a better outcome than a generator that fails.
            for attempt in 0..<8 {
                let candidate = city(in: region, ledger: &ledger, using: &random)
                if ledger.cityNames.insert(candidate.name).inserted || attempt == 7 {
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

    /// A nickname's comparable root: lowercased, with a plural ending taken off.
    ///
    /// Deliberately crude. It exists to tell two spellings of one word apart, not to
    /// conjugate English — "Foxes" reduces to "foxe", which is wrong as grammar and
    /// perfectly serviceable as a key, because the only thing ever asked of it is
    /// whether two names reduce to the same thing.
    static func stem(ofNickname nickname: String) -> String {
        let lowered = nickname.lowercased()
        return lowered.hasSuffix("s") ? String(lowered.dropLast()) : lowered
    }

    /// A city's stem: its name with a pool suffix taken off, and the whole of a bare
    /// name.
    ///
    /// A drawn city carries its stem, because the two pools share words and parsing one
    /// back out is guesswork. A *curated* city carries no stem — it was written, not
    /// assembled — so the ledger reads one off it this way, and that is right only when
    /// the last word is a suffix the pools use.
    ///
    /// When it is not, this returns the **whole name** and the ledger records that, so
    /// the real stem is never spent and a drawn city may repeat it. Four curated cities
    /// end in a word the pools do not know — Junipero Mesa, Alta Verde, Vermillion Flats
    /// and Tallow Bend — so a league that draws a city beside one of those four can field
    /// Vermillion Flats next to Vermillion Heights.
    ///
    /// Nothing ships in that state, and the reason is regional rather than a headcount.
    /// `FranchiseSet.initial` holds eight clubs per region, and `LeagueGenerator` tops a
    /// region up from the pools only when the shape asks it for more than it has — so on
    /// the *curated* source a city is drawn when some region is asked for more than
    /// eight. What a region is asked for is the divisions that land on it × `conferences`
    /// × `teamsPerDivision`, so with the four-team divisions a career is played in it
    /// means past thirty-two — but with wider divisions it happens below it. Measured:
    /// two conferences of two five-team divisions is a twenty-team league and draws four
    /// cities, and two of three is a thirty-team league and draws six, one of which lands
    /// beside a curated city it can stutter with. The other two sources draw at every size — `.randomised`
    /// draws all of them, and a short `.set` has the rest of its league drawn around its
    /// own lines, seven of eight in the tests' minimal world. None of those ships. The
    /// stutter is the same class of fault
    /// [#4](https://github.com/knissley/football-manager/issues/4) found in the
    /// randomiser, deferred with it to the pre-release revisit of generation
    /// ([M8](../../../../docs/roadmap.md)).
    static func stem(ofCity city: String) -> String {
        let words = city.split(separator: " ").map(String.init)
        guard words.count > 1, let last = words.last, CityPools.suffixes.contains(last) else {
            return city
        }
        return words.dropLast().joined(separator: " ")
    }

    /// Whether a nickname says its own city back at it — Coyote Coyotes, Frost
    /// Frostbite, Elkhart Elk.
    ///
    /// Both directions, because the echo runs both ways: the nickname can carry the
    /// city's whole stem ("Coyotes" holds "Coyote"), or the city can carry the
    /// nickname's ("Elkhart" holds "Elk"). Compared on the stem going the second way so
    /// a plural does not hide the repeat.
    ///
    /// What it does not catch is an echo of *meaning* rather than of letters: Winter
    /// Blizzard shares no substring, and a generator would need to know what the words
    /// mean to refuse it.
    static func echoesCity(_ nickname: String, stem cityStem: String) -> Bool {
        let city = cityStem.lowercased()
        guard !city.isEmpty else { return false }
        return nickname.lowercased().contains(city) || city.contains(stem(ofNickname: nickname))
    }

    public static func stadium(
        for city: GeneratedCity, ledger: inout NameLedger, using random: inout SplittableRandom
    ) -> Stadium {
        let kind = StadiumPools.kinds[
            Int(random.next(upperBound: UInt64(StadiumPools.kinds.count)))]

        // A feature-led name reads better — most grounds were named for the place or
        // something in it — but the pool is small enough to collide across a league, and
        // what collides is the word rather than the whole name: Lakeside Park and
        // Lakeside Field are one ground written down twice however the kinds differ.
        // So a feature word is spent once per world. When the draws all land on words
        // already spent, the city-led form takes over — a city name is spent once per
        // world too, in the same ledger, and no city is named for a feature, so it
        // cannot collide with anything. The one exception is the exhausted pool, where
        // `cities(in:count:)` repeats a name rather than failing and this repeats with
        // it (#65).
        var name = "\(city.name) \(kind)"
        if random.nextBool(probability: 0.55) {
            for _ in 0..<5 {
                let feature = StadiumPools.features[
                    Int(random.next(upperBound: UInt64(StadiumPools.features.count)))]
                if ledger.stadiumFeatures.insert(feature).inserted {
                    name = "\(feature) \(kind)"
                    break
                }
            }
        }
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

    // MARK: - Franchises

    /// One drawn franchise for a region: a city, a name for the club and a ground.
    ///
    /// The randomiser of [decision 154](../../../../docs/design-decisions.md), behind
    /// `FranchiseSource.randomised` and not refined
    /// ([decision 215](../../../../docs/design-decisions.md)). It returns the same shape
    /// the curated table holds, so `team(id:franchise:using:)` is the only way a `Team`
    /// is built and a drawn league and a curated one differ in nothing but where the
    /// row came from.
    ///
    /// The ledger is passed in rather than rolled against, because two teams sharing a
    /// nickname — or a stadium name — is the kind of thing nobody notices in a test of
    /// one team and everybody notices in a standings table.
    public static func franchise(
        in region: Region, ledger: inout NameLedger, using random: inout SplittableRandom
    ) -> Franchise {
        let city = city(in: region, ledger: &ledger, using: &random)
        return franchise(for: city, ledger: &ledger, using: &random)
    }

    /// A set of drawn franchises for one region, cities and all.
    ///
    /// Asked for region by region for the reason `cities(in:count:)` is: how many a
    /// region needs follows from the league's shape, and an even spread across four
    /// regions leaves a two-division conference short.
    public static func franchises(
        in region: Region, count: Int, ledger: inout NameLedger,
        using random: inout SplittableRandom
    ) -> [Franchise] {
        precondition(count >= 0, "cannot generate a negative number of franchises")

        let cities = cities(in: region, count: count, ledger: &ledger, using: &random)
        return cities.map { franchise(for: $0, ledger: &ledger, using: &random) }
    }

    /// The club a drawn city fields, and the ground it fields it in.
    private static func franchise(
        for city: GeneratedCity, ledger: inout NameLedger, using random: inout SplittableRandom
    ) -> Franchise {
        let nickname = nickname(for: city, ledger: &ledger, using: &random)
        let abbreviation = abbreviation(for: city.name, nickname: nickname, ledger: &ledger)
        let palette = colors(using: &random)
        let ground = stadium(for: city, ledger: &ledger, using: &random)
        return Franchise(
            city: city.name,
            region: city.region,
            market: city.market,
            climate: city.climate,
            altitude: city.altitudeFeet,
            nickname: nickname,
            abbreviation: abbreviation,
            primary: palette.primary.rawValue,
            secondary: palette.secondary.rawValue,
            accent: palette.accent.rawValue,
            stadium: ground.name,
            roof: ground.isIndoors ? .dome : .open,
            surface: ground.surface,
            capacity: ground.capacity,
            noise: ground.noise)
    }

    /// A nickname nobody else in this world has, that does not say its own city back.
    private static func nickname(
        for city: GeneratedCity, ledger: inout NameLedger, using random: inout SplittableRandom
    ) -> String {
        let categories = NicknamePools.categories(for: city.region)
        var nickname = ""
        for _ in 0..<24 {
            let category = categories[Int(random.next(upperBound: UInt64(categories.count)))]
            let candidate = category[Int(random.next(upperBound: UInt64(category.count)))]
            // Coyote Coyotes. The pools are region-filtered, which puts a city and a
            // nickname drawn from the same corner of the map next to each other far more
            // often than chance would, so this is drawn again rather than lived with.
            if echoesCity(candidate, stem: city.stem) { continue }
            // On the stem rather than the whole name, so a pool that ever holds a
            // singular and its plural cannot hand out one of each.
            if ledger.nicknameStems.insert(stem(ofNickname: candidate)).inserted {
                ledger.nicknames.insert(candidate)
                nickname = candidate
                break
            }
        }
        if nickname.isEmpty {
            // The pools are finite. A numbered fallback is ugly, and it is still better
            // than two teams with one name.
            nickname = "Club \(ledger.nicknames.count + 1)"
            ledger.nicknames.insert(nickname)
            ledger.nicknameStems.insert(stem(ofNickname: nickname))
        }
        return nickname
    }

    // MARK: - Teams

    /// The team a franchise fields.
    ///
    /// The only draw left is the scheme, because a scheme is what a club is *doing*
    /// rather than who it is: a coach arrives and changes it, and a career that started
    /// twice in the same buildings should not find the same playbooks in them
    /// ([decision 215](../../../../docs/design-decisions.md)).
    public static func team(
        id: TeamID, franchise: Franchise, using random: inout SplittableRandom
    ) -> Team {
        Team(
            id: id,
            region: franchise.region,
            identity: TeamIdentity(
                city: franchise.city,
                nickname: franchise.nickname,
                abbreviation: franchise.abbreviation,
                colors: franchise.colors),
            stadium: franchise.stadium,
            market: franchise.market,
            scheme: SchemeIdentity.scheme(using: &random))
    }
}
