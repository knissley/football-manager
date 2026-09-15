import FMCore
import FMRandom

/// Who is on the field, by slot.
///
/// Named `Lineup` rather than `Personnel` because the sport uses that word for two
/// different things and `FMCore` already has the other one: `FMCore.Personnel` is a person
/// the club employs, and a `PersonnelGroup` is the shorthand for who a team sent out. This
/// is the eleven actually standing there.
///
/// Slots 0–10 are the offence and 11–21 the defence, which is the convention
/// `PlayerSlot` and `Participation` already depend on: the team a player was on follows
/// from his slot rather than being stored on every credit.
public struct Lineup: Sendable {

    public private(set) var slots: [PlayerID?]
    public private(set) var positions: [Position?]

    public init() {
        slots = Array(repeating: nil, count: PlayerSlot.count)
        positions = Array(repeating: nil, count: PlayerSlot.count)
    }

    public subscript(slot: PlayerSlot) -> PlayerID? {
        guard !slot.isNone, Int(slot.rawValue) < slots.count else { return nil }
        return slots[Int(slot.rawValue)]
    }

    public func position(at slot: PlayerSlot) -> Position? {
        guard !slot.isNone, Int(slot.rawValue) < positions.count else { return nil }
        return positions[Int(slot.rawValue)]
    }

    mutating func place(_ player: PlayerID, position: Position, at slot: Int) {
        slots[slot] = player
        positions[slot] = position
    }

    /// Slots that were actually filled, offence first.
    public var occupied: [PlayerSlot] {
        (0..<PlayerSlot.count).compactMap { slots[$0] == nil ? nil : PlayerSlot($0) }
    }

    // MARK: - Who is where, given who was sent out
    //
    // These read the personnel rather than a fixed table, which is the point of having
    // personnel at all: an extra tight end is an extra blocker, an empty set has five men
    // running routes, and a dime package has corners where a base defence has linebackers.
    // With static lists none of that could be true.

    private func slots(in range: Range<Int>, matching test: (Position) -> Bool) -> [PlayerSlot] {
        range.compactMap { index in
            guard let position = positions[index], test(position) else { return nil }
            return PlayerSlot(index)
        }
    }

    /// The five linemen, plus any tight end or fullback who stays in to block.
    public func blockers(includingEligibles: Bool) -> [PlayerSlot] {
        let line = slots(in: 6..<11) { _ in true }
        guard includingEligibles else { return line }
        return line + slots(in: 1..<6) { $0 == .tightEnd || $0 == .fullback }
    }

    /// Everyone running a route, outside receivers first so the best coverage matches up
    /// against them.
    ///
    /// `stayingIn` is the eligible who is blocking instead — `Protection.keptIn` — because
    /// a man cannot block the sixth rusher and run the checkdown on the same snap. Nobody
    /// stays in on most snaps and the parameter is then empty.
    public func routeRunners(excluding stayingIn: PlayerSlot? = nil) -> [PlayerSlot] {
        let order: [Position] = [.wideReceiver, .tightEnd, .runningBack, .fullback]
        return order.flatMap { position in
            slots(in: 1..<6) { $0 == position }
        }
        .filter { $0 != stayingIn }
    }

    /// The men rushing the passer or holding the point, edges first.
    public var front: [PlayerSlot] {
        slots(in: 11..<22) { $0 == .edge } + slots(in: 11..<22) { $0 == .defensiveTackle }
    }

    /// Everyone in coverage, best cover men first: corners, then safeties, then whoever
    /// is left off the ball. A linebacker covering the number one receiver is what the
    /// old fixed list produced, and it is why base personnel needs to be a real choice
    /// rather than a label.
    public var coverageDefenders: [PlayerSlot] {
        slots(in: 11..<22) { $0 == .cornerback }
            + slots(in: 11..<22) { $0 == .safety }
            + slots(in: 11..<22) { $0 == .linebacker }
    }

