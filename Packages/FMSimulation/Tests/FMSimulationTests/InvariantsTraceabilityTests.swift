import Foundation
import Testing

// The docs that assert football, and the tests they claim assert it, checked against each
// other.
//
// The football-domain skill said the clock stops on a change of possession while the code
// ran it through one for weeks, because the sentence and the test were never connected and
// so nothing noticed. `docs/invariants.md`, `docs/reference/playing-rules.md` and the
// skill's `game-rules.md` connect them by name — `test:someFunction`, `row:someRowId` —
// and this suite is what stops a name being wrong, stale, or quietly absent.
//
// It reads the tree from disk, which is why it is `contract:` and not `football ·`: it
// asserts nothing about the sport. It asserts that what we wrote down about the sport
// still points at something.

/// The documents and sources this suite reads, resolved from `#filePath` rather than the
/// working directory so `swift test` passes wherever it is run from.
private enum Tree {

    /// The repository root: five components up from this file.
    static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FMSimulationTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // FMSimulation
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // the root
    }

    static let invariants = "docs/invariants.md"
    static let playingRules = "docs/reference/playing-rules.md"
    static let calibrationSources = "docs/reference/calibration-sources.md"
    static let gameRules = ".claude/skills/football-domain/references/game-rules.md"
    static let targets = "Tools/simharness/Sources/simharness/Targets.swift"

    /// Every document that may name a test or a calibration row.
    static let documents = [invariants, playingRules, calibrationSources, gameRules]

    static func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Every Swift file under a package's `Tests` directory.
    ///
    /// Hidden directories are skipped, which is what keeps a `.build` tree of checked-out
    /// dependencies out of the walk.
    static func testSources() -> [URL] {
        let packages = root.appendingPathComponent("Packages")
        guard
            let walk = FileManager.default.enumerator(
                at: packages, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        var found: [URL] = []
        for case let url as URL in walk where url.pathExtension == "swift" {
            if url.pathComponents.contains("Tests") { found.append(url) }
        }
        return found.sorted { $0.path < $1.path }
    }
}

/// The small amount of parsing the suite needs. Text scans, not a Swift parser: the names
/// they look for are written plainly by convention, and a name written any other way is
/// meant to fail here.
private enum Scan {

    private static let identifier = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.")

    /// Every `` `test:name` `` or `` `row:id` `` reference in a document.
    ///
    /// A reference written with an angle bracket — `test:<function name>` — is the prose
    /// explaining the convention rather than a claim about a test, and is skipped.
    static func references(_ prefix: String, in document: String) -> Set<String> {
        var found: Set<String> = []
        var rest = Substring(document)
        while let start = rest.range(of: "`\(prefix):") {
            rest = rest[start.upperBound...]
            guard let close = rest.firstIndex(of: "`") else { break }
            let name = rest[rest.startIndex..<close]
            if !name.isEmpty, name.allSatisfy({ identifier.contains($0) }) {
                found.insert(String(name))
            }
        }
        return found
    }

    /// Every test function carrying a `@Test` attribute, by name.
    static func testFunctions(in source: String) -> Set<String> {
        var found: Set<String> = []
        var rest = Substring(source)
        while let attribute = rest.range(of: "@Test") {
            rest = rest[attribute.upperBound...]
            guard let keyword = rest.range(of: "func ") else { break }
            let name = rest[keyword.upperBound...].prefix {
                identifier.contains($0) && $0 != "."
            }
            if !name.isEmpty { found.insert(String(name)) }
        }
        return found
    }

    /// Every calibration row in `Targets.swift`, and whether its band names a season.
    static func calibrationRows(in source: String) -> [(id: String, sourced: Bool)] {
        var rows: [(id: String, sourced: Bool)] = []
        for chunk in source.components(separatedBy: "CalibrationTarget(").dropFirst() {
            guard let idKey = chunk.range(of: "id:") else { continue }
            let after = chunk[idKey.upperBound...]
            guard let open = after.firstIndex(of: "\"") else { continue }
            let value = after[after.index(after: open)...]
            guard let close = value.firstIndex(of: "\"") else { continue }
            let id = String(value[value.startIndex..<close])
            guard !id.isEmpty else { continue }
            rows.append((id, !chunk.contains("season: .unsourced")))
        }
        return rows
    }

