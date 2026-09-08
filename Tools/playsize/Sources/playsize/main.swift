// Reports the in-memory footprint of a play record, and — by existing at all —
// proves `FMCore` links without Foundation or libm.
//
// The second job is the one that caught a real bug: `Double.rounded()` resolves
// to libm's `round`, so `FMCore` failed to link into any client that did not
// already pull in Foundation. Test targets link the testing library, which
// hides that. A plain executable does not.
//
//   swift run --package-path Tools/playsize

import FMCore

func report(_ label: String, _ value: Int, unit: String = "bytes") {
    var padded = label
    while padded.count < 28 { padded += " " }
    print("  \(padded)\(value) \(unit)")
}

print("Component sizes")
report("Situation", MemoryLayout<Situation>.size)
report("Calls", MemoryLayout<Calls>.size)
report("DecisionPoint", MemoryLayout<DecisionPoint>.stride)
report("Participation", MemoryLayout<Participation>.stride)
report("PenaltyRecord", MemoryLayout<PenaltyRecord>.stride)

// A realistic pass play: the passer, target, two other routes read, three
// blockers and two rushers whose matchups resolved, and the tackler.
let decisions = 12
let participants = 10
let fixedFields = 16  // ids, index, yards, ending, runoff, points

let perPlay =
    MemoryLayout<Situation>.size
    + MemoryLayout<Calls>.size
    + decisions * MemoryLayout<DecisionPoint>.stride
    + participants * MemoryLayout<Participation>.stride
    + fixedFields

print("")
print("A realistic play (\(decisions) decisions, \(participants) credited)")
report("decisions", decisions * MemoryLayout<DecisionPoint>.stride)
report("participants", participants * MemoryLayout<Participation>.stride)
report("total", perPlay)

let playsPerGame = 150
let gamesPerSeason = 272

print("")
print("Scaling")
report("per game", perPlay * playsPerGame / 1024, unit: "KB")
report("your season (17 games)", perPlay * playsPerGame * 17 / 1024, unit: "KB")
report("league season", perPlay * playsPerGame * gamesPerSeason / 1_048_576, unit: "MB")
report(
    "ten seasons, league-wide", perPlay * playsPerGame * gamesPerSeason * 10 / 1_048_576, unit: "MB"
)

print("")
print("Trajectory, for comparison (10Hz, 22 players, 4 bytes per position)")
let trajectoryPerGame = 1_300 * 22 * 4
report("per game", trajectoryPerGame / 1024, unit: "KB")
report("ratio to records", trajectoryPerGame / (perPlay * playsPerGame))
