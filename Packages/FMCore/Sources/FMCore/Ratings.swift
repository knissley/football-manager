/// A single rated attribute.
///
/// Split into general attributes, which every position trains, and positional
/// ones, which only some do. **Every player carries every key.** A quarterback's
/// `manCoverage` is present and low — drawn by generation from an untrained
/// distribution — rather than absent, because an absent key was a free pass:
/// `overall(at:)` dropped its weight and renormalised over what was there, so a
/// receiver evaluated at quarterback was scored on his awareness and speed alone
/// and came out a better quarterback than a receiver.
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

    /// Attributes every position trains.
    public static let general: [RatingKey] = [
        .awareness, .speed, .acceleration, .agility, .strength,
        .stamina, .toughness, .injuryResistance, .discipline,
    ]

    /// The keys a position **trains**, general attributes included.
    ///
    /// What generation draws around a player's quality, and what
    /// `PositionWeights` may weigh. Not the set he carries: he carries every key,
    /// and the ones outside this list are drawn low.
    public static func keys(for position: Position) -> [RatingKey] {
        general + positional(for: position)
    }

    /// The positional keys a position trains.
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
        // A receiver is a runner from the moment the catch is complete — the rules give
        // one definition of a runner and one of a fumble, neither of them by position
        // (2025 rulebook, 3-27, 3-2-5, 8-1-3) — so holding on to the ball and breaking a
        // tackle are his to train like anybody else who runs with it. Left off, they fell
        // to the untrained table's ball-carrying floor, and the fumble draw reads a
        // carrier's `carrying` and nothing else about him.
        case .wideReceiver:
            return [
                .catching, .catchInTraffic, .routeRunning, .releaseVsPress,
                .carrying, .breakTackle, .elusiveness,
            ]
        case .tightEnd:
            return [
                .catching, .catchInTraffic, .routeRunning, .releaseVsPress,
                .carrying, .breakTackle, .runBlock, .passBlock,
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

    /// The families the positional keys fall into: what a rating is *for*.
    ///
    /// Generation draws a key a position does not train from a distribution per
    /// family, so a lineman's four passing ratings are one row of a table rather
    /// than four constants. The general attributes are their own family.
    public enum Family: UInt8, CaseIterable, Sendable, Hashable {
        case general
        case passing
        case ballCarrying
        case receiving
        case blocking
        case frontSeven
        case coverage
        case kicking

        /// Every key in the family, in raw-value order.
        public var keys: [RatingKey] {
            RatingKey.allCases.filter { $0.family == self }
        }
    }

    public var family: Family {
        switch self {
        case .awareness, .speed, .acceleration, .agility, .strength,
            .stamina, .toughness, .injuryResistance, .discipline:
            return .general
        case .throwPower, .throwAccuracyShort, .throwAccuracyMedium, .throwAccuracyDeep,
            .underPressure, .playAction:
            return .passing
        case .carrying, .vision, .breakTackle, .elusiveness:
            return .ballCarrying
        case .catching, .catchInTraffic, .routeRunning, .releaseVsPress:
            return .receiving
        case .runBlock, .passBlock, .blockAnchor, .handTechnique:
            return .blocking
        case .powerMove, .finesseMove, .blockShedding, .pursuit, .tackling, .hitPower:
            return .frontSeven
        case .manCoverage, .zoneCoverage, .ballHawk:
            return .coverage
        case .kickPower, .kickAccuracy, .puntPower, .puntAccuracy:
            return .kicking
        }
    }
}

/// A player's rated attributes, on the genre-standard 0...99 scale.
///
/// Backed by a flat array indexed by `RatingKey.rawValue` plus a presence
/// bitmap, rather than a dictionary. Lookups are an array read with no hashing —
/// which matters, though not because `Ratings` is read inside the tick loop. It
/// isn't: the engine copies the handful of values a play needs into flat entity
/// arrays at snap, and reads those. This type is the domain representation.
///
/// A generated player carries **every** key (`isComplete`). The bitmap stays
/// because a hand-built set can still have holes, and the bitmap is how an
/// overall read from one is caught in debug rather than quietly scored on the
/// keys that happen to be there.
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

    /// What a reader gets for a key nobody wrote.
    ///
    /// Generation writes every key, so this is reached only by a hand-built set,
    /// and only in a release build: in debug the read is an assertion. The value
    /// is the untrained centre that most of generation's table shares, so a
    /// missing rating reads as a man who has never done the thing — never as his
    /// overall, and never as nothing.
    public static let untrainedFloor: UInt8 = 25

    private var storage: [UInt8]
    private var presentLow: UInt64
    private var presentHigh: UInt64

    /// An empty set of ratings.
    public init() {
        storage = [UInt8](repeating: 0, count: Self.maximumKeyCount)
        presentLow = 0
        presentHigh = 0
    }

    /// Every key at one value.
    ///
    /// The starting point for a hand-built player: complete by construction, so
    /// the keys a test then overrides are the only thing it is saying anything
    /// about.
    public static func uniform(_ value: UInt8) -> Ratings {
        var ratings = Ratings()
        for key in RatingKey.allCases {
            ratings[key] = value
        }
        return ratings
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
    /// A generated player is never absent anything, so a caller that reaches the
    /// fallback has been handed a hand-built set. Prefer this to force-unwrapping
    /// the subscript all the same: surviving one is better than crashing on it.
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

    /// Whether every key is present.
    ///
    /// The invariant for a generated player: a rating his position does not
    /// train is present and low, never absent. Checked rather than assumed,
    /// because a missing rating used to surface as a plausible number deep in the
    /// engine — a mover scored on the keys he happened to have — rather than as
    /// an obvious failure.
    public var isComplete: Bool {
        count == RatingKey.allCases.count
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
