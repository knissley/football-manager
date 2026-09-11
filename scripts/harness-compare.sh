#!/usr/bin/env bash
#
# harness-compare.sh — what moved between two simharness captures
#
# Every fix in the backlog runs `simharness --games 400` at two seeds before and after,
# and the reviewer's question is always the same: which rows moved, and did any of them
# change standing? Until this existed the answer came from `diff`, and `diff` answers a
# different question — it reports lines, and a line carries a value, a band, a verdict, a
# season and a source at once. Two failures follow from that, and both have been paid for:
#
#   1. A row can flip verdict while its printed value does not move. `diff` shows the
#      line, but a reviewer scanning the value column — which is what a calibration
#      argument is about — reads "unchanged" and moves on. Three such rows were inside one
#      branch's headline flip count before anybody noticed, and the count was wrong by
#      three in a document whose purpose is to let a reader check the change.
#   2. A row can move without changing verdict, which is the ordinary case and which
#      `diff` reports at exactly the same volume as the case above.
#
# So this reads the two captures as tables rather than as text, joins them row by row, and
# sorts what it finds into categories a reviewer can act on — the verdict flips first, and
# the flips whose printed value did not move first of all.
#
# It reports; it does not grade. The exit status is 0 whenever both captures could be
# read, whatever it found, so it is safe in a pipeline. It exits 2 when it could not read
# one of them, because an empty report from an unparsed capture would read as "nothing
# moved".
#
# Usage:
#   scripts/harness-compare.sh <before.txt> <after.txt>
#   scripts/harness-compare.sh --self-test
#
# The captures are whatever `simharness` printed: `--no-timing` output, a full run with
# its Budget block, or a CI artifact. Only the graded rows are read — a line with a label,
# a value, a band, a verdict and a season — and everything else is ignored.
#
# ## A note on the identical-value category
#
# The harness now prints enough decimals for a row's value to imply its verdict: a value
# printed as one of its band's endpoints is in band, and a row graded outside its band
# prints the decimals that put it outside. So between two captures taken from a harness
# that does that, a verdict flip on an identical printed value can only come from the
# band moving, from a row's season or gate changing, or from a row losing its sample —
# each of which this names. Against a capture taken before it, the category is the
# rounding artefact it was written for, and it is worth reading as one.
#
# ## The self-test
#
# `--self-test` runs the comparison over `scripts/harness-compare-fixtures/`, two
# hand-written captures carrying one row of every category — a flip on an identical
# printed value, a flip that moved, a move that did not flip, a band that moved, a row
# that lost its sample, a row on one side only, and two rows that share a label and are
# told apart by their season, as the rule-sensitive variants in Targets.swift are — and
# fails on any difference from the expected report. It needs no toolchain and no harness
# run, so CI runs it on every push.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
    echo "usage: scripts/harness-compare.sh <before.txt> <after.txt>"
    echo "       scripts/harness-compare.sh --self-test"
}

note() { printf '%s\n' "$*" >&2; }

# What a capture says about itself: the run it was, and the league it played in. Two
# captures of different runs can be compared line by line and mean nothing, so this is
# printed at the top of every report and a difference is called out.
describe() {
    awk '
        NR <= 6 {
            if (match($0, /[0-9]+ games, seed [0-9]+/)) run = substr($0, RSTART, RLENGTH)
            if ($1 == "world" && $2 == "checksum") world = $3
        }
        END {
            printf "%s, world %s\n", (run == "" ? "unknown run" : run),
                (world == "" ? "unknown" : world)
        }
    ' "$1"
}

