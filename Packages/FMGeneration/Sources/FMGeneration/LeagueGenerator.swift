import FMCore
import FMRandom

/// Assembles a league: teams, and the structure holding them.
public enum LeagueGenerator {

    /// Everything a generated league is made of.
    ///
    /// Teams are returned alongside the structure rather than inside it: `League` holds
    /// membership as identifiers so a division cannot disagree with a team about which
    /// division it is in, and the teams themselves live wherever the world keeps them.
    public struct GeneratedLeague: Sendable {
        public let league: League
        public let teams: [Team]

        public func team(_ id: TeamID) -> Team? {
            teams.first { $0.id == id }
        }
    }

    /// Why a league could not be generated.
    ///
    /// Two cases rather than one, because they are different mistakes: an impossible
    /// shape is the caller's, and a league that does not match a legal shape is the
    /// generator's. The second should be unreachable — it is checked anyway, so a
    /// future change cannot quietly hand back a league with a short division.
    public enum GenerationFailure: Error, Sendable, Hashable {
        case invalidShape(InvalidLeagueShape)
        case malformedLeague([League.StructureFailure])

        public var explanations: [String] {
            switch self {
            case .invalidShape(let error): return error.failures.map(\.explanation)
            case .malformedLeague(let failures): return failures.map(\.explanation)
            }
        }
    }

    /// Build a league to a shape.
    ///
    /// The shape is validated first and the failure is thrown back rather than
    /// generated around: a league built to an impossible shape breaks at the schedule,
    /// far from the mistake ([decision 107](../../../../docs/design-decisions.md)).
    ///
    /// - Parameters:
    ///   - shape: the league's structure.
    ///   - franchises: where the clubs come from. The curated thirty-two by default;
    ///     `.randomised` for the pool draw ([decision 215](../../../../docs/design-decisions.md)).
    ///   - random: the league's substream.
    /// - Returns: the league and its teams, or the reason the shape is not a league.
    public static func league(
        shape: LeagueShape = .standard,
        franchises: FranchiseSource = .curated,
        using random: inout SplittableRandom
    ) -> Result<GeneratedLeague, GenerationFailure> {
        let failures = shape.validationFailures
        guard failures.isEmpty else {
            return .failure(.invalidShape(InvalidLeagueShape(failures)))
        }

        // Divisions are regional where the shape allows it, which is what makes a
        // league look drawn rather than dealt — and what lets a rivalry be geographic
        // later. Each division index maps to a region, and every conference fields one
        // division per region, exactly as the real structure does.
        let regions = Region.allCases
        let isRegional = shape.divisionsPerConference <= regions.count

        // Demand is computed before anything is generated: a two-division conference
        // draws from two regions, so an even spread across four would leave both short.
        var demand: [Region: Int] = [:]
        for divisionIndex in 0..<shape.divisionsPerConference {
            let region = regions[divisionIndex % regions.count]
            demand[region, default: 0] += shape.conferences * shape.teamsPerDivision
        }

        // Sorted so generation order — and therefore the whole world — is stable.
        let orderedRegions = regions.sorted { $0.rawValue < $1.rawValue }
        var ledger = TeamGenerator.NameLedger()
        var pools: [Region: [Franchise]] = [:]

        // Two passes, and the order matters: every curated name in the *league* is in
        // the ledger before a single franchise is drawn, so a region topped up from the
        // pools cannot draw a nickname another region was handed. One pass would give
        // the north's top-up only the north's curated names.
        let curated = franchises.franchises
        for region in orderedRegions {
            guard let count = demand[region], count > 0 else { continue }
            let take = Array(curated.lazy.filter { $0.region == region }.prefix(count))
            for franchise in take { ledger.record(franchise) }
            pools[region] = take
        }
        for region in orderedRegions {
            guard let count = demand[region], count > 0 else { continue }
            let short = count - (pools[region]?.count ?? 0)
            guard short > 0 else { continue }
            // A shape that wants more of a region than the curated set holds. Nothing
            // ships at that size; a sixty-four team league is a thing a tool can ask for,
            // and refusing it outright would be worse than finishing it from the pools.
            pools[region, default: []] += TeamGenerator.franchises(
                in: region, count: short, ledger: &ledger, using: &random)
        }

        var identifiers = IdentifierSequence<TeamSubject>()
        var teams: [Team] = []
        teams.reserveCapacity(shape.totalTeams)

        var conferenceIDs = IdentifierSequence<ConferenceSubject>()
        var divisionIDs = IdentifierSequence<DivisionSubject>()
        var conferences: [Conference] = []

        let conferenceNames = names(
            StructurePools.conferenceNames, count: shape.conferences, fallback: "Conference")

        // How far into each region's pool the deal has got. From the front, so the file
        // order of `FranchiseSet` is the order a franchise joins the league: a league
        // smaller than thirty-two takes the top of each region rather than its tail.
        var dealt: [Region: Int] = [:]

        for conferenceIndex in 0..<shape.conferences {
            var divisions: [Division] = []
            for divisionIndex in 0..<shape.divisionsPerConference {
                let region = regions[divisionIndex % regions.count]
                var members: [TeamID] = []

                for _ in 0..<shape.teamsPerDivision {
                    let next = dealt[region, default: 0]
                    guard let pool = pools[region], next < pool.count else { continue }
                    dealt[region] = next + 1
                    let team = TeamGenerator.team(
                        id: identifiers.allocate(), franchise: pool[next], using: &random)
                    teams.append(team)
                    members.append(team.id)
                }

                divisions.append(
                    Division(
                        id: divisionIDs.allocate(),
                        name: divisionName(
                            index: divisionIndex, region: region, isRegional: isRegional),
                        teams: members))
            }
            conferences.append(
                Conference(
                    id: conferenceIDs.allocate(), name: conferenceNames[conferenceIndex],
                    divisions: divisions))
        }

        let league = League(
            id: LeagueID(1),
            name: StructurePools.leagueNames[
                Int(random.next(upperBound: UInt64(StructurePools.leagueNames.count)))],
            shape: shape,
            conferences: conferences)

        // The generator computes its city demand from the shape, so this should always
        // pass. Checking it means a change to that arithmetic surfaces here rather than
        // as a broken schedule several systems downstream.
        let structureFailures = league.structureFailures
        guard structureFailures.isEmpty else {
            return .failure(.malformedLeague(structureFailures))
        }

        return .success(GeneratedLeague(league: league, teams: teams))
    }

    /// A division is named for the region it holds, so "South" is not full of cities
    /// with hard winters. Past four divisions a conference has more divisions than the
    /// world has regions, so the thematic pool takes over and the name stops claiming
    /// anything geographic.
    private static func divisionName(index: Int, region: Region, isRegional: Bool) -> String {
        guard isRegional else {
            return index < StructurePools.divisionNames.count
                ? StructurePools.divisionNames[index] : "Division \(index + 1)"
        }
        switch region {
        case .north: return "North"
        case .south: return "South"
        case .east: return "East"
        case .west: return "West"
        }
    }

    /// Names for a set of conferences, numbered past the end of the pool.
    ///
    /// A league with nine divisions is a legal shape, and it is better to have a
    /// "Division 9" than to reuse a name and make two of them indistinguishable.
    private static func names(_ pool: [String], count: Int, fallback: String) -> [String] {
        (0..<count).map { index in
            index < pool.count ? pool[index] : "\(fallback) \(index + 1)"
        }
    }
}
