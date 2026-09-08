/// A single rated attribute.
///
/// Split into general attributes, which every player has, and positional ones,
/// which only the positions that use them carry. A quarterback has no
/// `manCoverage` — not a zero, but *nothing*, so that reading the wrong key is
/// a caught mistake rather than a silently plausible number.
///
/// Raw values are stable and must not be renumbered: they index storage, and a
/// change would silently reinterpret every saved player.
public enum RatingKey: UInt8, CaseIterable, Sendable, Hashable, Codable {

    // General — every player
    case awareness = 0
    case speed = 1
    case acceleration = 2
    case agility = 3
    case strength = 4
    case stamina = 5
    case toughness = 6
    case injuryResistance = 7
    case discipline = 8

    // Passing
    case throwPower = 10
    case throwAccuracyShort = 11
    case throwAccuracyMedium = 12
    case throwAccuracyDeep = 13
    case underPressure = 14
    case playAction = 15

    // Ball carrying
    case carrying = 20
    case vision = 21
    case breakTackle = 22
    case elusiveness = 23

    // Receiving
    case catching = 30
    case catchInTraffic = 31
    case routeRunning = 32
    case releaseVsPress = 33

    // Blocking
    case runBlock = 40
    case passBlock = 41
    case blockAnchor = 42
    case handTechnique = 43

    // Front seven
    case powerMove = 50
    case finesseMove = 51
    case blockShedding = 52
    case pursuit = 53
    case tackling = 54
    case hitPower = 55

    // Coverage
    case manCoverage = 60
    case zoneCoverage = 61
    case ballHawk = 62

    // Kicking
    case kickPower = 70
    case kickAccuracy = 71
    case puntPower = 72
    case puntAccuracy = 73

    /// Attributes every player carries regardless of position.
    public static let general: [RatingKey] = [
        .awareness, .speed, .acceleration, .agility, .strength,
        .stamina, .toughness, .injuryResistance, .discipline,
    ]

    /// The full set a position uses, general attributes included.
    ///
    /// Generation fills exactly these and no others, so "absent" stays
    /// meaningful.
    public static func keys(for position: Position) -> [RatingKey] {
        general + positional(for: position)
    }

    public static func positional(for position: Position) -> [RatingKey] {
        switch position {
        case .quarterback:
            return [
                .throwPower, .throwAccuracyShort, .throwAccuracyMedium,
                .throwAccuracyDeep, .underPressure, .playAction, .carrying, .elusiveness,
            ]
        case .runningBack:
            return [.carrying, .vision, .breakTackle, .elusiveness, .catching, .passBlock]
        case .fullback:
            return [.carrying, .breakTackle, .catching, .runBlock, .passBlock, .hitPower]
        case .wideReceiver:
            return [.catching, .catchInTraffic, .routeRunning, .releaseVsPress, .elusiveness]
        case .tightEnd:
            return [
                .catching, .catchInTraffic, .routeRunning, .releaseVsPress,
                .runBlock, .passBlock,
            ]
        case .leftTackle, .leftGuard, .center, .rightGuard, .rightTackle:
            return [.runBlock, .passBlock, .blockAnchor, .handTechnique]
        case .edge:
            return [.powerMove, .finesseMove, .blockShedding, .pursuit, .tackling, .hitPower]
        case .defensiveTackle:
            return [.powerMove, .finesseMove, .blockShedding, .pursuit, .tackling, .hitPower]
        case .linebacker:
            return [
                .blockShedding, .pursuit, .tackling, .hitPower,
                .manCoverage, .zoneCoverage,
            ]
        case .cornerback:
            return [.manCoverage, .zoneCoverage, .ballHawk, .tackling, .releaseVsPress]
        case .safety:
            return [.manCoverage, .zoneCoverage, .ballHawk, .tackling, .hitPower, .pursuit]
        case .kicker:
            return [.kickPower, .kickAccuracy]
        case .punter:
            return [.puntPower, .puntAccuracy]
        case .longSnapper:
            return [.runBlock]
        }
    }
}