    // MARK: - The rush, the protection, and who is left to cover
    //
    // **The convention the rest of the engine reads: `front` is who lined up on the ball
    // and `rush(_:)` is who came.** They are the same men on a four-man rush and on no
    // other call. A fact about the neutral zone belongs to the front — an encroachment is
    // a man over the ball, whether or not he was sent — and a fact about a rep belongs to
    // the rush. Nothing here counts a man twice: what `rush(_:)` sends,
    // `coverageDefenders(after:)` subtracts, and the eleven still hold eleven jobs
    // (2025 rulebook, 5-1-1).
    //
    // **Who rushes and who protects is coaching convention, not rules.** No article says
    // where an extra rusher comes from or who picks him up, and no season in
    // docs/reference/calibration-sources.md bands it; the choices below are stated there
    // under *What a test claims about a game and nothing sources* and in
    // docs/match-engine.md, in the sense the arrival window and the read order are.

    /// The men a pass-rush call sends, and the lineman it dropped to send them.
    public struct Rush: Sendable, Hashable {

        /// Everyone coming, in the order the protection picks them up: the front first,
        /// then the extras, closest to the ball first.
        public var rushers: [PlayerSlot]

        /// The down lineman who dropped instead of rushing — the zone blitz's exchange,
        /// and `.none` on every other call.
        public var dropping: PlayerSlot

        public init(rushers: [PlayerSlot], dropping: PlayerSlot = .none) {
            self.rushers = rushers
            self.dropping = dropping
        }
    }

    /// Who comes, given the call.
    ///
    /// The count is the call's, taken from the eleven actually out there and not from the
    /// four men on the ball: the front first, then the extras — linebackers, then
    /// safeties, then the extra defensive back, which is closest-to-the-ball order and is
    /// stable, so the same eleven and the same call always send the same men.
    public func rush(_ call: PassRush) -> Rush {
        let front = self.front
        let wanted = Int(call.rushers)
        let linebackers = slots(in: 11..<22) { $0 == .linebacker }

        var coming = Array(front.prefix(wanted))
        if coming.count < wanted {
            let extras =
                linebackers + slots(in: 11..<22) { $0 == .safety }
                + slots(in: 11..<22) { $0 == .cornerback }
            coming += extras.prefix(wanted - coming.count)
        }
        guard call == .zoneBlitz else { return Rush(rushers: coming) }

        // Still four, and not the four who lined up: an interior lineman drops off and a
        // linebacker comes through the gap he left. The exchange is the call — it beats a
        // protection that counted the front and loses to the throw into the area the
        // linebacker vacated, which is what `CallVulnerability.hotThrow` already names.
        //
        // A front with no interior lineman to spare, or a package with no second
        // linebacker to send, has no exchange to make and rushes the four it had: a
        // three-man front's fourth rusher is already the linebacker, and swapping him for
        // himself would rush three.
        guard let dropping = coming.last(where: { position(at: $0) == .defensiveTackle }),
            let replacing = linebackers.first(where: { !coming.contains($0) })
        else { return Rush(rushers: coming) }
        coming.removeAll { $0 == dropping }
        coming.append(replacing)
        return Rush(rushers: coming, dropping: dropping)
    }

    /// Who stays in to block, and which eligible the offence kept.
    public struct Protection: Sendable, Hashable {

        /// Everyone protecting, in the order the rush is picked up: the line, and behind
        /// it the man kept in.
        public var protectors: [PlayerSlot]

        /// The eligible kept in to take the man the line has nobody for — and therefore
        /// not running a route. `.none` when the line had it covered, or when the set was
        /// empty and there was nobody to keep.
        public var keptIn: PlayerSlot

        public init(protectors: [PlayerSlot], keptIn: PlayerSlot = .none) {
            self.protectors = protectors
            self.keptIn = keptIn
        }
    }

