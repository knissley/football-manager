import Testing

@testable import FMCore

@Suite("Rotation profiles")
struct RotationProfileTests {

    /// The invariant that makes a season's snap counts add up to a season: a position's
    /// shares sum to roughly how many of that position are on the field at once.
    @Test("Shares sum to a plausible number on the field")
    func sharesSumToOnFieldCount() {
        let expected: [Position: (Double, Double)] = [
            .quarterback: (0.9, 1.1),
            .runningBack: (0.9, 1.15),
            .wideReceiver: (2.3, 2.9),
            .tightEnd: (1.0, 1.4),
            .leftTackle: (0.9, 1.1),
            .center: (0.9, 1.1),
            .edge: (1.7, 2.2),
            .defensiveTackle: (1.7, 2.2),
            .linebacker: (2.0, 2.5),
            .cornerback: (2.4, 2.9),
            .safety: (1.9, 2.3),
        ]

        for (position, range) in expected {
            let total = RotationProfile.expectedOnField(position)
            #expect(
                total >= range.0 && total <= range.1,
                "\(position) puts \(total) players on the field")
        }
    }

    /// Eleven a side, and football is not approximate about it. If the shares do not add
    /// up, every box score is wrong in a way no single position would reveal — a first
    /// pass fielded 10.7 defenders and the loose range this test originally carried was
    /// what let it through.
    @Test("Each side of the ball fields eleven players")
    func elevenASide() {
        func total(_ side: Side) -> Double {
            Position.allCases.filter { $0.side == side }
                .reduce(0) { $0 + RotationProfile.expectedOnField($1) }
        }
        #expect(total(.offense) > 10.9 && total(.offense) < 11.1, "offence: \(total(.offense))")
        #expect(total(.defense) > 10.9 && total(.defense) < 11.1, "defence: \(total(.defense))")
    }

    /// The defensive front is four men whether it is two edges and two tackles or a
    /// three-man front with an extra rusher standing up.
    @Test("The defensive front and the secondary carry their real numbers")
    func defensiveShape() {
        let front =
            RotationProfile.expectedOnField(.edge)
            + RotationProfile.expectedOnField(.defensiveTackle)
        let secondary =
            RotationProfile.expectedOnField(.cornerback) + RotationProfile.expectedOnField(.safety)

        #expect(front > 3.9 && front < 4.15, "front: \(front)")
        // Nickel is the base defence now, so five defensive backs more often than four.
        #expect(secondary > 4.5 && secondary < 4.9, "secondary: \(secondary)")
    }

    @Test("A starter always plays more than his backup")
    func sharesDescend() {
        for position in Position.allCases {
            let shares = RotationProfile.shares(for: position)
            #expect(shares == shares.sorted(by: >), "\(position) has a backup ahead of a starter")
            #expect(shares.allSatisfy { $0 > 0 }, "\(position) lists a share of zero")
        }
    }

    /// A lineman plays every snap or he is a backup; a defensive line rotates heavily.
    /// Flattening that would put a false story in every box score.
    @Test("Rotation depth differs by position the way the sport does")
    func rotationDepthVaries() {
        #expect(RotationProfile.snapShare(.leftTackle, depth: 0) > 0.95)
        #expect(RotationProfile.snapShare(.leftTackle, depth: 1) < 0.1)

        #expect(RotationProfile.snapShare(.edge, depth: 2) > 0.3, "the third edge should play")
        #expect(RotationProfile.snapShare(.defensiveTackle, depth: 3) > 0.1)
        #expect(RotationProfile.snapShare(.runningBack, depth: 1) > 0.25)
    }

    /// A fourth tight end does not play on offence, and giving him a share would put
    /// statistics on a player who never took the field.
    @Test("Past the end of the rotation, nobody plays")
    func beyondTheRotation() {
        #expect(RotationProfile.snapShare(.tightEnd, depth: 3) == 0)
        #expect(RotationProfile.snapShare(.quarterback, depth: 2) == 0)
        #expect(RotationProfile.snapShare(.wideReceiver, depth: 99) == 0)
        #expect(RotationProfile.snapShare(.center, depth: -1) == 0)
    }
}