compare() {
    local before=$1 after=$2
    for file in "$before" "$after"; do
        if [ ! -r "$file" ]; then
            note "harness-compare: cannot read $file"
            exit 2
        fi
    done

    echo "harness-compare: $before -> $after"
    echo "  before: $(describe "$before")"
    echo "  after:  $(describe "$after")"

    awk '
        BEGIN { FS = "  +" }

        # A graded row is a label, a value, a band, a verdict, a season and a source key,
        # in that order, separated by runs of two or more spaces — the shape `report` in
        # Tools/simharness/Sources/simharness/main.swift prints. The value field is a
        # decimal number whose digits after the point vary by row, or an em dash for a row
        # with no sample, so it is the two fields either side of it that identify a row.
        {
            if (NF < 6) next
            name = $2 " [" $6 "]"
            value = $3
            band = $4
            mark = $5
            if (band !~ /^([0-9]+(\.[0-9]+)?-[0-9]+(\.[0-9]+)?|none)$/) next
            if (mark !~ /^(ok|OFF|\(ok\)|\(OFF\)|stale|unsourced|n\/a)$/) next
            # Two rows can share a label — a rule-sensitive row has a variant per rulebook
            # — so the nth row of a name on one side is matched with the nth on the other.
            if (NR == FNR) {
                seenBefore[name]++
                key = name "#" seenBefore[name]
                orderBefore[++countBefore] = key
                valueBefore[key] = value; bandBefore[key] = band; markBefore[key] = mark
            } else {
                seenAfter[name]++
                key = name "#" seenAfter[name]
                orderAfter[++countAfter] = key
                valueAfter[key] = value; bandAfter[key] = band; markAfter[key] = mark
            }
        }

        function shown(key,   name) { name = key; sub(/#[0-9]+$/, "", name); return name }
        # A band moves when its numbers move, not when its printing does. A row graded
        # outside its band prints the decimals that put it outside, and both endpoints
        # print at the same precision as the value beside them, so one band reads
        # "3.9-4.6" on one row and "3.90-4.60" on another. Comparing the two as text
        # calls a display change a retune.
        function sameBand(before, after,   low, high) {
            if (before == after) return 1
            if (before == "none" || after == "none") return 0
            split(before, low, "-")
            split(after, high, "-")
            return (low[1] + 0 == high[1] + 0) && (low[2] + 0 == high[2] + 0)
        }
        function moved(before, after) { return before == after ? before : before " -> " after }
        function line(key, before, after, beforeBand, afterBand) {
            return sprintf("    %s   %s   %s   band %s", shown(key),
                moved(before, after), moved(markBefore[key], markAfter[key]),
                moved(beforeBand, afterBand))
        }
        function record(category, text) {
            found[category]++
            report[category, found[category]] = text
        }
        function section(category, heading,   i) {
            printf "\n  %s (%d)\n", heading, found[category] + 0
            for (i = 1; i <= found[category]; i++) print report[category, i]
        }

        END {
            for (i = 1; i <= countBefore; i++) {
                key = orderBefore[i]
                if (!(key in valueAfter)) {
                    record("gone",
                        sprintf("    %s   %s   %s   band %s", shown(key), valueBefore[key],
                            markBefore[key], bandBefore[key]))
                    continue
                }
                matched[key] = 1
                text = line(key, valueBefore[key], valueAfter[key], bandBefore[key],
                    bandAfter[key])
                # A row with no sample prints an em dash where its value would be, so a
                # value with no digit in it is a row the run could not measure.
                sampled = (valueBefore[key] ~ /[0-9]/)
                sampledAfter = (valueAfter[key] ~ /[0-9]/)
                if (sampled != sampledAfter) {
                    record("sample", text)
                } else if (!sameBand(bandBefore[key], bandAfter[key])) {
                    record("band", text)
                } else if (markBefore[key] != markAfter[key]) {
                    if (valueBefore[key] == valueAfter[key]) record("silent", text)
                    else record("flipped", text)
                } else if (valueBefore[key] != valueAfter[key]) {
                    record("value", text)
                } else {
                    unchanged++
                }
            }
            for (i = 1; i <= countAfter; i++) {
                key = orderAfter[i]
                if (key in matched) continue
                record("new",
                    sprintf("    %s   %s   %s   band %s", shown(key), valueAfter[key],
                        markAfter[key], bandAfter[key]))
            }

            printf "  %d graded rows before, %d after\n", countBefore, countAfter
            if (countBefore == 0 || countAfter == 0) {
                print "\n  No graded rows were read on one side. Either the capture is not a"
                print "  simharness run or the table has changed shape and this script needs"
                print "  updating."
                exit 2
            }

            section("silent", "verdict changed while the printed value did not")
            section("band", "the band itself moved")
            section("sample", "a row lost or gained its sample")
            section("flipped", "verdict changed")
            section("value", "value changed, verdict did not")
            section("gone", "only in the before run")
            section("new", "only in the after run")
            printf "\n  unchanged (%d)\n", unchanged + 0
        }
    ' "$before" "$after"
}

self_test() {
    local fixtures=scripts/harness-compare-fixtures
    local got status=0
    local difference
    difference=$(mktemp "${TMPDIR:-/tmp}/harness-compare.XXXXXX")
    # Relative paths, from the repository root, so the report names what the expected
    # report names wherever the script was called from.
    cd "$root"
    got=$(compare "$fixtures/before.txt" "$fixtures/after.txt") || status=$?
    if [ "$status" -ne 0 ]; then
        note "harness-compare: the self-test's own comparison exited $status, expected 0"
        printf '%s\n' "$got" >&2
        rm -f "$difference"
        return 1
    fi
    if ! printf '%s\n' "$got" | diff -u "$fixtures/expected.txt" - >"$difference"; then
        note "harness-compare: SELF-TEST FAILED — the report is not the expected one:"
        sed 's/^/  /' "$difference" >&2
        rm -f "$difference"
        return 1
    fi
    rm -f "$difference"
    note "harness-compare: self-test clean — every category reported as expected."
    return 0
}

case "${1-}" in
    "")
        note "harness-compare: two captures are required"
        usage >&2
        exit 2
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    --self-test)
        [ $# -eq 1 ] || {
            usage >&2
            exit 2
        }
        self_test
        ;;
    -*)
        note "harness-compare: unknown argument: $1"
        usage >&2
        exit 2
        ;;
    *)
        [ $# -eq 2 ] || {
            usage >&2
            exit 2
        }
        compare "$1" "$2"
        ;;
esac
