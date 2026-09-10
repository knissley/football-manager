// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the `dispatch` rule of scripts/lint-sim.sh and
// the comment stripper in front of it. Every hit it must produce is listed in
// scripts/lint-sim-fixtures/expected.txt; run scripts/lint-sim.sh --self-test.

import Dispatch  // EXPECT: dispatch
@preconcurrency import Dispatch  // EXPECT: dispatch
// import Dispatch — must not fire
/* import Dispatch — must not fire */