    /// The five linemen, and behind them whoever stays in for the man they have nobody
    /// for.
    ///
    /// Five rushers are five bodies the five linemen take one each, so nobody has to stay
    /// and the back is free to run his route; a sixth is a man the line cannot reach, and
    /// a back stays in to take him. An empty set has nobody to keep and wears the free
    /// rusher, which is the trade that grouping makes.
    ///
    /// The back first because he is already behind the line, then a fullback, then a tight
    /// end. **Coaching convention, and there is no article behind it** — see the note
    /// above this section.
    public func protection(against rushers: Int) -> Protection {
        let line = blockers(includingEligibles: false)
        guard rushers > line.count else { return Protection(protectors: line) }
        let backfield = slots(in: 1..<6) { $0 == .runningBack || $0 == .fullback }
        guard let keptIn = backfield.first ?? slots(in: 1..<6, matching: { $0 == .tightEnd }).last
        else { return Protection(protectors: line) }
        return Protection(protectors: line + [keptIn], keptIn: keptIn)
    }

    /// Everyone left in coverage once the rush has gone.
    ///
    /// The men sent come out — a linebacker blitzing is a linebacker not covering, and
    /// that is the whole cost of the call — and the lineman who dropped goes in, last,
    /// because a lineman in space is the worst cover man on the field and the man he ends
    /// up on is the last read.
    public func coverageDefenders(after rush: Rush) -> [PlayerSlot] {
        let sent = Set(rush.rushers)
        var covering = coverageDefenders.filter { !sent.contains($0) }
        if !rush.dropping.isNone { covering.append(rush.dropping) }
        return covering
    }

    /// The men with a deep zone, of those left in coverage.
    ///
    /// **How many** is the shell's own, and `Coverage` states each one where the case is
    /// declared: cover three is three deep and four under, cover two is two deep and five
    /// under, quarters is four deep and three under, and prevent is deep everything. A
    /// run blitz is nobody's zone at all and a man call has no zones to give out.
    ///
    /// **Which men** the crude engine cannot say, because it has no alignment: nothing
    /// here knows that the corners take the outside thirds of a three-deep and the free
    /// safety the middle. So they go to the men who align deepest — the safeties, then
    /// the corners, then whoever is left off the ball — and everyone the count does not
    /// reach is underneath, which is the flat. That ordering is a convention of this
    /// engine and no article is behind it; the spatial engine places bodies and decides
    /// it properly.
    ///
    /// Written as a switch with no `default`, so a coverage added to the enum has to
    /// answer this rather than silently playing no deep zones.
    public func deepZoneDefenders(
        under coverage: Coverage, among covering: [PlayerSlot]
    )
        -> Set<PlayerSlot>
    {
        let zones: Int
        switch coverage {
        case .coverZero, .manFree, .twoMan, .runBlitz: zones = 0
        case .coverTwo: zones = 2
        case .coverThree: zones = 3
        case .quarters, .matchQuarters, .prevent: zones = 4
        }
        guard zones > 0 else { return [] }
        let deepest =
            covering.filter { position(at: $0) == .safety }
            + covering.filter { position(at: $0) == .cornerback }
            + covering.filter { position(at: $0) == .linebacker }
        return Set(deepest.prefix(zones))
    }

    /// The men in the box, front first: the ones a run has to get through.
    public var boxDefenders: [PlayerSlot] {
        front + slots(in: 11..<22) { $0 == .linebacker }
    }

    /// Defenders committed to the run rather than to a receiver.
    ///
    /// The number that decides whether a run has anywhere to go: eight in a goal-line
    /// defence, seven in base, six in nickel, five in dime.
    public var boxCount: Int {
        slots(in: 11..<22) { $0 == .edge || $0 == .defensiveTackle || $0 == .linebacker }.count
    }
}

/// The slot each position occupies in the crude engine's personnel.
///
/// Eleven and eleven, in a shape close to modern base personnel: three receivers and a
/// tight end against nickel. The spatial engine will place bodies by formation; this is
/// the smallest arrangement that lets a matchup have two named sides.
enum SlotLayout {

