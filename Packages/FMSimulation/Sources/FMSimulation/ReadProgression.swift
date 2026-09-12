import FMCore

/// The crude resolver's read order for a pass family: who the quarterback works, in what
/// order, when each read is judged, and how deep the ball goes if it goes there.
///
/// **Authored coaching design, and stated as such.** A read progression is not in the
/// rulebook and it is not a rate, so CLAUDE.md's rule 10 has nothing for it to cite. It is
/// an input the passer then succeeds or fails at working — the same kind of thing as the
/// caller's run shares and the pocket's arrival window, and it is registered where those
/// are: under *Pass play* in `docs/match-engine.md`, and under *What a test claims about a
/// game and nothing sources* in `docs/reference/calibration-sources.md`. What it produces
/// is graded by sourced rows; the table itself is pinned, not asserted as football.
/// Decided on C27 (#169) and consumed by C3 (#44).
///
/// **The two anchoring rules.** The hold each family had before the table existed is the
/// last numbered read's break, and earlier reads break earlier; the depth each family had
/// is the first numbered read's depth. So the ball can only come out earlier than it did,
/// never later, and `row:pressureRate` can only fall, bounded by the share of snaps that
/// end on the first read.
///
/// **Lifetime.** Keyed by this engine's slots, for the reason `SlotLayout` gives for living
/// here, and deleted with the crude resolver at M5, whose reads come from a design's
/// assignments and whose timing comes from route geometry. M6's premade library is where
/// the five orders below are reused: the decision that the quick game starts at the third
/// receiver and play action at the tight end is what the first design in each family says.
///
/// The concept stays route-free — a play format with routes in it does not retire
/// `PlayConcept`, as its own doc says — which is why this is not on the concept.
struct ReadProgression: Sendable, Hashable {

    /// Who a read is, in the roles the crude engine's personnel can name. There is no left
    /// and no right: the slot layout fills receivers outside in, so the first receiver is
    /// the first wide-receiver slot on the field and so on down.
    enum Role: UInt8, CaseIterable, Sendable, Hashable {
        case firstReceiver = 0
        case secondReceiver = 1
        case thirdReceiver = 2
        case tightEnd = 3
        case back = 4
    }

    /// One numbered read.
    struct Read: Sendable, Hashable {
        let role: Role
        /// When the passer judges this read, in milliseconds from the snap: the break of
        /// the route it is on, which is where separation is created and when the ball has
        /// to be out. Non-decreasing along `reads`; the last is the family's hold.
        let breakMillis: Int
        /// Where the ball is caught if thrown here. Flight and the accuracy key derive
        /// from it, and the resolver's existing spread is applied around it.
        let depthYards: Int
    }

    /// The escape valve: a role and a depth, and no break, because it has no place in the
    /// sequence — it is the look after the numbered reads are done with, wherever the rush
    /// or the deadline finds the passer.
    struct Checkdown: Sendable, Hashable {
        let role: Role
        let depthYards: Int
    }

    /// Worked in order.
    let reads: [Read]
    let checkdown: Checkdown?

    /// How long the family holds the ball at most: the last numbered read's break.
    var holdMillis: Int { reads.last?.breakMillis ?? 0 }

    /// A play with no reads in it. Never a pass family's; what a concept that is not a
    /// dropback gets when asked, so that the table is total and nothing has to guess.
    static let none = ReadProgression(reads: [], checkdown: nil)

    /// The five families, as authored, and the try, which inherits the quick game's order.
    ///
    /// The orders are the design; the break times and depths are starting values in the
    /// sense of C3's parameters, retuned in E3 (#49) and not before. Both anchoring rules
    /// hold in every row, and `ReadProgressionTests` pins them.
    ///
    /// Exhaustive with no `default`, deliberately: a concept that is not a dropback gets an
    /// empty progression rather than another family's, and the next concept added fails to
    /// build here rather than borrowing one.
    static func of(_ concept: PlayConcept) -> ReadProgression {
        switch concept {
        case .screen:
            // The screen is the back, and nothing else: a covered screen is a throwaway,
            // or a sack if the pocket has gone.
            return ReadProgression(
                reads: [Read(role: .back, breakMillis: 1_400, depthYards: -1)], checkdown: nil)
        case .quickPass:
            // Three-step timing, starting at the third receiver — the slot, in a real
            // design — and never further than the tight end.
            return ReadProgression(
                reads: [
                    Read(role: .thirdReceiver, breakMillis: 1_400, depthYards: 4),
                    Read(role: .firstReceiver, breakMillis: 1_600, depthYards: 6),
                    Read(role: .tightEnd, breakMillis: 1_700, depthYards: 5),
                ],
                checkdown: Checkdown(role: .back, depthYards: 2))
        case .mediumPass:
            return ReadProgression(
                reads: [
                    Read(role: .secondReceiver, breakMillis: 2_000, depthYards: 10),
                    Read(role: .firstReceiver, breakMillis: 2_300, depthYards: 14),
                    Read(role: .tightEnd, breakMillis: 2_600, depthYards: 8),
                ],
                checkdown: Checkdown(role: .back, depthYards: 3))
        case .playAction:
            // Sells the run first, so the first read is the tight end coming across
            // behind the fake and the shot downfield is the second.
            return ReadProgression(
                reads: [
                    Read(role: .tightEnd, breakMillis: 2_400, depthYards: 12),
                    Read(role: .firstReceiver, breakMillis: 2_800, depthYards: 22),
                    Read(role: .secondReceiver, breakMillis: 3_000, depthYards: 14),
                ],
                checkdown: Checkdown(role: .back, depthYards: 3))
        case .deepPass:
            return ReadProgression(
                reads: [
                    Read(role: .firstReceiver, breakMillis: 2_600, depthYards: 20),
                    Read(role: .secondReceiver, breakMillis: 3_000, depthYards: 18),
                    Read(role: .tightEnd, breakMillis: 3_400, depthYards: 12),
                ],
                checkdown: Checkdown(role: .back, depthYards: 3))
        case .twoPointPass:
            // A throw into a phone booth from the two: the quick game's order, every read
            // a yard deep and judged at the try's hold, which is what the try resolved as
            // before the table existed. The separation scaling that makes it a
            // conversion rather than a completion is the resolver's.
            return ReadProgression(
                reads: [
                    Read(role: .thirdReceiver, breakMillis: 1_500, depthYards: 1),
                    Read(role: .firstReceiver, breakMillis: 1_500, depthYards: 1),
                    Read(role: .tightEnd, breakMillis: 1_500, depthYards: 1),
                ],
                checkdown: Checkdown(role: .back, depthYards: 1))
        case .insideRun, .outsideRun, .punt, .fieldGoal, .kneel, .spike, .kickoff,
            .extraPoint, .onsideKick, .twoPointRun, .deepKickoff:
            return .none
        }
    }

