import FMCore
import FMGeneration
import FMRandom
import Testing

@testable import FMSimulation

/// Who is trusted with the football.
///
/// `Fumbles.drawn` reads one thing about the man holding it — his `carrying` — so what a
/// generated league gives a position there *is* its ball security, and a position generated
/// low fumbles more on every contact for the rest of its career. This suite reads that
/// number back out of a generated league and puts it through the engine's own draw.
@Suite("Ball security")
struct BallSecurityTests {

    /// The league the medians are read from. Seed 7 is the harness's own world.
    private static let world = try? WorldGenerator.generate(
        seed: 7, shape: .standard, season: 2030
    ).get()

    private func everyone() throws -> [Player] {
        let world = try #require(Self.world, "seed 7 did not produce a world")
        var players: [Player] = []
        for team in world.teams { players += world.roster(of: team.id) }
        return players
    }

    /// The middle value, which is what a median is. Sorted first, so the answer does not
    /// depend on the order a roster happens to arrive in.
    private func median(_ values: [UInt8]) -> UInt8 {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return Ratings.untrainedFloor }
        return sorted[sorted.count / 2]
    }

    /// A man built to hold exactly one rating at a stated value.
    ///
    /// Everything else is held equal between the two arms below, and the carrier is a back
    /// in both of them, because `Fumbles.drawn` reads the carrier through
    /// `PlayContext.effective` — which adds his fit to the scheme on top of the rating. Two
    /// men at two positions would differ by their fit as well as by their ball security,
    /// and the comparison is about the ball security.
    private func man(
        id: UInt64, position: Position, ratings overrides: [RatingKey: UInt8]
    ) -> Player {
        var values: Ratings = [:]
        for key in RatingKey.allCases { values[key] = overrides[key] ?? 68 }
        return Player(
            id: PlayerID(id), name: PersonName(given: "Test", family: "Player"),
            birthSeason: 2004,
            college: College(name: "Fallback State", profile: .midMajor), draft: nil,
            firstSeason: 2026,
            position: position, secondaryPositions: [],
            physical: PhysicalProfile(
                heightInches: 71, weightPounds: 215, fortyYardDash: 452, verticalJump: 350,
                broadJump: 1200, threeCone: 690, benchReps: 18),
            ratings: values,
            hidden: HiddenAttributes(
                ceiling: 80, developmentTrait: .normal, workEthic: 70, durability: 70))
    }

    /// How often a hit on a carrier at `carrying` puts the ball on the ground, over
    /// `contacts` contacts with the same tackler.
    private func fumbleRate(
        carrying: UInt8, hitPower: UInt8, contacts: Int, seed: UInt64
    ) -> Double {
        var personnel = Lineup()
        personnel.place(PlayerID(1), position: .runningBack, at: 1)
        personnel.place(PlayerID(2), position: .linebacker, at: 15)

        let context = PlayContext(
            offense: TeamID(1), defense: TeamID(2), offenseRotation: [], defenseRotation: [],
            players: [
                PlayerID(1): man(id: 1, position: .runningBack, ratings: [.carrying: carrying]),
                PlayerID(2): man(id: 2, position: .linebacker, ratings: [.hitPower: hitPower]),
            ],
            offenseScheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder),
            defenseScheme: TeamScheme(offense: .airRaid, defense: .nickelMatch),
            rules: .standard)

        var random = SplittableRandom(seed: seed)
        var loose = 0
        for _ in 0..<contacts {
            if Fumbles.drawn(
                carrier: PlayerSlot(1), tackler: PlayerSlot(15), isSack: false,
                personnel: personnel, context: context, random: &random) != nil
            {
                loose += 1
            }
        }
        return Double(loose) / Double(contacts)
    }

    /// The engine must not read a penalty into ball security that the rules do not draw.
    ///
    /// **Why this is a promise about the engine and not a claim about the sport.** The
    /// rules support the *premise* and not the assertion. The 2025 rulebook defines a
    /// fumble once and a runner once, and neither definition turns on the position a man
    /// plays or on how the ball reached him: losing it is a fumble unless it left him as a
    /// pass, a hand-off or a legal kick (3-2-5); the runner is simply whoever on the
    /// offence holds the live ball (3-27); and the man who catches a pass is free to run
    /// with it (8-1-3). One category in the rules, and one model here — `Fumbles.drawn`
    /// reads the carrier's `carrying` and nothing else about him. What those articles do
    /// **not** establish is that a receiver in the real sport fumbles no more often per
    /// touch than a back. That is an empirical claim about a real season, and it would
    /// need a season and a source, which is why this test is tagged as a contract: a
    /// promise the engine makes about itself, with the rules as the reason the promise is
    /// the right one.
    ///
    /// **The band that would make it a football claim does not exist here.** No
    /// per-position fumbles-per-touch row is sourced in
    /// [`calibration-sources.md`](../../../../docs/reference/calibration-sources.md), and
    /// none could be obtained: the two fumble rows that are sourced are per team-game over
    /// every carrier and cannot separate two positions. Adding one is a sourcing job under
    /// that file's own band policy — a season, a source, and a derivation the script can
    /// reproduce — and until somebody does it, nothing in this repository can grade ball
    /// security by position against the sport.
    ///
    /// **How it is measured.** The two ball-security numbers are the medians a generated
    /// league actually produces at seed 7: every receiver and tight end on every roster,
    /// against every back. They are then put through `Fumbles.drawn` itself, against one
    /// tackler at the league's median defensive hit power, rather than by playing games —
    /// four hundred games contain something like twelve hundred fumbles in total, split
    /// across every position and against touch counts that are nothing like equal, which
    /// is far too coarse to separate two positions' per-touch rates. A quarter of a million
    /// contacts an arm is the same measurement with the noise taken out of it.
    ///
    /// **It has teeth, and here is the evidence.** Two mutations, both run against this
    /// assertion. Take the two ball-carrying keys back off the receiving positions, so
    /// they draw ball security from the untrained table again, and it reads 0.03401 of
    /// contacts against a back's 0.01980 with four standard errors at 0.00183 — red by
    /// roughly twenty-seven of them. Hold everything else and give the receiver arm six
    /// points less carrying than the back's median, and it reads 0.02186 against 0.01980
    /// with a tolerance of 0.00162 — still red. So it is not only sensitive to the
    /// forty-point hole it was written for: it turns red once a receiver's median ball
    /// security falls about six points under a back's.
    ///
    /// **The tolerance is an assumed model, not a measured spread**: the binomial standard
    /// error of the difference of the two rates at this many draws, which assumes each
    /// contact is an independent trial at a fixed probability. Nobody has measured the
    /// spread of this statistic by resampling.
    @Test(
        "contract: ball security carries no positional penalty the rules do not draw — a receiver at his league's median carrying is no likelier to fumble per contact than a back at his",
        .tags(.contract))
    func aReceiverIsNotALooserBallCarrierThanABack() throws {
        let players = try everyone()
        let receiving = players.filter {
            $0.position == .wideReceiver || $0.position == .tightEnd
        }
        let backfield = players.filter { $0.position.group == .backfield }
        #expect(!receiving.isEmpty && !backfield.isEmpty, "seed 7 produced no such players")

        let receiverSecurity = median(receiving.compactMap { $0.ratings[.carrying] })
        let backSecurity = median(backfield.compactMap { $0.ratings[.carrying] })
        let punch = median(
            players.filter { $0.position.side == .defense }.compactMap { $0.ratings[.hitPower] })

        let contacts = 250_000
        let receiverRate = fumbleRate(
            carrying: receiverSecurity, hitPower: punch, contacts: contacts, seed: 115)
        let backRate = fumbleRate(
            carrying: backSecurity, hitPower: punch, contacts: contacts, seed: 115)

        let noise =
            ((receiverRate * (1 - receiverRate) + backRate * (1 - backRate))
            / Double(contacts)).squareRoot()

        #expect(
            receiverRate <= backRate + 4 * noise,
            """
            a receiver at carrying \(receiverSecurity) fumbles \(receiverRate) of his contacts \
            against \(backRate) for a back at carrying \(backSecurity), \
            hit power \(punch), four standard errors being \(4 * noise)
            """)
    }

    /// A ball that is already dead cannot come loose, so the hit that put it on the
    /// ground is not also a tackle the record says was made.
    ///
    /// Two articles, read together. 3-2-5 makes a fumble an act by a player who *was in
    /// possession* when it happened, and ends the fumble the moment the ball is dead.
    /// 7-2-1-a makes the ball dead as soon as a runner contacted by an opponent touches
    /// the ground with any part of him other than his hands or his feet. So the two
    /// events are ordered by the rules and not by taste: the ball comes out on the hit,
    /// or it does not come out at all. A down that ended in a fumble is a down on which
    /// nobody finished the tackle, and a record saying the carrier was tackled and then
    /// lost it is describing a down the book cannot produce.
    ///
    /// What the engine has to do about it is therefore narrow, and it is the whole of
    /// this claim: the attempt that knocked it loose is written as a forced fumble, and
    /// the same play carries no completed tackle of the man who fumbled.
    ///
    /// **Read over the shared corpus** rather than a forced draw, because a fumble is
    /// common enough for forty games to hold well over a hundred of them and what is
    /// being asserted is a property of *every* one, not the existence of one. The count
    /// is checked before the claim, so a corpus that stopped producing fumbles fails
    /// here rather than passing on an empty filter.
    ///
    /// **Only downs somebody was in possession of**, which is the article's own
    /// restriction: 3-2-5's last sentence makes the word mean that the ball was in a
    /// player's possession when the act occurred, and a free kick the kicking team falls
    /// on was never in anybody's — it is a loose ball (3-2-4). The engine nonetheless
    /// records that recovery as `PlayEnding.fumbleRecovered`, so the ending alone does
    /// not say a fumble happened and this reads the play kind as well.
    @Test(
        "football · Rules 3-2-5, 7-2-1 · a down that ended in a fumble carries no completed tackle of the man who fumbled",
        .tags(.football))
    func theBallComesOutBeforeTheRunnerIsDown() {
        let fromScrimmage: Set<PlayKind> = [
            .rush, .pass, .sack, .scramble, .twoPointConversion,
        ]
        var fumbles = 0
        for result in TestWorld.corpus {
            for play in result.plays
            where fromScrimmage.contains(play.outcome.kind)
                && (play.outcome.endedIn == .fumbleLost
                    || play.outcome.endedIn == .fumbleRecovered)
            {
                fumbles += 1
                let attempts = play.decisions.filter { $0.kind == .tackleAttempt }
                let at = "play \(play.index) of game \(result.game)"
                #expect(
                    attempts.contains { $0.tackleResult == .forcedFumble },
                    "\(at): the ball came loose and no attempt says who forced it")
                #expect(
                    !attempts.contains { $0.tackleResult == .madeTackle },
                    "\(at): the tackle was made and the ball came loose afterwards")
            }
        }
        #expect(fumbles > 0, "no fumble in the corpus to read")
    }
}