    /// The five linemen, who are the same five whatever the offence sends out.
    static let line: [(Position, Int)] = [
        (.leftTackle, 6), (.leftGuard, 7), (.center, 8), (.rightGuard, 9), (.rightTackle, 10),
    ]

    /// Who the offence has on the field for a given personnel grouping.
    ///
    /// Slot 0 is the quarterback, 1 is the featured back, 2 through 5 are the eligible
    /// receivers, and 6 through 10 are the line. The *slots* are stable and the
    /// *positions* filling them are not, which is what lets the rest of the engine go on
    /// talking about "the receivers" and "the blockers" while the personnel underneath
    /// changes.
    ///
    /// Every snap of every game used to be eleven personnel. `PersonnelGroup` was a
    /// complete, tested type in `FMCore` that nothing in the engine ever set, so the
    /// heavy grouping a team runs at the goal line and the empty set it throws from on
    /// third and long were both simply absent.
    static func offense(_ group: PersonnelGroup) -> [(Position, Int)] {
        var layout: [(Position, Int)] = [(.quarterback, 0)]

        // The eligibles, filled from the outside in: receivers take the wide slots, tight
        // ends the inside ones, and a second back is the last man on.
        var eligible = [1, 2, 3, 4, 5]
        layout.append(
            (group.runningBacks > 0 ? .runningBack : .wideReceiver, eligible.removeFirst()))

        for _ in 0..<Int(group.wideReceivers) where !eligible.isEmpty {
            layout.append((.wideReceiver, eligible.removeFirst()))
        }
        for _ in 0..<Int(group.tightEnds) where !eligible.isEmpty {
            layout.append((.tightEnd, eligible.removeLast()))
        }
        // A second back is a fullback in a heavy set: he is a blocker who happens to be
        // eligible, which is the whole reason the grouping exists.
        for _ in 1..<max(1, Int(group.runningBacks)) where !eligible.isEmpty {
            layout.append((.fullback, eligible.removeLast()))
        }
        while let slot = eligible.first {
            eligible.removeFirst()
            layout.append((.wideReceiver, slot))
        }

        return layout + line
    }

    /// Who the defence answers with.
    ///
    /// Slots 11 to 14 are the front, 15 to 17 the off-ball defenders, and 18 to 21 the
    /// secondary — again stable as *slots*, so the pursuit and coverage lists keep
    /// meaning what they say while the bodies change. A package is named for its
    /// defensive back count, and swapping a linebacker for a nickel back is the single
    /// most common substitution in the sport.
    ///
    /// Note what the old fixed layout actually was: two edges, two tackles, *two*
    /// linebackers and *three* corners. That is nickel. The engine played nickel on every
    /// snap of every game and called it base, so a goal-line stand had five defensive
    /// backs on the field and third and fifteen had no extra one.
    static func defense(_ package: DefensivePackage) -> [(Position, Int)] {
        switch package {
        case .base:
            return [
                (.edge, 11), (.edge, 12), (.defensiveTackle, 13), (.defensiveTackle, 14),
                (.linebacker, 15), (.linebacker, 16), (.linebacker, 17),
                (.cornerback, 18), (.cornerback, 19), (.safety, 20), (.safety, 21),
            ]
        case .nickel:
            return [
                (.edge, 11), (.edge, 12), (.defensiveTackle, 13), (.defensiveTackle, 14),
                (.linebacker, 15), (.linebacker, 16),
                (.cornerback, 17), (.cornerback, 18), (.cornerback, 19),
                (.safety, 20), (.safety, 21),
            ]
        case .dime:
            return [
                (.edge, 11), (.edge, 12), (.defensiveTackle, 13), (.defensiveTackle, 14),
                (.linebacker, 15),
                (.cornerback, 16), (.cornerback, 17), (.cornerback, 18), (.cornerback, 19),
                (.safety, 20), (.safety, 21),
            ]
        case .quarter, .prevent:
            // Three down, one off-ball, and everybody else in coverage. Prevent is the
            // same personnel playing deeper, which is a coverage call rather than a
            // different eleven.
            return [
                (.edge, 11), (.edge, 12), (.defensiveTackle, 13),
                (.linebacker, 14),
                (.cornerback, 15), (.cornerback, 16), (.cornerback, 17), (.cornerback, 18),
                (.safety, 19), (.safety, 20), (.safety, 21),
            ]
        case .goalLine:
            // Five down linemen and three off-ball, because there is no field behind them
            // to defend and every yard is the whole play.
            return [
                (.edge, 11), (.edge, 12), (.defensiveTackle, 13), (.defensiveTackle, 14),
                (.defensiveTackle, 15),
                (.linebacker, 16), (.linebacker, 17), (.linebacker, 18),
                (.cornerback, 19), (.safety, 20), (.safety, 21),
            ]
        }
    }

