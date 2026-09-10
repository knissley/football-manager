// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. The negative control: banned names written in comments,
// none of which may fire, plus one in a string literal, which must, because
// string literals are deliberately not stripped. The three comment forms do not
// hold the same thing, and each block below says what it holds and why. The one
// hit is listed in scripts/lint-sim-fixtures/expected.txt.

/// A doc comment holding the use-site bans, and only those: Int.random(in:),
/// SystemRandomNumberGenerator(), deck.shuffled(), deck.shuffled(using: &rng),
/// roster.randomElement(), UUID(), Date(), Hasher(), ContinuousClock(),
/// SuspendingClock(), DispatchTime.now(), ProcessInfo, getenv and clock_gettime.
/// Not one of them fires.
///
/// The import bans cannot be pinned in this form at all. Their patterns are
/// anchored to the start of the line, so a `//` in front of `import Foundation`
/// puts it out of the pattern's reach whether the stripper runs or not, and a
/// line like that proves nothing about the stripper.
//
// The same holds for a plain line comment, so this one carries use-site names
// too. Each would fire if the stripper's line-comment branch stopped working:
// let unlucky = UUID(), Date(), Hasher()
// deck.shuffled(), roster.randomElement(), ProcessInfo, getenv, clock_gettime
//
/* A block comment is the one form that can pin the import rules, because it
   opens on an earlier line and leaves the lines after it starting with the
   keyword. Each of these four would fire its rule — foundation, foundation,
   dispatch, platform — if the block-comment branch stopped working:

   import Foundation
   import FoundationEssentials
   import Dispatch
   import SwiftData

   and so would every use-site name below:

   let unlucky = UUID(), Date(), Hasher(), ContinuousClock(), SuspendingClock()
   var rng = SystemRandomNumberGenerator(); Int.random(in: 0..<1)
   deck.shuffled(), deck.shuffled(using: &rng), roster.randomElement()
   DispatchTime.now(), ProcessInfo, getenv, clock_gettime
*/
func negativeControl() -> String {
    // The single hit in this file. A banned name inside a string literal is
    // reported on purpose: interpolation can hold real code, and literal text
    // that reads like a banned call is a false positive worth looking at.
    return "the engine is handed the time, it never calls Date() itself"  // EXPECT: date
}
