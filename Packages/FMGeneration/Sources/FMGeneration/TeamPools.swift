import FMCore

/// A generated city: a name, a region, and the market and weather that follow from it.
public struct GeneratedCity: Sendable, Hashable, Codable {
    public let name: String
    public let region: Region
    public let market: MarketSize
    public let climate: Climate
    public let altitudeFeet: Int16
}

/// Parts for inventing cities.
///
/// Real places are as off-limits as real teams and real colleges
/// ([ADR-0005](../../../../docs/adr/0005-generated-fictional-content.md)), so cities
/// are assembled from a stem and a suffix. The pools are split by region so that a
/// northern city sounds northern — flavour the generator gets for free, and the thing
/// that stops thirty-two names blurring into one another.
enum CityPools {

    static let stems: [Region: [String]] = [
        .north: [
            "Kettle", "Birch", "Frost", "Granite", "Alder", "Pinecrest", "Ironbark", "Winter",
            "Norwold", "Timber", "Elkhart", "Coldspring", "Aurora", "Steelfall", "Mooring",
        ],
        .south: [
            "Magnolia", "Delta", "Bayou", "Sable", "Cotton", "Belleview", "Cypress", "Marigold",
            "Sugarhill", "Verano", "Palmetto", "Camellia", "Riverstead", "Goldleaf", "Tallow",
        ],
        .east: [
            "Harbor", "Quincy", "Meridian", "Ashport", "Bellhaven", "Carrick", "Dunmore",
            "Fallstead", "Kingsbridge", "Newhaven", "Sablewick", "Thorne", "Wrenford", "Ember",
            "Lockridge",
        ],
        .west: [
            "Coyote", "Vermillion", "Saltflat", "Redmesa", "Cascade", "Junipero", "Big Sur",
            "Sundown", "Copper", "Silverpeak", "Alta", "Wildhorse", "Painted", "Estero", "Baja",
        ],
    ]

    static let suffixes: [String] = [
        "City", "Falls", "Harbor", "Heights", "Landing", "Point", "Ridge", "Springs", "Bay",
        "Park", "Crossing", "Hollow", "Reach", "Junction", "Mills",
    ]

    /// Some cities are just the stem. A world where every name is two words reads as
    /// generated, and the sport's own city names are a mix.
    static let bareNameProbability = 0.35
}

/// Parts for inventing team nicknames.
///
/// Checked against the real league's thirty-two and its historical names; nothing here
/// collides with one. The categories exist so a generated league has the same spread
/// the real thing does — animals, trades, weather, and the odd bit of local myth —
/// rather than thirty-two predators.
enum NicknamePools {

    static let animals: [String] = [
        "Badgers", "Barracudas", "Bison", "Bobcats", "Condors", "Coyotes", "Elk", "Foxes",
        "Gators", "Goshawks", "Grizzlies", "Herons", "Ibex", "Jackals", "Kestrels", "Lynx",
        "Mustangs", "Ospreys", "Otters", "Pumas", "Rattlers", "Stallions", "Stags", "Timberwolves",
        "Vipers", "Wolverines",
    ]

    static let trades: [String] = [
        "Anchors", "Blacksmiths", "Boilermakers", "Brewers", "Drillers", "Foundry", "Ironworkers",
        "Longshoremen", "Millers", "Miners", "Pilots", "Prospectors", "Quarrymen", "Railmen",
        "Riverboats", "Shipwrights", "Smelters", "Surveyors", "Tanners", "Wranglers",
    ]

    /// Weather names are region-bound, because a western team called Nor'easters or a
    /// team from the hot south called Avalanche reads as generated the instant anyone
    /// notices. The neutral set is available everywhere.
    static let neutralWeather: [String] = ["Cyclones", "Gale", "Squall", "Thunder", "Torrent"]

