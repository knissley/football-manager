// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the `platform` rule of scripts/lint-sim.sh,
// one line per framework in the pattern, and the comment stripper in front of
// it. Every hit it must produce is listed in
// scripts/lint-sim-fixtures/expected.txt; run scripts/lint-sim.sh --self-test.

import SwiftData  // EXPECT: platform
import SwiftUI  // EXPECT: platform
import UIKit  // EXPECT: platform
import AppKit  // EXPECT: platform
import Combine  // EXPECT: platform
import CoreGraphics  // EXPECT: platform
import Glibc  // EXPECT: platform
import Darwin  // EXPECT: platform
import os  // EXPECT: platform
// import SwiftUI — must not fire
/* import UIKit — must not fire */
