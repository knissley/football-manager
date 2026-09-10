#!/usr/bin/env bash
#
# test-census.sh — what kind of thing the test suite asserts, counted.
#
# CLAUDE.md rule 11 says football tests come first and every test says what kind
# it is. A principle nobody measures is a principle that gets skimmed: the suite
# reached five hundred and sixty-two green tests with three of them asserting
# wrong football, and the estimate of how much of it was football at all came
# from reading it, because nothing counted.
#
# Every `@Test` in every test target carries exactly one kind tag — `.football`,
# `.contract`, `.unit` or `.pin`, declared in that target's `TestTags.swift` and
# defined in CLAUDE.md under *Conventions → Tests*. This script counts them per
# target and per suite, prints the shares, and fails on a test that carries none.
#
# It is a text scan, not a Swift parser. It reads a line that *begins* with
# `@Test` as an attribute and accumulates it until its parentheses balance, which
# is what makes a multi-line attribute and a parameterised test count once each.
# Lines inside a `"""` string and inside a `/* */` block are skipped, so prose
# about a `@Test` does not become one. A `@Test` written any other way — after a
# semicolon, say — is meant to be missed here and caught in review; the suite
# totals printed at the end are the check that the scan found what `swift test`
# runs.
#
# Usage:
#   scripts/test-census.sh              census the tree
#   scripts/test-census.sh --list       one line per test: file:line: kind
#   scripts/test-census.sh --self-test  census the fixture tree instead, and
#                                       compare it against the expected list
#
# Exits 0 on a fully tagged tree, 1 when a test carries no kind or carries two,
# and 2 when it would otherwise have passed by scanning nothing.
#
# --self-test is what keeps the scanner honest. scripts/test-census-fixtures/
# holds Swift files that are never compiled and never part of a package: one
# fully tagged, one not, and the shapes the scan has to get right — a multi-line
# attribute, a parameterised test, a tag on the suite rather than the test, and
# `@Test` written inside a comment and inside a multi-line string. Every test the
# tree must produce is listed in scripts/test-census-fixtures/expected.txt as
# `path:line: kind`, and a difference in either direction fails, so a test that
# quietly stops being counted is caught as loudly as one counted twice.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

mode=census
case "${1-}" in
    "") ;;
    --list) mode=list ;;
    --self-test) mode=self-test ;;
    -h | --help)
        echo "usage: scripts/test-census.sh [--list | --self-test]"
        exit 0
        ;;
    *)
        echo "test-census: unknown argument: $1" >&2
        echo "usage: scripts/test-census.sh [--list | --self-test]" >&2
        exit 2
        ;;
esac

# Written out rather than globbed, for the same reason lint-sim.sh writes its
# package list out: a target that disappears from the tree should fail this
# script rather than quietly drop out of the census. Add a line when a test
# target lands.
targets=$(
    cat <<'TARGETS'
FMRandom	Packages/FMRandom/Tests
FMCore	Packages/FMCore/Tests
FMGeneration	Packages/FMGeneration/Tests
FMSimulation	Packages/FMSimulation/Tests
simharness	Tools/simharness/Tests
TARGETS
)

fixtures="scripts/test-census-fixtures"