/// A player's rated attributes, on the genre-standard 0...99 scale.
///
/// Backed by a flat array indexed by `RatingKey.rawValue` plus a presence
/// bitmap, rather than a dictionary. Lookups are an array read with no hashing,
/// and "absent" is representable — both of which matter, though not because
/// `Ratings` is read inside the tick loop. It isn't: the engine copies the
/// handful of values a play needs into flat entity arrays at snap, and reads
/// those. This type is the domain representation.
public struct Ratings: Sendable, Hashable, Codable {

    /// Raw values are gapped so related keys sit together and new ones can be
    /// inserted without renumbering. Storage is indexed by raw value directly,
    /// so it is sized to the largest representable key rather than the number of
    /// keys — and the presence bitmap needs two words to match.
    ///
    /// A test asserts every key fits. Getting this wrong aliases one rating onto
    /// another silently, which is exactly the class of bug that only shows up as
    /// a kicker who is inexplicably tough.
    public static let maximumKeyCount = 128

    public static let range: ClosedRange<UInt8> = 0...99

    private var storage: [UInt8]
    private var presentLow: UInt64
    private var presentHigh: UInt64

    /// An empty set of ratings.
    public init() {
        storage = [UInt8](repeating: 0, count: Self.maximumKeyCount)
        presentLow = 0
        presentHigh = 0
    }

    /// Ratings from a set of key/value pairs, each clamped into 0...99.
    public init(_ values: [RatingKey: UInt8]) {
        self.init()
        for (key, value) in values {
            self[key] = value
        }
    }

    /// The value for `key`, or `nil` if this player does not carry it.
    ///
    /// Setting `nil` removes the rating; setting a value clamps it into 0...99
    /// rather than trapping, because clamping is what every caller would do.
    public subscript(key: RatingKey) -> UInt8? {
        get {
            guard has(key) else { return nil }
            return storage[Int(key.rawValue)]
        }
        set {
            let index = Int(key.rawValue)
            guard let newValue else {
                setPresence(key, to: false)
                storage[index] = 0
                return
            }
            storage[index] = min(max(newValue, Self.range.lowerBound), Self.range.upperBound)
            setPresence(key, to: true)
        }
    }

    /// The value for `key`, or `fallback` when absent.
    ///
    /// Simulation code should prefer this to force-unwrapping the subscript: a
    /// missing rating means the play is asking a player to do something his
    /// position does not do, which is a bug worth surviving rather than
    /// crashing on.
    public func value(_ key: RatingKey, or fallback: UInt8 = 0) -> UInt8 {
        self[key] ?? fallback
    }

    public func has(_ key: RatingKey) -> Bool {
        let raw = key.rawValue
        return raw < 64
            ? presentLow & (1 << UInt64(raw)) != 0
            : presentHigh & (1 << UInt64(raw - 64)) != 0
    }

    /// The keys this player actually carries, in stable order.
    public var keys: [RatingKey] {
        RatingKey.allCases.filter(has)
    }

    public var count: Int {
        presentLow.nonzeroBitCount + presentHigh.nonzeroBitCount
    }

    /// Whether exactly the keys `position` uses are present — no more, no fewer.
    ///
    /// An invariant for generated players. Checked rather than assumed, because
    /// a missing rating surfaces as odd behaviour deep in the engine rather than
    /// as an obvious failure.
    public func matchesKeys(for position: Position) -> Bool {
        Set(keys) == Set(RatingKey.keys(for: position))
    }

    private mutating func setPresence(_ key: RatingKey, to isPresent: Bool) {
        let raw = key.rawValue
        let bit: UInt64 = 1 << UInt64(raw < 64 ? raw : raw - 64)
        if raw < 64 {
            if isPresent { presentLow |= bit } else { presentLow &= ~bit }
        } else {
            if isPresent { presentHigh |= bit } else { presentHigh &= ~bit }
        }
    }
}

extension Ratings: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (RatingKey, UInt8)...) {
        self.init(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
