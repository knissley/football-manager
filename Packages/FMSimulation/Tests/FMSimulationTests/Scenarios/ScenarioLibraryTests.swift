import FMCore
import FMSimulationScenarios
import Testing

@testable import FMSimulation

// The library of conformance scenarios, as a tool sees it.
//
// `gamelog --scenario <name>` runs one of the rules-conformance scenarios through the
// same printer a seeded game goes through, so a rule can be shown rather than described.
// That only works if the tool can name every scenario the suite runs, and if the name it
// takes on the command line is the name it prints.
//
// The agreement is enforced by construction rather than by this test alone: the scripts
// themselves are internal to `FMSimulationScenarios`, so the only way a suite can obtain
// a named conformance scenario is a case of `RulesScenario` — and every case is in
// `allCases`, which is what the listing prints. What this test pins is the rest of it:
// that the listing really does name them all, that the slug the listing prints is the
// slug the tool parses back, and that every scenario in the library still runs and emits
// a stream a printer can walk.

@Suite("Scenario library")
struct ScenarioLibraryTests {

    @Test(
        "contract · --scenario list names every scenario in the conformance library, each with the football it is there to show"
    )
    func listingNamesEveryScenario() {
        let listing = RulesScenario.listing()
        #expect(RulesScenario.allCases.isEmpty == false, "the library is empty")
        for scenario in RulesScenario.allCases {
            #expect(
                listing.contains { $0.hasSuffix(" " + scenario.slug) },
                "--scenario list does not name \(scenario.slug)")
            #expect(
                scenario.expectations.isEmpty == false,
                "\(scenario.slug) says nothing about what to watch for")
            for expectation in scenario.expectations {
                // The expectations are the conformance tests' own names, so each one
                // carries its kind, and a football sentence carries its citation.
                #expect(
                    expectation.hasPrefix("football · ") || expectation.hasPrefix("pin · "),
                    "\(scenario.slug): \"\(expectation)\" does not say what kind of claim it is")
                #expect(
                    expectation.hasPrefix("pin · ") || expectation.contains("Rule ")
                        || expectation.contains("A.R."),
                    "\(scenario.slug): \"\(expectation)\" cites no rule")
                #expect(
                    listing.contains { $0.contains(expectation) },
                    "--scenario list does not print \(scenario.slug)'s citation")
            }
        }
    }

    @Test("contract · a scenario's slug is the name the tool takes on the command line")
    func slugsRoundTripAndAreDistinct() {
        var seen: Set<String> = []
        for scenario in RulesScenario.allCases {
            let slug = scenario.slug
            #expect(seen.insert(slug).inserted, "two scenarios are both called \(slug)")
            #expect(RulesScenario(slug) == scenario, "--scenario \(slug) does not find it again")
            #expect(slug.isEmpty == false)
            #expect(
                slug.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" },
                "\(slug) is not a plain command-line token")
        }
    }

    @Test("contract · every scenario in the library runs and emits a stream a printer can walk")
    func everyScenarioRuns() {
        for scenario in RulesScenario.allCases {
            let trace = scenario.run()
            #expect(trace.plays.isEmpty == false, "\(scenario.slug) played no football")
            for (offset, play) in trace.plays.enumerated() {
                #expect(
                    Int(play.index) == offset,
                    "\(scenario.slug): play \(offset) is indexed \(play.index)")
            }
        }
    }
}