# Emits one record per @Test: kind, target, suite, file, line.
#
# `target` is the second path component under Packages/ or Tools/, and the
# containing directory for the fixture tree.
scan() {
    # POSIX awk only, and no POSIX character classes: mawk on a CI container and
    # BSD awk on a Mac both have to run this.
    awk -v OFS='\t' '
        function targetOf(path,   parts, n) {
            n = split(path, parts, "/")
            if (parts[1] == "Packages" || parts[1] == "Tools") return parts[2]
            return (n > 1) ? parts[n - 1] : parts[1]
        }

        function kindOf(text,   at, rest, stop, inner, found, kinds, i, k) {
            at = index(text, ".tags(")
            if (at == 0) return "untagged"
            rest = substr(text, at + 6)
            stop = index(rest, ")")
            inner = (stop > 0) ? substr(rest, 1, stop - 1) : rest
            split("football contract unit pin", kinds, " ")
            found = ""
            for (i = 1; i <= 4; i++) {
                k = kinds[i]
                if (index(inner, "." k) > 0) found = (found == "") ? k : "multiple"
            }
            return (found == "") ? "untagged" : found
        }

        function quoted(text,   at, rest, stop) {
            at = index(text, "\"")
            if (at == 0) return ""
            rest = substr(text, at + 1)
            stop = index(rest, "\"")
            return (stop > 0) ? substr(rest, 1, stop - 1) : rest
        }

        FNR == 1 {
            suite = ""; pending = ""; inMulti = 0; inBlock = 0
            target = targetOf(FILENAME)
        }

        # Skip what is not code: a multi-line string, and a block comment. The
        # string delimiters are counted per line, so one that opens and closes on
        # the same line leaves the state where it was.
        {
            line = $0
            if (inMulti) {
                if (gsub(/"""/, "&", line) % 2 == 1) inMulti = 0
                next
            }
            if (inBlock) {
                if (index(line, "*/") > 0) inBlock = 0
                next
            }
            if (line ~ /^[ \t]*\/\*/ && index(line, "*/") == 0) { inBlock = 1; next }
            if (gsub(/"""/, "&", line) % 2 == 1) { inMulti = 1; next }
        }

        # A suite is named by its @Suite attribute when it has one, and by the
        # type otherwise, so a bare struct of tests still lands in a row.
        /^[ \t]*@Suite[ \t]*\(/ { pending = quoted($0); next }

        /^[ \t]*(public[ \t]+)?(final[ \t]+)?(struct|class|enum|actor)[ \t]/ {
            if (pending != "") {
                suite = pending
                pending = ""
            } else {
                match($0, /(struct|class|enum|actor)[ \t]+[A-Za-z_][A-Za-z0-9_]*/)
                name = substr($0, RSTART, RLENGTH)
                sub(/^[a-z]+[ \t]+/, "", name)
                suite = name
            }
            next
        }

        /^[ \t]*@Test([ \t]|\(|$)/ {
            start = FNR
            text = $0
            depth = gsub(/\(/, "(", text) - gsub(/\)/, ")", text)
            text = $0
            while (depth > 0 && (getline > 0)) {
                text = text " " $0
                depth += gsub(/\(/, "(", $0) - gsub(/\)/, ")", $0)
            }
            print kindOf(text), target, (suite == "" ? "(no suite)" : suite), FILENAME, start
        }
    ' "$@"
}

# --- collect the files -------------------------------------------------------

files=()
order=()

if [ "$mode" = self-test ]; then
    while IFS= read -r file; do
        files+=("$file")
    done < <(find "$fixtures" -name '*.swift' 2>/dev/null | sort)
    if [ "${#files[@]}" -eq 0 ]; then
        echo "test-census: the fixture tree under $fixtures/ is missing or empty" >&2
        exit 2
    fi
else
    while IFS=$'\t' read -r name dir; do
        [ -n "$name" ] || continue
        if [ ! -d "$dir" ]; then
            echo "test-census: $dir does not exist — $name would be censused as nothing" >&2
            exit 2
        fi
        before=${#files[@]}
        while IFS= read -r file; do
            files+=("$file")
        done < <(find "$dir" -name '*.swift' | sort)
        if [ "${#files[@]}" -eq "$before" ]; then
            echo "test-census: $dir holds no .swift files — $name would be censused as nothing" >&2
            exit 2
        fi
        order+=("$name")
    done <<<"$targets"
fi

records=$(scan "${files[@]}")

if [ -z "$records" ]; then
    echo "test-census: found no @Test declarations — the census would pass by counting nothing" >&2
    exit 2
fi

# --- --list and --self-test --------------------------------------------------

listing=$(printf '%s\n' "$records" | awk -F'\t' '{ printf "%s:%s: %s\n", $4, $5, $1 }' |
    sort -t: -k1,1 -k2,2n)

if [ "$mode" = list ]; then
    printf '%s\n' "$listing"
    exit 0
fi

if [ "$mode" = self-test ]; then
    expected="$fixtures/expected.txt"
    if [ ! -f "$expected" ]; then
        echo "test-census: $expected is missing — nothing to compare the fixtures against" >&2
        exit 2
    fi
    # `|| true` because grep exits 1 when every line is filtered out, and under
    # `set -e` that would end the script here with no explanation at all.
    want=$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$expected" |
        sort -t: -k1,1 -k2,2n || true)
    if [ -z "$want" ]; then
        echo "test-census: $expected names no tests — there is nothing to compare against" >&2
        exit 2
    fi
    if [ "$listing" = "$want" ]; then
        counted=$(printf '%s\n' "$listing" | wc -l | tr -d ' ')
        echo "test-census: self-test clean — $counted test(s) across ${#files[@]} fixture" \
            "files, each the kind $expected says."
        exit 0
    fi
    echo "test-census: SELF-TEST FAILED — the fixture tree did not census as $expected says." >&2
    echo "  '-' was expected and did not appear; '+' appeared and was not expected." >&2
    { diff <(printf '%s\n' "$want") <(printf '%s\n' "$listing") || true; } |
        sed -n 's/^</  -/p; s/^>/  +/p' >&2
    exit 1
fi

# --- the census --------------------------------------------------------------

printf '%s\n' "$records" | awk -F'\t' -v order="${order[*]}" '
    function share(count, total) {
        return (total > 0) ? sprintf("%5.1f%%", 100 * count / total) : "     —"
    }
    function cell(count, total) {
        return sprintf("%4d %s", count, share(count, total))
    }
    BEGIN {
        split("football contract unit pin untagged multiple", kinds, " ")
        n = split(order, targetOrder, " ")
    }
    {
        kind = $1; target = $2; suite = $3
        total[target]++
        grand++
        byTarget[target, kind]++
        byKind[kind]++
        key = target SUBSEP suite
        if (!(key in seenSuite)) {
            seenSuite[key] = 1
            suiteCount[target]++
            suiteName[target, suiteCount[target]] = suite
        }
        bySuite[key, kind]++
        suiteTotal[key]++
    }
    END {
        printf "test census — %d @Test declarations in %d targets\n\n", grand, n

        printf "  %-14s %10s %10s %10s %10s %10s %7s\n", \
            "target", "football", "contract", "unit", "pin", "untagged", "total"
        for (i = 1; i <= n; i++) {
            t = targetOrder[i]
            printf "  %-14s %10s %10s %10s %10s %10s %7d\n", t, \
                cell(byTarget[t, "football"], total[t]), \
                cell(byTarget[t, "contract"], total[t]), \
                cell(byTarget[t, "unit"], total[t]), \
                cell(byTarget[t, "pin"], total[t]), \
                cell(byTarget[t, "untagged"] + byTarget[t, "multiple"], total[t]), \
                total[t]
        }
        printf "  %-14s %10s %10s %10s %10s %10s %7d\n", "all", \
            cell(byKind["football"], grand), cell(byKind["contract"], grand), \
            cell(byKind["unit"], grand), cell(byKind["pin"], grand), \
            cell(byKind["untagged"] + byKind["multiple"], grand), grand

        for (i = 1; i <= n; i++) {
            t = targetOrder[i]
            printf "\n%s — %d tests in %d suites\n", t, total[t], suiteCount[t]
            printf "  %-48s %8s %8s %8s %5s %8s %5s\n", \
                "suite", "football", "contract", "unit", "pin", "untagged", "total"
            for (j = 1; j <= suiteCount[t]; j++) {
                s = suiteName[t, j]
                key = t SUBSEP s
                printf "  %-48s %8d %8d %8d %5d %8d %5d\n", substr(s, 1, 48), \
                    bySuite[key, "football"], bySuite[key, "contract"], \
                    bySuite[key, "unit"], bySuite[key, "pin"], \
                    bySuite[key, "untagged"] + bySuite[key, "multiple"], suiteTotal[key]
            }
        }
    }
'

untagged=$(printf '%s\n' "$records" | awk -F'\t' '$1 == "untagged" || $1 == "multiple"')

if [ -n "$untagged" ]; then
    echo
    printf '%s\n' "$untagged" | awk -F'\t' '
        {
            if ($1 == "multiple")
                why = "names two kinds — a test is one of football, contract, unit or pin"
            else
                why = "no kind tag — add .tags(.football), .tags(.contract), .tags(.unit) or .tags(.pin)"
            printf "%s:%s: %s\n", $4, $5, why
        }' |
        sort -t: -k1,1 -k2,2n
    count=$(printf '%s\n' "$untagged" | wc -l | tr -d ' ')
    echo
    echo "test-census: $count test(s) do not say what kind they are (CLAUDE.md rule 11)."
    exit 1
fi

echo
echo "test-census: every test says what kind it is."
