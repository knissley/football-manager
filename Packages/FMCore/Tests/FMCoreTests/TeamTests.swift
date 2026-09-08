import Testing

@testable import FMCore

@Suite("Team identity")
struct TeamIdentityTests {

    private let navy = TeamColor(red: 12, green: 35, blue: 64)
    private let bone = TeamColor(red: 240, green: 236, blue: 224)
    private let forest = TeamColor(red: 20, green: 52, blue: 40)

    private func identity() -> TeamIdentity {
        TeamIdentity(
            city: "Kettle Falls", nickname: "Wolverines", abbreviation: "KF",
            colors: TeamColors(primary: navy, secondary: bone, accent: bone))
    }

    @Test("A colour packs and unpacks its channels")
    func colorChannels() {
        let color = TeamColor(red: 12, green: 35, blue: 64)
        #expect(color.red == 12)
        #expect(color.green == 35)
        #expect(color.blue == 64)
        #expect(TeamColor(rawValue: color.rawValue) == color)
    }

    /// The top byte is not a colour channel, so it must not survive a round trip and
    /// come back as a different colour.
    @Test("A raw value is masked to twenty-four bits")
    func rawValueIsMasked() {
        #expect(TeamColor(rawValue: 0xFF00_0000).rawValue == 0)
        #expect(TeamColor(rawValue: 0xAB12_3456).rawValue == 0x12_3456)
    }

    @Test("Luma tracks lightness")
    func luma() {
        #expect(bone.luma > navy.luma)
        #expect(TeamColor(red: 0, green: 0, blue: 0).luma == 0)
        #expect(TeamColor(red: 255, green: 255, blue: 255).luma >= 250)
    }

    /// Two dark colours on a jersey is two teams nobody can tell apart at a glance.
    /// The generator relies on this to reject a pairing, so it has to actually reject.
    @Test("Contrast separates a readable pairing from two darks")
    func contrast() {
        #expect(TeamColors(primary: navy, secondary: bone, accent: bone).hasReadableContrast)
        #expect(
            TeamColors(primary: navy, secondary: forest, accent: bone).hasReadableContrast == false)
    }

    @Test("A full name is the city and the nickname")
    func fullName() {
        #expect(identity().fullName == "Kettle Falls Wolverines")
    }
}

@Suite("Team identity history")
struct TeamIdentityEventTests {

    private let navy = TeamColor(red: 12, green: 35, blue: 64)
    private let bone = TeamColor(red: 240, green: 236, blue: 224)
    private let gold = TeamColor(red: 236, green: 190, blue: 62)

    private func founding() -> TeamIdentityEvent {
        TeamIdentityEvent(
            team: TeamID(1), effectiveFrom: SeasonID(1),
            change: .founded(
                identity: TeamIdentity(
                    city: "Ashport", nickname: "Anchors", abbreviation: "ASH",
                    colors: TeamColors(primary: navy, secondary: bone, accent: bone)),
                stadium: Stadium(name: "Harborside Field", capacity: 64_000)))
    }

    /// The point of the whole stream: a replay of an old game has to show the world as
    /// it was, not as a rebrand has since made it.
    @Test("A projection shows the identity of the season asked for")
    func projectionRespectsTime() {
        let events = [
            founding(),
            TeamIdentityEvent(
                team: TeamID(1), effectiveFrom: SeasonID(4), change: .renamed(nickname: "Kraken")),
            TeamIdentityEvent(
                team: TeamID(1), effectiveFrom: SeasonID(6),
                change: .rebranded(TeamColors(primary: navy, secondary: gold, accent: bone))),
        ]

        #expect(
            TeamSnapshot.projected(at: SeasonID(1), from: events)?.identity.nickname == "Anchors")
        #expect(
            TeamSnapshot.projected(at: SeasonID(3), from: events)?.identity.nickname == "Anchors")
        #expect(
            TeamSnapshot.projected(at: SeasonID(4), from: events)?.identity.nickname == "Kraken")
        #expect(
            TeamSnapshot.projected(at: SeasonID(5), from: events)?.identity.colors.secondary == bone
        )
        #expect(
            TeamSnapshot.projected(at: SeasonID(9), from: events)?.identity.colors.secondary == gold
        )
    }

    /// A move takes the building with it. Replaying a game from before it must not put
    /// the team in a stadium it had not built yet.
    @Test("A relocation carries the stadium with the city")
    func relocationMovesTheStadium() {
        let events = [
            founding(),
            TeamIdentityEvent(
                team: TeamID(1), effectiveFrom: SeasonID(7),
                change: .relocated(
                    city: "Silverpeak",
                    stadium: Stadium(
                        name: "Alta Bowl", capacity: 71_000, climate: .mountain,
                        altitudeFeet: 5_200))),
        ]

        let before = TeamSnapshot.projected(at: SeasonID(6), from: events)
        #expect(before?.identity.city == "Ashport")
        #expect(before?.stadium.name == "Harborside Field")
        #expect(before?.stadium.isHighAltitude == false)

        let after = TeamSnapshot.projected(at: SeasonID(7), from: events)
        #expect(after?.identity.city == "Silverpeak")
        #expect(after?.stadium.name == "Alta Bowl")
        #expect(after?.stadium.isHighAltitude == true)
        #expect(after?.identity.nickname == "Anchors", "a move is not a rename")
    }

    /// A team that was never founded has no state to report. Inventing a blank one
    /// would let the mistake travel to whatever asked.
    @Test("A stream with no founding event projects to nothing")
    func unfoundedProjectsToNil() {
        let orphan = [
            TeamIdentityEvent(
                team: TeamID(1), effectiveFrom: SeasonID(2), change: .renamed(nickname: "Kraken"))
        ]
        #expect(TeamSnapshot.projected(at: SeasonID(5), from: orphan) == nil)
        #expect(TeamSnapshot.projected(at: SeasonID(0), from: [founding()]) == nil)
    }

    /// The current cached value on `Team` must equal what the stream folds to, or the
    /// projection is not a projection.
    @Test("A team's cached state matches the fold of its stream")
    func cacheMatchesTheFold() {
        let events = [
            founding(),
            TeamIdentityEvent(
                team: TeamID(1), effectiveFrom: SeasonID(3),
                change: .reabbreviated("ASP")),
        ]
        guard let folded = TeamSnapshot.projected(at: SeasonID(3), from: events) else {
            Issue.record("the stream should fold")
            return
        }

        let team = Team(
            id: TeamID(1), region: .east, identity: folded.identity, stadium: folded.stadium,
            market: .large, scheme: TeamScheme(offense: .airRaid, defense: .nickelMatch))

        #expect(team.snapshot == folded)
        #expect(team.identity.abbreviation == "ASP")
        #expect(team.projected(at: SeasonID(1), from: events)?.identity.abbreviation == "ASH")
        #expect(
            team.projected(at: SeasonID(1), from: events)?.market == .large,
            "a rebrand does not touch what is not identity")
    }
}
