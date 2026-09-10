// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the `foundation` rule of scripts/lint-sim.sh —
// every import spelling it must catch, including FoundationEssentials, the
// swift-foundation module that supplies Date, UUID and Data — and the comment
// stripper in front of it. Every hit it must produce is listed in
// scripts/lint-sim-fixtures/expected.txt; run scripts/lint-sim.sh --self-test.

import Foundation  // EXPECT: foundation
import FoundationEssentials  // EXPECT: foundation
import class Foundation.NSString  // EXPECT: foundation
@preconcurrency import Foundation  // EXPECT: foundation
// import Foundation — must not fire
/* import FoundationEssentials — must not fire */

// The rule's `$` branch: nothing follows the module name on the line.
// EXPECT-NEXT: foundation
import Foundation