    static let blockers: [PlayerSlot] = [
        PlayerSlot(6), PlayerSlot(7), PlayerSlot(8), PlayerSlot(9), PlayerSlot(10),
    ]
    static let rushers: [PlayerSlot] = [
        PlayerSlot(11), PlayerSlot(12), PlayerSlot(13), PlayerSlot(14),
    ]
    static let receivers: [PlayerSlot] = [
        PlayerSlot(2), PlayerSlot(3), PlayerSlot(4), PlayerSlot(5), PlayerSlot(1),
    ]
    static let coverage: [PlayerSlot] = [
        PlayerSlot(17), PlayerSlot(18), PlayerSlot(19), PlayerSlot(20), PlayerSlot(21),
        PlayerSlot(15), PlayerSlot(16),
    ]
    /// The kicking unit, for the snaps the offence's eleven do not take.
    ///
    /// Rosters have carried a kicker, a punter and a long snapper since world generation
    /// existed, and none of them had ever been on the field: the kicking code read
    /// `.kickAccuracy` and `.puntPower` off slot 0 and got the *quarterback's*. So a
    /// team's kicker was irrelevant to whether it made kicks, and no specialist could
    /// take a snap, be credited, or get hurt.
    ///
    /// Slot 0 is the snap's principal — the quarterback on a play from scrimmage, the
    /// specialist on a kick — which keeps one eleven-slot arrangement rather than a
    /// second parallel one. The spatial engine places bodies by formation and this
    /// arrangement goes away with it.
    static let fieldGoalUnit: [(Position, Int)] = [
        (.kicker, 0), (.longSnapper, 8),
        (.leftTackle, 6), (.leftGuard, 7), (.rightGuard, 9), (.rightTackle, 10),
        (.tightEnd, 5), (.tightEnd, 4), (.fullback, 3), (.runningBack, 2), (.runningBack, 1),
    ]

    static let puntUnit: [(Position, Int)] = [
        (.punter, 0), (.longSnapper, 8),
        (.leftTackle, 6), (.leftGuard, 7), (.rightGuard, 9), (.rightTackle, 10),
        (.tightEnd, 5), (.fullback, 4),
        // Gunners, who are the fastest men the team can spare.
        (.wideReceiver, 2), (.wideReceiver, 3), (.runningBack, 1),
    ]

    static let kickoffUnit: [(Position, Int)] = [
        (.kicker, 0),
        (.linebacker, 1), (.linebacker, 2), (.safety, 3), (.safety, 4),
        (.cornerback, 5), (.cornerback, 6), (.tightEnd, 7),
        (.fullback, 9), (.runningBack, 10), (.wideReceiver, 8),
    ]

    /// The eleven facing a kick. Cover men and backs rather than a front seven.
    static let returnUnit: [(Position, Int)] = [
        (.linebacker, 11), (.linebacker, 12), (.edge, 13), (.edge, 14),
        (.safety, 15), (.safety, 16),
        (.cornerback, 17), (.cornerback, 18), (.cornerback, 19),
        (.runningBack, 20), (.wideReceiver, 21),
    ]