    static let regionalWeather: [Region: [String]] = [
        .north: ["Avalanche", "Blizzard", "Whiteout", "Frostbite", "Northwind"],
        .south: ["Embers", "Wildfire", "Heatwave", "Monsoon", "Swelter"],
        .east: ["Nor'easters", "Tide", "Undertow", "Riptide", "Surge"],
        .west: ["Dust Devils", "Chinook", "Mirage", "Santa Anas", "Drought"],
    ]

    static let myth: [String] = [
        "Argonauts", "Banshees", "Centaurs", "Gargoyles", "Golems", "Griffins", "Harbingers",
        "Kraken", "Minotaurs", "Nomads", "Oracles", "Phantoms", "Revenants", "Sentinels",
        "Specters", "Wardens", "Wyverns",
    ]

    /// The categories a team from this region can draw from.
    ///
    /// Weather is filtered; animals, trades and myth travel anywhere, the way they do
    /// in the real thing.
    static func categories(for region: Region) -> [[String]] {
        [animals, trades, neutralWeather + (regionalWeather[region] ?? []), myth]
    }
}

/// Parts for inventing stadium names.
///
/// No sponsor names: a fictional corporation reads as a joke, and a real one is a mark.
/// Generated grounds are named for the place or a feature of it, which is what most
/// stadiums were called before anybody sold the naming rights.
enum StadiumPools {

    static let kinds: [String] = [
        "Field", "Stadium", "Park", "Bowl", "Coliseum", "Grounds", "Yard", "Arena",
    ]

    static let features: [String] = [
        "Memorial", "Municipal", "Union", "Liberty", "Harborside", "Riverfront", "Lakeside",
        "Hillcrest", "Founders", "Centennial", "Cathedral", "Sunset", "Northgate", "Old Mill",
    ]
}

/// A palette to draw team colours from.
///
/// Hand-picked rather than random RGB: random colours produce mud, and a league whose
/// teams are all mud is one nobody can tell apart on a scoreboard. Split by lightness
/// so a generator can always find a pairing that reads
/// (`TeamColors.hasReadableContrast`).
enum PalettePools {

    /// Deep colours, for a primary.
    static let dark: [TeamColor] = [
        TeamColor(red: 12, green: 35, blue: 64),  // navy
        TeamColor(red: 20, green: 52, blue: 40),  // forest
        TeamColor(red: 92, green: 16, blue: 28),  // maroon
        TeamColor(red: 40, green: 22, blue: 66),  // aubergine
        TeamColor(red: 24, green: 24, blue: 26),  // near-black
        TeamColor(red: 96, green: 44, blue: 12),  // rust
        TeamColor(red: 14, green: 58, blue: 74),  // teal
        TeamColor(red: 72, green: 20, blue: 62),  // plum
        TeamColor(red: 58, green: 62, blue: 20),  // olive
        TeamColor(red: 122, green: 26, blue: 20),  // brick
    ]

    /// Bright colours, for a secondary or an accent.
    static let light: [TeamColor] = [
        TeamColor(red: 240, green: 236, blue: 224),  // bone
        TeamColor(red: 236, green: 190, blue: 62),  // gold
        TeamColor(red: 244, green: 148, blue: 40),  // orange
        TeamColor(red: 158, green: 214, blue: 236),  // sky
        TeamColor(red: 176, green: 210, blue: 120),  // spring
        TeamColor(red: 232, green: 122, blue: 140),  // coral
        TeamColor(red: 200, green: 200, blue: 206),  // silver
        TeamColor(red: 246, green: 214, blue: 160),  // sand
    ]
}

/// Names for the league and its parts.
enum StructurePools {

    static let leagueNames: [String] = [
        "Continental Football League", "United Football League", "Premier Gridiron League",
        "National Gridiron Association", "Federal Football League",
    ]

    static let conferenceNames: [String] = [
        "Atlantic", "Pacific", "Continental", "Frontier", "Meridian", "Summit",
    ]

    /// Directional first, so a four-division conference names itself the way the sport
    /// does. Beyond four, the thematic names take over.
    static let divisionNames: [String] = [
        "North", "South", "East", "West", "Central", "Coastal", "Highland", "Valley",
    ]
}