    // MARK: - What a depth decides

    /// The three widths of throw the passer's accuracy is rated in, and the three
    /// thresholds his perceived window is judged against (C3, #44).
    enum DepthClass: Sendable, Hashable {
        case short, medium, deep
    }

    /// Short is inside eight yards, deep is sixteen and beyond, and the families' own
    /// depths sit where they always did: a quick game's four is short, a medium concept's
    /// ten and play action's twelve are medium, a deep drop's twenty is deep.
    static func depthClass(ofYards depth: Int) -> DepthClass {
        if depth < 8 { return .short }
        if depth < 16 { return .medium }
        return .deep
    }

    /// Which accuracy the throw is rated on.
    static func accuracyKey(forDepth depth: Int) -> RatingKey {
        switch depthClass(ofYards: depth) {
        case .short: return .throwAccuracyShort
        case .medium: return .throwAccuracyMedium
        case .deep: return .throwAccuracyDeep
        }
    }

    /// How long the ball is in the air, in the record's ticks: half a tick a yard past
    /// four, with a floor of three for anything thrown behind the line. The five pairs
    /// `routeDepth` used to hold — three ticks at minus one, four at four, seven at ten,
    /// eight at twelve, twelve at twenty — are this function's fixed points, and
    /// `ReadProgressionTests` says so.
    static func flightTicks(forDepth depth: Int) -> Int {
        max(3, 4 + (depth - 4) / 2)
    }

    // MARK: - Who fills a role on this snap

    /// The slot each numbered read resolves to on the field as it stands, in the order the
    /// passer works them. A role nobody fills is skipped and the order closes up, which is
    /// why a read point's index is its place in the order *as worked* rather than in the
    /// table.
    ///
    /// `runners` is `lineup.routeRunners()`, passed in by a caller that has already read
    /// it — the resolver's coverage loop has — so the order is built once a snap.
    func resolvedReads(
        in lineup: Lineup, runners: [PlayerSlot]? = nil
    ) -> [(read: Read, receiver: PlayerSlot)] {
        let runners = runners ?? lineup.routeRunners()
        return reads.compactMap { read in
            read.role.slot(among: runners, in: lineup).map { (read, $0) }
        }
    }

    /// The checkdown's man, when the family has one and the grouping fielded him.
    func resolvedCheckdown(
        in lineup: Lineup, runners: [PlayerSlot]? = nil
    ) -> (checkdown: Checkdown, receiver: PlayerSlot)? {
        guard let checkdown,
            let slot = checkdown.role.slot(among: runners ?? lineup.routeRunners(), in: lineup)
        else { return nil }
        return (checkdown, slot)
    }
}

extension ReadProgression.Role {

    /// The slot filling this role, or `nil` when the grouping on the field has nobody in
    /// it: the third receiver in twelve personnel, the tight end in an empty set.
    ///
    /// Read off `Lineup.routeRunners()`, which is the order the coverage matches, so a
    /// read and its matchup name the same man.
    func slot(in lineup: Lineup) -> PlayerSlot? {
        slot(among: lineup.routeRunners(), in: lineup)
    }

    /// The same, given the route runners already read off the lineup — once per snap
    /// rather than once per role, since the order is what every role is read against.
    func slot(among runners: [PlayerSlot], in lineup: Lineup) -> PlayerSlot? {
        let receivers = runners.filter { lineup.position(at: $0) == .wideReceiver }
        switch self {
        case .firstReceiver: return receivers.count > 0 ? receivers[0] : nil
        case .secondReceiver: return receivers.count > 1 ? receivers[1] : nil
        case .thirdReceiver: return receivers.count > 2 ? receivers[2] : nil
        case .tightEnd: return runners.first { lineup.position(at: $0) == .tightEnd }
        case .back:
            // A fullback is the back only when there is no running back to be one.
            return runners.first { lineup.position(at: $0) == .runningBack }
                ?? runners.first { lineup.position(at: $0) == .fullback }
        }
    }
}