    /// Who has an angle on the ball carrier, and how likely each is to be the one who
    /// gets there.
    ///
    /// This was `coverage.prefix(3)` for every kind of play — the three cornerbacks — so
    /// a run up the middle was tackled by a corner and a linebacker never made a tackle
    /// all season. It is a weighted draw rather than a queue because a fixed order gives
    /// the first man in the list nine tackles in ten: pursuit depends on where the ball
    /// actually went, which a crude engine cannot see, so the spread stands in for it.
    static let insideRunPursuit: [(PlayerSlot, Double)] = [
        (PlayerSlot(15), 4), (PlayerSlot(16), 4),
        (PlayerSlot(13), 3), (PlayerSlot(14), 3),
        (PlayerSlot(11), 2), (PlayerSlot(12), 2),
        (PlayerSlot(20), 1), (PlayerSlot(21), 1),
    ]

    /// Outside, the edge sets it, the second level runs to it, and a safety is the last
    /// man before the sideline.
    static let outsideRunPursuit: [(PlayerSlot, Double)] = [
        (PlayerSlot(11), 3), (PlayerSlot(12), 3),
        (PlayerSlot(15), 3), (PlayerSlot(16), 3),
        (PlayerSlot(20), 2), (PlayerSlot(21), 2),
        (PlayerSlot(17), 1), (PlayerSlot(18), 1),
    ]

    /// A scramble is a run the front is late to, because they were rushing the passer.
    static let scramblePursuit: [(PlayerSlot, Double)] = [
        (PlayerSlot(15), 3), (PlayerSlot(16), 3),
        (PlayerSlot(20), 2), (PlayerSlot(21), 2),
        (PlayerSlot(11), 1), (PlayerSlot(12), 1),
    ]

    /// After a catch, the help behind whoever was covering him. The covering man himself
    /// is added at the call site, weighted heavily — he is right there.
    static let catchPursuit: [(PlayerSlot, Double)] = [
        (PlayerSlot(20), 2), (PlayerSlot(21), 2),
        (PlayerSlot(15), 1), (PlayerSlot(16), 1),
        (PlayerSlot(17), 1), (PlayerSlot(18), 1), (PlayerSlot(19), 1),
    ]

    /// The man back to field a kick, and the second one beside him. Both sit in the
    /// return unit's defensive slots, because on a kick the *kicking* team has
    /// possession — the returner is on the side that does not.
    static let returner = PlayerSlot(21)
    static let secondReturner = PlayerSlot(20)

    /// The coverage team running down to meet him.
    static let coverageUnit: [(PlayerSlot, Double)] = [
        (PlayerSlot(1), 2), (PlayerSlot(2), 2), (PlayerSlot(3), 2), (PlayerSlot(4), 2),
        (PlayerSlot(5), 2), (PlayerSlot(6), 1), (PlayerSlot(7), 1),
    ]

    static let quarterback = PlayerSlot(0)
    static let back = PlayerSlot(1)
    /// Slot 0 again, named for what sits there on a kick. Reading `quarterback` in the
    /// kicking game is how the specialists went missing in the first place.
    static let specialist = PlayerSlot(0)
}

extension PlayConcept {

    /// The unit the offence sends out for this concept.
    ///
    /// A kick is not eleven starters plus a placeholder for the ball: it is a different
    /// eleven, and the crude engine had only ever fielded the one. Here rather than in
    /// `FMCore` because the slots are this engine's arrangement, and the spatial engine
    /// places bodies by formation.
    ///
    /// **Written as a switch over every case with no `default`, deliberately.** A kicking
    /// concept that falls through to the scrimmage layout puts the wrong eleven on the
    /// field and says nothing about it, and the snap counts then record a kickoff as a
    /// snap for the starting offence. An exhaustive switch turns the next concept added
    /// into a build failure here instead.
    func offenseLayout(_ group: PersonnelGroup) -> [(Position, Int)] {
        switch self {
        case .punt: return SlotLayout.puntUnit
        case .fieldGoal, .extraPoint: return SlotLayout.fieldGoalUnit
        case .kickoff, .onsideKick, .deepKickoff: return SlotLayout.kickoffUnit
        case .insideRun, .outsideRun, .quickPass, .mediumPass, .deepPass, .screen,
            .playAction, .kneel, .spike, .twoPointPass, .twoPointRun:
            return SlotLayout.offense(group)
        }
    }

