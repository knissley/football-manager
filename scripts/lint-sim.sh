#!/usr/bin/env bash
#
# lint-sim.sh — the determinism and purity lint for the FM* packages.
#
# ADR-0003 bans a short list of standard-library primitives inside the
# simulation: they are either unseeded, or seeded by an algorithm the standard
# library does not promise to keep stable. A game is stored as
# (initialState, seed, sliderConfig, decisionLog) and replayed on demand, so one
# of these reaching the engine corrupts saved history rather than merely failing
# a test. ADR-0004 bans the frameworks: the domain core is plain Swift so it can
# be tested anywhere and so no platform type leaks into a domain signature.
#
# Both were conventions with nothing enforcing them until this script existed.
#
# Two checks:
#
#   1. Banned primitives and framework imports in the Sources/ tree of every
#      FM* package.
#   2. `Hasher` in a golden test. Swift randomises its hash seed per process, so
#      a golden checksum built on Hasher cannot detect the drift it exists to
#      detect (ADR-0003, "What this cost us").
#
# Comments are stripped before matching, so prose *about* the ban — the doc
# comment on SplittableRandom that names `Int.random(in:using:)`, the one on each
# golden Checksum saying it is deliberately not `Hasher` — does not trip the
# lint. String literals are left alone: interpolation can hold real code, and a
# banned token in literal text is a false positive worth looking at.
#
# The stripper is not airtight, and a clean run is not proof. It walks a line at
# a time tracking only whether it is inside a line comment, a block comment, a
# string or a multi-line string, and it never rejoins what a comment split:
# `Date/* x */()` matches no rule, and neither does the same trick inside an
# import. Closing that would mean re-lexing the line once the comment came out,
# which is a Swift lexer and not a grep. A clean lint means no banned token was
# written plainly — the golden tests, the replay contract tests and review are
# what catch the rest.
#
# The `packages` array below is written out rather than globbed on purpose.
# FMPersistence is an FM* package that must *not* be scanned — SwiftData lives
# there by design (ADR-0004, rule 7) — so `Packages/FM*` would be the wrong
# check, not a shorter one. When FMAnalysis or FMNarrative lands, add it here;
# nothing else will.
#
# Usage:
#   scripts/lint-sim.sh              lint the tree
#   scripts/lint-sim.sh --self-test  lint the fixture tree instead, and compare
#                                    the hits against the expected list
#
# Prints `file:line: what` for every hit and exits 1; exits 0 on a clean tree,
# and exits 2 when it would otherwise have passed by scanning nothing.
#
# --self-test is what keeps the stripper honest. scripts/lint-sim-fixtures/ holds
# a Swift file per rule — never compiled, never scanned by the real lint — each
# carrying a plain hit plus the same token behind a line comment and inside a
# block comment, along with a negative control and the cases the stripper is
# asked to get right. Every hit the tree must produce is listed in
# scripts/lint-sim-fixtures/expected.txt as `path:line: rule-id`, and a
# difference in either direction fails. The self-test reports the rule id rather
# than the message, so the expectation pins which rule fired and not its wording.
# A new rule therefore needs a fixture and an expectation line.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

mode=lint
case "${1-}" in
    "") ;;
    --self-test) mode=self-test ;;
    -h | --help)
        echo "usage: scripts/lint-sim.sh [--self-test]"
        exit 0
        ;;
    *)
        echo "lint-sim: unknown argument: $1" >&2
        echo "usage: scripts/lint-sim.sh [--self-test]" >&2
        exit 2
        ;;
esac

packages=(FMCore FMRandom FMGeneration FMSimulation)

fixtures="scripts/lint-sim-fixtures"

# Files exempt from a single rule, as "<path> <rule-id>" pairs. Nothing on the
# current tree needs one: the seeded shuffle in FMRandom is declared as
# `func shuffle<T>(` and called as `shuffle(&copy)`, neither of which matches a
# rule below — the shuffle rules require the leading dot of a method call on a
# collection. The mechanism is here for the file that eventually needs it;
# widening it to turn a red lint green is the thing it must not be used for.
allowlist=()

