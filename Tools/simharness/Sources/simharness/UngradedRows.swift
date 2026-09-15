// The rows a run could not grade, and why it could not.
//
// An ungraded row is invisible in a way an out-of-band row is not. It prints an em dash,
// it lands in a tally beside the rows that are ungradable by design, and it makes the
// summary *greener*, because a row that cannot be graded is a row that cannot be `OFF`.
// That is how `row:ypcOutnumberedByOne` lost its entire sample: a change removed the only
// situation it grades, nothing went red, no check complained, and it was caught only
// because somebody read a run line by line.
//
// So the run names them. A row with no value says which row it is and what stopped it,
// and a row whose call site offered no reason says *that*, loudly, rather than passing
// for one of the deliberate deferrals.

/// The ungraded rows of one run, in the order they were reported.
struct UngradedRows {

    /// What a row says when its call site gave no reason. It reads as a defect in the
    /// run rather than as an empty column, which is the whole point of collecting these.
    static let noReasonGiven = "NO REASON GIVEN — the row went ungraded and nothing said why"

    private(set) var rows: [(id: String, reason: String)] = []

    /// Report a row the run could not grade. `reason` is what stopped it: too thin a
    /// sample, a population the engine cannot reach yet, a measurement that arrives with
    /// a later milestone.
    mutating func record(_ id: String, reason: String) {
        rows.append((id, reason.isEmpty ? Self.noReasonGiven : reason))
    }

    var isEmpty: Bool { rows.isEmpty }

    /// One line per row, the id padded so the reasons line up.
    var lines: [String] {
        let width = (rows.map(\.id.count).max() ?? 0) + 3
        return rows.map { row in
            var padded = row.id
            while padded.count < width { padded += " " }
            return padded + row.reason
        }
    }
}