    /// The return side. A crude engine does not model a return, but the men who have to
    /// be out there still take the snap — a punt is a play eleven of them were on the
    /// field for, and their snap counts should say so.
    ///
    /// Exhaustive for the same reason as the offence side above.
    func defenseLayout(_ package: DefensivePackage) -> [(Position, Int)] {
        switch self {
        case .punt, .fieldGoal, .extraPoint, .kickoff, .onsideKick, .deepKickoff:
            return SlotLayout.returnUnit
        case .insideRun, .outsideRun, .quickPass, .mediumPass, .deepPass, .screen,
            .playAction, .kneel, .spike, .twoPointPass, .twoPointRun:
            return SlotLayout.defense(package)
        }
    }
}

extension Lineup {

    /// Fill the field from both rotations.
    ///
    /// Who plays is drawn against each man's snap share, so a starter is usually out
    /// there and his backup sometimes is. Over a season that is what makes snap counts
    /// and backup statistics real rather than a starter taking everything.
    static func onField(
        _ context: PlayContext, concept: PlayConcept, situation: Situation,
        random: inout SplittableRandom
    ) -> Lineup {
        var personnel = Lineup()
        fill(
            &personnel, layout: concept.offenseLayout(situation.offensePersonnel),
            from: context.offenseRotation, players: context.players, random: &random)
        fill(
            &personnel, layout: concept.defenseLayout(situation.defensePackage),
            from: context.defenseRotation, players: context.players, random: &random)
        return personnel
    }

    private static func fill(
        _ personnel: inout Lineup,
        layout: [(Position, Int)],
        from rotation: [DepthChart.Rotation],
        players: [PlayerID: Player],
        random: inout SplittableRandom
    ) {
        var used: Set<PlayerID> = []

        for (position, slot) in layout {
            var candidates = rotation.filter {
                $0.position == position && !used.contains($0.player)
            }
            if candidates.isEmpty {
                // Nobody left who plays there. A safety lines up at corner, a guard slides
                // to tackle, and the game goes on — which is what `secondaryPositions` is
                // for, and it had never been read by anything. Without this the slot
                // simply stayed empty and the team played a man short, silently.
                candidates = rotation.filter { rotation in
                    guard !used.contains(rotation.player) else { return false }
                    return players[rotation.player]?.secondaryPositions.contains(position) == true
                }
            }
            guard !candidates.isEmpty else { continue }

            let chosen: DepthChart.Rotation
            switch RotationProfile.kind(for: position) {
            case .starterOnly:
                // No draw at all: the man highest on the chart who is still available
                // takes it. The quarterback, the five line spots and the specialists come
                // off for an injury and for nothing else, and drawing them against a share
                // made the backup's share a per-snap chance — a substitution mid-drive,
                // undone on the next snap, with the starter perfectly fit.
                chosen = candidates.min { $0.depth < $1.depth } ?? candidates[0]
            case .rotates:
                // Weighted by snap share, so the man who plays most usually plays. A
                // depleted group falls through to whoever is left, which is the point of
                // next-man-up.
                let weights = candidates.map { max(0.01, $0.snapShare) }
                let index = random.weightedIndex(weights) ?? 0
                chosen = candidates[index]
            }
            used.insert(chosen.player)
            personnel.place(chosen.player, position: position, at: slot)
        }
    }
}