# id <TAB> extended regex <TAB> what to say about a hit.
# `(^|[^A-Za-z0-9_])` rather than `\b` so the patterns are POSIX ERE and behave
# the same under BSD grep on a Mac as under GNU grep in CI.
rules=$(
    cat <<'RULES'
random	\.random\(	stdlib randomness — use SplittableRandom (ADR-0003)
sysrng	SystemRandomNumberGenerator	an unseeded generator — use SplittableRandom (ADR-0003)
shuffle	\.shuffled?\(\)	unseeded shuffle — use SplittableRandom.shuffle(_:) (ADR-0003)
shuffle-using	\.shuffled?\(using:	stdlib shuffle: seeded, but its algorithm is not promised stable across Swift versions (ADR-0003)
random-element	\.randomElement\(	unseeded pick — use SplittableRandom.pick(from:) (ADR-0003)
uuid	(^|[^A-Za-z0-9_])UUID\(	a random identity — use a typed ID (ADR-0003)
date	(^|[^A-Za-z0-9_])Date\(	a clock read — the sim takes time as a parameter (ADR-0003)
hasher	(^|[^A-Za-z0-9_])Hasher\(	Hasher is seeded per process — use FNV-1a (ADR-0003)
clock	(^|[^A-Za-z0-9_])(ContinuousClock|SuspendingClock|DispatchTime|ProcessInfo|getenv|clock_gettime)([^A-Za-z0-9_]|$)	a clock or environment read (ADR-0003)
foundation	^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)?import[[:space:]]+([a-z]+[[:space:]]+)?Foundation(Essentials)?([^A-Za-z0-9_]|$)	a Foundation import — the FM* modules are framework-free (ADR-0004)
dispatch	^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)?import[[:space:]]+([a-z]+[[:space:]]+)?Dispatch([^A-Za-z0-9_]|$)	import Dispatch — the FM* modules are framework-free (ADR-0004)
platform	^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)?import[[:space:]]+([a-z]+[[:space:]]+)?(SwiftData|SwiftUI|UIKit|AppKit|Combine|CoreGraphics|Glibc|Darwin|os)([^A-Za-z0-9_]|$)	a platform framework — only FMPersistence knows SwiftData exists (ADR-0004)
RULES
)

# Strips comments, keeping one output line per input line so grep -n still
# reports the source line number. String literals are passed through unchanged;
# they are only tracked so that // or /* inside one is not read as a comment.
strip_comments() {
    awk '
        BEGIN { inBlock = 0; inMulti = 0 }
        {
            line = $0; out = ""; i = 1; n = length(line); inStr = 0
            while (i <= n) {
                c = substr(line, i, 1)
                two = substr(line, i, 2)
                three = substr(line, i, 3)
                if (inMulti) {
                    if (three == "\"\"\"") { inMulti = 0; out = out three; i += 3 }
                    else { out = out c; i++ }
                    continue
                }
                if (inBlock) {
                    if (two == "*/") { inBlock = 0; out = out "  "; i += 2 }
                    else { out = out " "; i++ }
                    continue
                }
                if (inStr) {
                    if (c == "\\") { out = out two; i += 2 }
                    else { if (c == "\"") inStr = 0; out = out c; i++ }
                    continue
                }
                if (three == "\"\"\"") { inMulti = 1; out = out three; i += 3; continue }
                if (two == "//") { break }
                if (two == "/*") { inBlock = 1; out = out "  "; i += 2; continue }
                if (c == "\"") { inStr = 1; out = out c; i++; continue }
                out = out c; i++
            }
            print out
        }
    ' "$1"
}

is_allowed() {
    local file=$1 rule=$2 entry
    for entry in ${allowlist[@]+"${allowlist[@]}"}; do
        [ "$entry" = "$file $rule" ] && return 0
    done
    return 1
}

# The lint proper says what is wrong with the line; the self-test pins which rule
# fired. Same scan either way, only the text after the line number differs.
hit_text() {
    if [ "$mode" = self-test ]; then
        printf '%s' "$1"
    else
        printf '%s' "$2"
    fi
}

hits=0
found=""

# Collected rather than printed as they are found, so the output can come out in
# file-then-line order instead of rule order.
report() {
    found="$found$1"$'\n'
    hits=$((hits + 1))
}

scan_sources() {
    local file code id pattern message hit
    for file in "$@"; do
        code=$(strip_comments "$file")
        while IFS=$'\t' read -r id pattern message; do
            [ -n "$id" ] || continue
            is_allowed "$file" "$id" && continue
            while IFS= read -r hit; do
                [ -n "$hit" ] || continue
                report "$file:${hit%%:*}: $(hit_text "$id" "$message")"
            done < <(printf '%s\n' "$code" | grep -nE -- "$pattern" || true)
        done <<<"$rules"
    done
}

scan_goldens() {
    local file code hit message
    message="Hasher in a golden test — its seed is randomised per process,"
    message="$message so the golden cannot detect drift (ADR-0003)"
    for file in "$@"; do
        code=$(strip_comments "$file")
        while IFS= read -r hit; do
            [ -n "$hit" ] || continue
            report "$file:${hit%%:*}: $(hit_text golden-hasher "$message")"
        done < <(printf '%s\n' "$code" |
            grep -nE -- '(^|[^A-Za-z0-9_])Hasher([^A-Za-z0-9_]|$)' || true)
    done
}

# --- --self-test: lint the fixture tree, compare against the expected list ---

if [ "$mode" = self-test ]; then
    expected="$fixtures/expected.txt"

    if [ ! -f "$expected" ]; then
        echo "lint-sim: $expected is missing — nothing to compare the fixtures against" >&2
        exit 2
    fi

    fixture_sources=()
    while IFS= read -r file; do
        fixture_sources+=("$file")
    done < <(find "$fixtures/sources" -name '*.swift' 2>/dev/null | sort)

    fixture_goldens=()
    while IFS= read -r file; do
        fixture_goldens+=("$file")
    done < <(find "$fixtures/goldens" -name '*Golden*Tests.swift' 2>/dev/null | sort)

    if [ "${#fixture_sources[@]}" -eq 0 ] || [ "${#fixture_goldens[@]}" -eq 0 ]; then
        echo "lint-sim: the fixture tree under $fixtures/ is missing or empty" >&2
        exit 2
    fi

    scan_sources "${fixture_sources[@]}"
    scan_goldens "${fixture_goldens[@]}"

    actual=$(printf '%s' "$found" | sort -t: -k1,1 -k2,2n)
    want=$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$expected" |
        sort -t: -k1,1 -k2,2n)

    if [ "$actual" = "$want" ]; then
        echo "lint-sim: self-test clean — $hits hit(s) from" \
            "${#fixture_sources[@]} source fixtures and" \
            "${#fixture_goldens[@]} golden fixture(s), all of them expected."
        exit 0
    fi

    echo "lint-sim: SELF-TEST FAILED — the fixture tree did not lint as $expected says." >&2
    echo "  '-' was expected and did not fire; '+' fired and was not expected." >&2
    { diff <(printf '%s\n' "$want") <(printf '%s\n' "$actual") || true; } |
        sed -n 's/^</  -/p; s/^>/  +/p' >&2
    exit 1
fi

# --- 1. banned primitives and framework imports in the FM* sources ----------

sources=()
for package in "${packages[@]}"; do
    dir="Packages/$package/Sources"
    if [ ! -d "$dir" ]; then
        echo "lint-sim: $dir does not exist — the lint would pass by scanning nothing" >&2
        exit 2
    fi
    before=${#sources[@]}
    while IFS= read -r file; do
        sources+=("$file")
    done < <(find "$dir" -name '*.swift' | sort)
    # Counted per package, not just in total: with four packages in the array,
    # three of them holding sources keeps the total non-zero and drops the fourth
    # in silence.
    if [ "${#sources[@]}" -eq "$before" ]; then
        echo "lint-sim: $dir holds no .swift files — $package would be scanned as nothing" >&2
        exit 2
    fi
done

if [ "${#sources[@]}" -eq 0 ]; then
    echo "lint-sim: found no Swift sources to scan" >&2
    exit 2
fi

scan_sources "${sources[@]}"

# --- 2. no Hasher in a golden test -----------------------------------------

goldens=()
while IFS= read -r file; do
    goldens+=("$file")
done < <(find Packages -name '*Golden*Tests.swift' | sort)

if [ "${#goldens[@]}" -eq 0 ]; then
    echo "lint-sim: found no *Golden*Tests.swift — the golden check would pass by scanning nothing" >&2
    exit 2
fi

scan_goldens "${goldens[@]}"

# --- verdict ----------------------------------------------------------------

if [ "$hits" -gt 0 ]; then
    printf '%s' "$found" | sort -t: -k1,1 -k2,2n
    echo
    echo "lint-sim: $hits violation(s) in ${#sources[@]} source files and ${#goldens[@]} golden test files."
    exit 1
fi

echo "lint-sim: clean — ${#sources[@]} source files, ${#goldens[@]} golden test files."
