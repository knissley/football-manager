// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. The negative control: every banned name the table knows,
// written in every comment form the repo uses, none of which may fire — plus one
// in a string literal, which must, because string literals are deliberately not
// stripped. Every hit it must produce is listed in
// scripts/lint-sim-fixtures/expected.txt; run scripts/lint-sim.sh --self-test.

/// A doc comment naming Int.random(in:), SystemRandomNumberGenerator(),
/// deck.shuffled(), deck.shuffled(using: &rng), roster.randomElement(), UUID(),
/// Date(), Hasher(), ContinuousClock(), SuspendingClock(), DispatchTime.now(),
/// ProcessInfo, getenv and clock_gettime. Not one of them fires.
//
// import Foundation
// import FoundationEssentials
// import Dispatch
// import SwiftData
// import SwiftUI
//
/*
   The same list again inside a block comment, because the stripper handles the
   two forms on different branches: Int.random(in:),
   SystemRandomNumberGenerator(), deck.shuffled(), deck.shuffled(using: &rng),
   roster.randomElement(), UUID(), Date(), Hasher(), ContinuousClock(),
   SuspendingClock(), DispatchTime.now(), ProcessInfo, getenv, clock_gettime,
   import Foundation, import FoundationEssentials, import Dispatch,
   import SwiftData, import SwiftUI. Not one of them fires either.
*/
func negativeControl() -> String {
    // The single hit in this file. A banned name inside a string literal is
    // reported on purpose: interpolation can hold real code, and literal text
    // that reads like a banned call is a false positive worth looking at.
    return "the engine is handed the time, it never calls Date() itself"  // EXPECT: date
}
