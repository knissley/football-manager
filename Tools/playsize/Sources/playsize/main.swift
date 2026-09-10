// Reports the in-memory footprint of a play record, and — by existing at all —
// proves the simulation modules link without Foundation or libm.
//
// The second job is the one that caught a real bug, twice: `Double.rounded()`
// resolves to libm's `round`, so a module using it fails to link into any client
// that does not already pull in Foundation. Test targets link the testing
// library, which hides it. A plain executable does not — so this depends on the
// top of the module chain to guard all of it.
//
//   swift run --package-path Tools/playsize

import FMCore
import FMGeneration

func report(_ label: String, _ value: Int, unit: String = "bytes") {
    var padded = label
    while padded.count < 28 { padded += " " }
    print("  \(padded)\(value) \(unit)")
}

print("Component sizes")
report("Situation", MemoryLayout<Situation>.size)
report("Calls", MemoryLayout<Calls>.size)
report("  OffensiveCall", MemoryLayout<OffensiveCall>.size)
report("  DefensiveCall", MemoryLayout<DefensiveCall>.size)
report("PlayRef", MemoryLayout<PlayRef>.size)
report("PlayRecord (fixed part)", MemoryLayout<PlayRecord>.size)
report("DecisionPoint", MemoryLayout<DecisionPoint>.stride)
report("Participation", MemoryLayout<Participation>.stride)
report("PenaltyRecord", MemoryLayout<PenaltyRecord>.stride)

// A realistic pass play: the passer, target, two other routes read, three
// blockers and two rushers whose matchups resolved, and the tackler.
let decisions = 12
let participants = 10
// Everyone on the field, credited or not, as a roster index a byte wide.
let onField = PlayerSlot.count * MemoryLayout<UInt8>.stride
// Measured rather than hand-counted: the struct's own size already covers the
// situation, both calls, the game and index, and one pointer per array. Only the
// heap-allocated elements have to be added.
let perPlay =
    MemoryLayout<PlayRecord>.size
    + decisions * MemoryLayout<DecisionPoint>.stride
    + participants * MemoryLayout<Participation>.stride
    + onField

print("")
print("A realistic play (\(decisions) decisions, \(participants) credited, 22 on the field)")
report("decisions", decisions * MemoryLayout<DecisionPoint>.stride)
report("participants", participants * MemoryLayout<Participation>.stride)
report("on the field", onField)
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
let ratioTenths = (trajectoryPerGame * 10) / (perPlay * playsPerGame)
print("  ratio to records            \(ratioTenths / 10).\(ratioTenths % 10)x")