@Suite("Depth charts")
struct DepthChartTests {

    private func chart() -> DepthChart {
        DepthChart(order: [
            .quarterback: [PlayerID(1), PlayerID(2)],
            .runningBack: [PlayerID(10), PlayerID(11), PlayerID(12), PlayerID(13)],
            .edge: [PlayerID(20), PlayerID(21), PlayerID(22)],
            .center: [PlayerID(30), PlayerID(31)],
        ])
    }

    @Test("A chart reports order, starters and depth")
    func ordering() {
        let chart = chart()
        #expect(chart.starter(at: .quarterback) == PlayerID(1))
        #expect(chart.depth(of: PlayerID(12), at: .runningBack) == 2)
        #expect(chart.depth(of: PlayerID(99), at: .runningBack) == nil)
        #expect(chart.contains(PlayerID(21)))
        #expect(chart.contains(PlayerID(99)) == false)
        #expect(chart.starter(at: .punter) == nil)
    }

    @Test("Positions come back in a stable order")
    func stableOrder() {
        #expect(chart().positions == chart().positions)
        #expect(chart().positions == chart().positions.sorted { $0.rawValue < $1.rawValue })
    }

    /// A fourth running back is on the roster and not in the rotation. He should not
    /// collect statistics.
    @Test("Only players inside the rotation are credited")
    func rotationIsBounded() {
        let backs = chart().rotation(at: .runningBack)
        #expect(backs.count == 3, "a fourth back should not be in the rotation")
        #expect(backs.map(\.player) == [PlayerID(10), PlayerID(11), PlayerID(12)])
        #expect(backs[0].snapShare > backs[1].snapShare)
    }

    /// Next man up: a starter going down turns his backup into a starter, and that falls
    /// out of the ordering rather than needing a rule.
    @Test("An injury promotes everyone behind him")
    func nextManUp() {
        let healthy = chart().rotation(at: .runningBack)
        let injured = chart().rotation(at: .runningBack, unavailable: [PlayerID(10)])

        #expect(injured[0].player == PlayerID(11))
        #expect(injured[0].snapShare == healthy[0].snapShare, "the new starter inherits the load")
        #expect(injured.map(\.player) == [PlayerID(11), PlayerID(12), PlayerID(13)])
        #expect(injured[0].depth == 0)
    }

    /// The share belongs to the place on the chart, not to the man. Two injuries ahead
    /// of him and the fourth back is carrying the ball.
    @Test("Shares follow the depth, not the player")
    func sharesFollowDepth() {
        let depleted = chart().rotation(
            at: .runningBack, unavailable: [PlayerID(10), PlayerID(11)])
        #expect(depleted[0].player == PlayerID(12))
        #expect(depleted[0].snapShare == RotationProfile.snapShare(.runningBack, depth: 0))
        #expect(depleted.count == 2)
    }

    /// Injuries do run a position out of bodies. Saying so is better than silently
    /// fielding ten men.
    @Test("A position with nobody left is reported")
    func unmannedPositions() {
        let chart = chart()
        #expect(chart.unmannedPositions().isEmpty)

        let wiped = chart.unmannedPositions(unavailable: [PlayerID(1), PlayerID(2)])
        #expect(wiped == [.quarterback])
        #expect(chart.rotation(at: .quarterback, unavailable: [PlayerID(1), PlayerID(2)]).isEmpty)
    }

    @Test("A whole-chart rotation covers every position in a stable order")
    func wholeChartRotation() {
        let all = chart().rotation()
        #expect(Set(all.map(\.position)).count == 4)
        #expect(all.map(\.position) == all.map(\.position).sorted { $0.rawValue < $1.rawValue })
        #expect(all.allSatisfy { $0.snapShare > 0 })
        #expect(chart().rotation() == chart().rotation())
    }
}