    /// One entry's lines as a single line, with runs of whitespace collapsed.
    ///
    /// An entry is wrapped prose, so a phrase the checks look for — "not yet enforced" —
    /// can be split by a line break and its indent. Joining without collapsing leaves
    /// "not yet   enforced", which matches nothing, and the check passes on a doc that
    /// says nothing.
    static func joined(_ lines: [String]) -> String {
        lines.joined(separator: " ").split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// The numbered entries of `invariants.md`, each as its number and its whole text.
    ///
    /// An entry starts at the left margin with `12. ` and runs until the next one or the
    /// next heading; its continuation lines are indented under it.
    static func numberedEntries(in document: String) -> [(number: String, text: String)] {
        var entries: [(String, String)] = []
        var current: (number: String, lines: [String])?
        for line in document.components(separatedBy: "\n") {
            let digits = line.prefix { $0.isNumber }
            let startsEntry = !digits.isEmpty && line.dropFirst(digits.count).hasPrefix(". ")
            if startsEntry {
                if let open = current {
                    entries.append((open.number, joined(open.lines)))
                }
                current = (String(digits), [line])
            } else if line.hasPrefix("#") {
                if let open = current {
                    entries.append((open.number, joined(open.lines)))
                }
                current = nil
            } else if current != nil {
                current?.lines.append(line)
            }
        }
        if let open = current { entries.append((open.number, joined(open.lines))) }
        return entries.map { ($0.0, $0.1) }
    }

    /// The article entries of `playing-rules.md`, each as its article and its whole text.
    ///
    /// An entry is a bullet that opens with a bold article number — `- **4-3-2-a-1** —` —
    /// and runs until the next bullet or the next heading. A bullet that opens any other
    /// way is prose about the section and is not an entry.
    static func articleEntries(in document: String) -> [(article: String, text: String)] {
        var entries: [(String, String)] = []
        var current: (article: String, lines: [String])?
        func close() {
            if let open = current {
                entries.append((open.article, joined(open.lines)))
            }
            current = nil
        }
        for line in document.components(separatedBy: "\n") {
            if line.hasPrefix("- ") || line.hasPrefix("#") {
                close()
                guard line.hasPrefix("- **") else { continue }
                let afterMarker = line.dropFirst(4)
                guard let end = afterMarker.range(of: "**") else { continue }
                current = (String(afterMarker[afterMarker.startIndex..<end.lowerBound]), [line])
            } else if current != nil {
                current?.lines.append(line)
            }
        }
        close()
        return entries
    }
}

@Suite("Invariants and the reference")
struct InvariantsTraceabilityTests {

    // MARK: The tree, read once per test

    private func documents() throws -> [(path: String, text: String)] {
        try Tree.documents.map { ($0, try Tree.read($0)) }
    }

    /// Every `@Test` function in every package, and only those.
    ///
    /// Not every declared function: a doc that named a private helper would otherwise
    /// resolve and claim a check that never runs.
    private func testFunctions() -> Set<String> {
        var found: Set<String> = []
        for url in Tree.testSources() {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            found.formUnion(Scan.testFunctions(in: source))
        }
        return found
    }

    // MARK: The checks

    /// Nothing below can fail honestly if the paths have moved and every scan comes back
    /// empty, which is how a lint passes by scanning nothing.
    @Test(
        "contract: the documents and the sources this suite reads are all present", .tags(.contract)
    )
    func theTreeIsWhereWeThinkItIs() throws {
        for (path, text) in try documents() {
            #expect(text.count > 500, "\(path) is missing or nearly empty")
        }
        let functions = testFunctions()
        #expect(
            functions.count > 200, "found \(functions.count) test functions; expected the suites")
        let rows = Scan.calibrationRows(in: try Tree.read(Tree.targets))
        #expect(rows.count > 90, "found \(rows.count) calibration rows; expected the table")
    }

