/// How far through college a prospect is.
public enum CollegeYear: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case freshman = 0
    case sophomore = 1
    case junior = 2
    case senior = 3

    public var next: CollegeYear? { CollegeYear(rawValue: rawValue + 1) }

    /// Underclassmen have a choice about entering the draft; seniors do not.
    public var mayReturnToSchool: Bool { self != .senior }
}

/// Whether a prospect is in this year's class.
public enum Declaration: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// Eligible, but has not come out. Next year he is a different prospect: a season
    /// older, with another year of tape, and a stock that has moved either way.
    case returning = 0
    case declared = 1
    /// Out of eligibility. The decision was never his.
    case automatic = 2
    /// Too early to be asked. A sophomore is not weighing anything yet, and reporting
    /// him as "not entering" would read as a decision he has not made.
    case notYetEligible = 3

    public var isInThisClass: Bool { self == .declared || self == .automatic }

    /// Whether the choice is live this year.
    public var isDecided: Bool { self != .notYetEligible }
}

/// A concern that moves boards once anybody finds out.
///
/// Deliberately **football-professional**: everything here is about the job. The game
/// invents people, and inventing conduct allegations about them would buy a slightly
/// more realistic draft broadcast at a cost the rest of the design is not willing to
/// pay ([decision 160](../../../../docs/design-decisions.md)). Medical is the other
/// half, and it is the one that produces the classic late slide.
public enum RedFlagKind: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case knee = 0
    case shoulder = 1
    case back = 2
    case concussionHistory = 3
    case chronicSoftTissue = 4
    /// Does not put in the work when nobody is watching.
    case workEthic = 20
    /// Argues with coaching rather than absorbing it.
    case coachability = 21
    /// Wins on ability and has never had to learn the details.
    case filmStudy = 22
    /// Handles adversity badly — a bad quarter becomes a bad game.
    case maturity = 23
    /// Wants his own role more than the team's scheme.
    case schemeBuyIn = 24

    public var isMedical: Bool { rawValue < 20 }
}

/// One flag on one prospect.
///
/// `severity` is truth and `visibility` is how hard it is to find. The pairing is the
/// whole point: a serious concern nobody has surfaced is what makes a player slide on
/// draft day for a reason that only becomes knowable later.
public struct RedFlag: Sendable, Hashable, Codable {

    public let kind: RedFlagKind
    /// 1–100. How much it actually matters.
    public let severity: UInt8
    /// 1–100. How readily scouting turns it up; low means it stays buried.
    public let visibility: UInt8

    public init(kind: RedFlagKind, severity: UInt8, visibility: UInt8) {
        self.kind = kind
        self.severity = severity
        self.visibility = visibility
    }

    /// A real problem that is hard to see — the slide nobody can explain at the time.
    public var isBuried: Bool { severity >= 60 && visibility <= 35 }
}

/// What a prospect's numbers said in one college season.
///
/// Production carries **independent** error, not just a restatement of ability
/// ([decision 158](../../../../docs/design-decisions.md)). A good player on a bad team
/// puts up ordinary numbers; a limited one in the right system puts up numbers he will
/// never repeat. Without that, production is ability wearing a hat and there is nothing
/// for a scout to be wrong about.
public struct ProductionProfile: Sendable, Hashable, Codable {

    public let season: Int
    public let collegeYear: CollegeYear
    /// 1–100. What the numbers look like.
    public let productionScore: UInt8
    /// 1–100. How much he was actually on the field.
    public let usage: UInt8
    /// 1–100. The team around him.
    public let teamQuality: UInt8

    public init(
        season: Int, collegeYear: CollegeYear, productionScore: UInt8, usage: UInt8,
        teamQuality: UInt8
    ) {
        self.season = season
        self.collegeYear = collegeYear
        self.productionScore = productionScore
        self.usage = usage
        self.teamQuality = teamQuality
    }
}

/// A player's college context, for as long as he has one.
///
/// There is no `Prospect` *player* type. A prospect is a `Player` — the same identifier
/// he will carry through a fifteen-year career and into the Hall of Fame — and this is
/// the college half of his record, which stops being added to once he is drafted. That
/// is what makes "we have had eyes on him since he was a sophomore" a query rather than
/// a fiction, and it is the same one-entity-one-identifier rule that governs teams and
/// plays ([ADR-0011](../../../../docs/adr/0011-derived-identity-for-regenerable-streams.md)).
public struct Prospect: Sendable, Hashable, Codable, Identifiable {

    public let player: PlayerID
    public let collegeYear: CollegeYear
    public let declaration: Declaration
    /// The class he would enter, if he enters.
    public let eligibleSeason: Int
    /// One entry per college season played, oldest first.
    public let production: [ProductionProfile]
    /// Hidden truth. Discovery is scouting's job, not the class's.
    public let flags: [RedFlag]

    public init(
        player: PlayerID,
        collegeYear: CollegeYear,
        declaration: Declaration,
        eligibleSeason: Int,
        production: [ProductionProfile],
        flags: [RedFlag] = []
    ) {
        self.player = player
        self.collegeYear = collegeYear
        self.declaration = declaration
        self.eligibleSeason = eligibleSeason
        self.production = production
        self.flags = flags
    }

    public var id: PlayerID { player }

    public var isInThisClass: Bool { declaration.isInThisClass }

    /// Came out early. Worth knowing because it is the population that busts most, and
    /// the population with the least tape.
    public var isEarlyEntrant: Bool {
        declaration == .declared && collegeYear.mayReturnToSchool
    }

    public var latestProduction: ProductionProfile? { production.last }

    public var medicalFlags: [RedFlag] { flags.filter(\.kind.isMedical) }
}