    @Test("contract: every test named in the invariants and the reference exists", .tags(.contract))
    func everyNamedTestExists() throws {
        let functions = testFunctions()
        var named = 0
        for (path, text) in try documents() {
            let references = Scan.references("test", in: text)
            named += references.count
            for name in references.sorted() {
                // The membership is bound first so a failure prints the name and not the
                // eight hundred function names it was looked up in.
                let exists = functions.contains(name)
                #expect(
                    exists,
                    "\(path) names test:\(name), which is not a test function in any package")
            }
        }
        #expect(named > 100, "only \(named) tests are named; the docs have lost their traceability")
    }

    @Test(
        "contract: every calibration row named in the invariants and the reference exists",
        .tags(.contract))
    func everyNamedRowExists() throws {
        let ids = Set(Scan.calibrationRows(in: try Tree.read(Tree.targets)).map(\.id))
        for (path, text) in try documents() {
            for name in Scan.references("row", in: text).sorted() {
                let exists = ids.contains(name)
                #expect(
                    exists,
                    "\(path) names row:\(name), which is not a row in Targets.swift")
            }
        }
    }

    /// The A0 suite is the acceptance language for the rules layer, so an invariant it
    /// checks that nobody wrote down is a truth with no list entry.
    @Test("contract: every rules-conformance scenario is covered by an invariant", .tags(.contract))
    func everyScenarioIsAnInvariant() throws {
        let conformance = Scan.testFunctions(
            in: try Tree.read(
                "Packages/FMSimulation/Tests/FMSimulationTests/RulesConformanceTests.swift"))
        #expect(conformance.count > 50, "found \(conformance.count) scenarios; expected the suite")
        let named = Scan.references("test", in: try Tree.read(Tree.invariants))
        for scenario in conformance.sorted() {
            let covered = named.contains(scenario)
            #expect(
                covered,
                "\(scenario) is a rules-conformance scenario that docs/invariants.md does not name")
        }
    }

    /// A band nobody wrote an invariant for is a number with no claim attached, which is
    /// what the harness's eighteen ties a season were for a week.
    @Test(
        "contract: every sourced calibration row is an invariant and names its source",
        .tags(.contract))
    func everySourcedRowIsCovered() throws {
        let rows = Scan.calibrationRows(in: try Tree.read(Tree.targets))
        let inInvariants = Scan.references("row", in: try Tree.read(Tree.invariants))
        let inSources = Scan.references("row", in: try Tree.read(Tree.calibrationSources))
        for row in rows where row.sourced {
            let claimed = inInvariants.contains(row.id)
            let sourced = inSources.contains(row.id)
            #expect(claimed, "\(row.id) has a sourced band that docs/invariants.md does not name")
            #expect(sourced, "\(row.id) is not in docs/reference/calibration-sources.md")
        }
    }

    /// Every truth carries either a check or an admission that there is none — never
    /// silence, which reads as "we do this" and often is not. An admission says which
    /// issue will enforce it, or says in as many words that no issue carries it yet.
    @Test(
        "contract: every invariant names a test, a harness row, or says it is not enforced",
        .tags(.contract))
    func everyInvariantIsTraceable() throws {
        let entries = Scan.numberedEntries(in: try Tree.read(Tree.invariants))
        #expect(entries.count > 100, "found \(entries.count) invariants; expected the list")
        for entry in entries {
            let checked = entry.text.contains("`test:") || entry.text.contains("`row:")
            let admitted = entry.text.contains("not yet enforced")
            let untraceable =
                "invariant \(entry.number) names no test, no row, and does not say it is"
                + " not yet enforced: \(entry.text.prefix(80))"
            #expect(checked || admitted, "\(untraceable)")
            guard admitted else { continue }
            let accounted = entry.text.contains("/issues/") || entry.text.contains("no issue")
            let unaccounted =
                "invariant \(entry.number) is not yet enforced and names neither the issue"
                + " that will nor the absence of one"
            #expect(accounted, "\(unaccounted)")
        }
    }

    /// The same promise on the other side of the reference: Done-when 1 for this issue is
    /// that every row of the rules reference names a test that exists, and
    /// `everyNamedTestExists` alone would stay green if every name were deleted.
    @Test(
        "contract: every article in the reference names a test or says it is not modelled",
        .tags(.contract))
    func everyArticleIsTraceable() throws {
        let entries = Scan.articleEntries(in: try Tree.read(Tree.playingRules))
        #expect(entries.count > 100, "found \(entries.count) articles; expected the index")
        for entry in entries {
            let traced =
                entry.text.contains("`test:") || entry.text.contains("not modelled")
                || entry.text.contains("not yet enforced")
            let untraceable =
                "\(entry.article) names no test and does not say the engine skips it:"
                + " \(entry.text.prefix(80))"
            #expect(traced, "\(untraceable)")
        }
    }
}
