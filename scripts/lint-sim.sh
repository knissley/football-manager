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
# Three checks:
#
#   1. Banned primitives and framework imports in the Sources/ tree of every
#      FM* package.
#   2. `Hasher` in a golden test. Swift randomises its hash seed per process, so
#      a golden checksum built on Hasher cannot detect the drift it exists to
#      detect (ADR-0003, "What this cost us").
#   3. Process history in a comment, in any Sources/ or Tests/ tree under
#      Packages/ or Tools/ — an issue number, a wave, "the audit", "the review",
#      "orchestrator". A comment that says which piece of work a line came out of
#      stops meaning anything the day that work closes, and it never told the
#      reader why the code is the way it is. Say that instead, with the rule or
#      the data it comes from, and leave the history in the commit message.
#
# Checks 1 and 2 read the code with comments stripped, so prose *about* the ban —
# the doc comment on SplittableRandom that names `Int.random(in:using:)`, the one
# on each golden Checksum saying it is deliberately not `Hasher` — does not trip
# the lint. String literals are left alone: interpolation can hold real code, and
# a banned token in literal text is a false positive worth looking at.
#
# Check 3 reads the mirror image: the comment text, with code and string literals
# blanked. So a test's display name may say anything, and so may a register whose
# entries are strings; only what a reader meets as prose is scanned.
#
# Check 3 has two structural exceptions, both recognised from the shape of the
# code rather than from anything written in the comment:
#
#   - the doc comment on a test whose `@Test` attribute carries `.pin`. A pin
#     exists to be replaced, and naming the issue that replaces it is the only
#     way a reader knows the pin is not the intended end state. The exemption is
#     the run of `///` lines immediately above the attribute — a `// MARK:` line
#     or a blank line ends the run, so a section header is not covered.
#   - a register of cases the engine cannot reach yet, opened by the marker
#     `lint-sim: unreachable-register` in a comment. The exemption is the block
#     the marker is in plus the declaration that block introduces, to the bracket
#     that closes it, so per-case comments inside the register are covered.
#
# and a baseline, scripts/lint-sim-baseline.txt, carrying the hits that were in
# the tree when the check landed so it could land before the sweep that clears
# them. A hit whose key is carried passes; a hit whose key is not fails; a
# carried key that matches nothing is reported, not failed, so the file burns
# down. The key is the comment's own text, not its line number, because a line
# number moves with every edit above it.
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
#   scripts/lint-sim.sh --baseline   print the baseline the tree would need for
#                                    check 3 to pass. For filling the file the
#                                    first time and for reading what is left in
#                                    it — never for quieting a new hit
#
# Prints `file:line: what` for every hit and exits 1; exits 0 on a clean tree,
# and exits 2 when it would otherwise have passed by scanning nothing.
#
# --self-test is what keeps the stripper honest. scripts/lint-sim-fixtures/ holds
# a Swift file per rule — never compiled, never scanned by the real lint — each
# carrying a plain hit plus the same token behind a line comment and inside a
# block comment, along with a negative control and the cases the stripper is
# asked to get right. comments/ does the same for check 3, against the fixture
# baseline in scripts/lint-sim-fixtures/baseline.txt rather than the real one.
# Every hit the tree must produce is listed in
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
    --baseline) mode=baseline ;;
    -h | --help)
        echo "usage: scripts/lint-sim.sh [--self-test | --baseline]"
        exit 0
        ;;
    *)
        echo "lint-sim: unknown argument: $1" >&2
        echo "usage: scripts/lint-sim.sh [--self-test | --baseline]" >&2
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

# Check 3's rules, matched against the comment view and case-insensitively. None
# of the five reads differently in capitals — "Wave 4" opening a sentence, "The
# review", "an AUDIT" — and an issue number has no case at all.
#
# The messages below say what to write instead. They deliberately carry no issue
# number themselves; the reason this rule exists belongs in the header and in
# docs/tools.md, not in a string that would have to be reworded when the thing it
# names is closed.
comment_rules=$(
    cat <<'COMMENT_RULES'
history-issue	#[0-9]+	an issue number in a comment — it stops meaning anything the day the issue closes; say why the code is this way and name the gotcha, and put the history in the commit message
history-wave	(^|[^A-Za-z0-9_])wave [0-9]	a wave number in a comment — the backlog's filing order is not a fact about this code
history-audit	(^|[^A-Za-z0-9_])audit([^A-Za-z0-9_]|$)	"the audit" in a comment — say what is true of the code and cite the rule or the data, not who found it
history-review	(^|[^A-Za-z0-9_])the review([^A-Za-z0-9_]|$)	"the review" in a comment — a review is a conversation, and the reader of this line was not in it
history-orchestrator	(^|[^A-Za-z0-9_])orchestrator([^A-Za-z0-9_]|$)	how the work was dispatched is not a fact about the code
COMMENT_RULES
)

# The marker that opens a register of cases the engine cannot reach yet. Written
# in a comment, it exempts the block it is in and the declaration that block
# introduces, so the entries may name the issue that makes each case reachable.
# It is spelled with the script's own name so a reader who meets it knows what
# honours it and can find this file.
comment_marker="lint-sim: unreachable-register"

# Today's hits, carried so the rule could land before the sweep that clears them.
# A hit whose key is in here passes; anything else fails.
comment_baseline="scripts/lint-sim-baseline.txt"

# One state machine, two views of a file, always one output line per input line
# so grep -n still reports the source line number.
#
#   code     comments blanked, string literals passed through unchanged. What
#            checks 1 and 2 read. Literals are left alone because interpolation
#            can hold real code, and a banned token in literal text is a false
#            positive worth looking at; they are tracked only so that // or /*
#            inside one is not read as a comment.
#   comment  the mirror image — comment text kept, code and string literals
#            blanked — with the lines the two structural exceptions cover blanked
#            as well. What check 3 reads.
#
# The two views come out of one pass because they are the same parse. Written as
# two programs they would drift, and the stripper is the part of this script that
# --self-test exists to keep honest.
view_of() {
    awk -v view="$2" -v marker="$comment_marker" '
        function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
        function isDoc(i) { return substr(trim(RAW[i]), 1, 3) == "///" }
        function commentOnly(i) { return trim(BRC[i]) == "" && trim(CMT[i]) != "" }
        BEGIN { inBlock = 0; inMulti = 0; last = 0 }
        {
            line = $0; i = 1; n = length(line); inStr = 0
            code = ""; cmt = ""; brc = ""
            while (i <= n) {
                c = substr(line, i, 1)
                two = substr(line, i, 2)
                three = substr(line, i, 3)
                if (inMulti) {
                    if (three == "\"\"\"") { inMulti = 0; code = code three; cmt = cmt "   "; brc = brc "   "; i += 3 }
                    else { code = code c; cmt = cmt " "; brc = brc " "; i++ }
                    continue
                }
                if (inBlock) {
                    if (two == "*/") { inBlock = 0; code = code "  "; cmt = cmt "  "; brc = brc "  "; i += 2 }
                    else { code = code " "; cmt = cmt c; brc = brc " "; i++ }
                    continue
                }
                if (inStr) {
                    if (c == "\\") { code = code two; cmt = cmt "  "; brc = brc "  "; i += 2 }
                    else { if (c == "\"") inStr = 0; code = code c; cmt = cmt " "; brc = brc " "; i++ }
                    continue
                }
                if (three == "\"\"\"") { inMulti = 1; code = code three; cmt = cmt "   "; brc = brc "   "; i += 3; continue }
                if (two == "//") { cmt = cmt substr(line, i); break }
                if (two == "/*") { inBlock = 1; code = code "  "; cmt = cmt "  "; brc = brc "  "; i += 2; continue }
                if (c == "\"") { inStr = 1; code = code c; cmt = cmt " "; brc = brc " "; i++; continue }
                code = code c; cmt = cmt " "; brc = brc c; i++
            }
            if (view == "code") { print code; next }
            RAW[NR] = line; CMT[NR] = cmt; BRC[NR] = brc; last = NR
        }
        END {
            if (view == "code") exit

            # Exception 1 — the doc comment on a test tagged .pin. Recognised
            # from the code side: a line holding @Test, the attribute list that
            # follows it up to the declaration it decorates, and `.pin` somewhere
            # in that list. The exemption is the run of `///` lines immediately
            # above, all of them, and only those: a `// MARK:` line or a blank
            # line ends the run, so a section header above a pinned test is not
            # covered by it.
            for (t = 1; t <= last; t++) {
                if (BRC[t] !~ /@Test/) continue
                attrs = ""
                for (f = t; f <= last && f < t + 40; f++) {
                    if (BRC[f] ~ /(^|[^A-Za-z0-9_])func[[:space:]]/) break
                    attrs = attrs " " BRC[f]
                }
                if (attrs !~ /\.pin([^A-Za-z0-9_]|$)/) continue
                for (b = t - 1; b >= 1 && isDoc(b); b--) EXEMPT[b] = 1
            }

            # Exception 2 — a register of cases the engine cannot reach yet,
            # opened by the marker. The exemption is the comment block the marker
            # is written in plus the declaration that block introduces, to the
            # bracket that closes it, so the per-case doc comments inside a
            # register are covered without a marker each. Brackets are counted on
            # the code side with literals blanked, and one of {, [ or ( counts the
            # same as another: a register is as often a dictionary literal as a
            # braced declaration. The 400-line cap is there so a miscount ends.
            for (m = 1; m <= last; m++) {
                if (marker == "" || index(CMT[m], marker) == 0) continue
                s = m; while (s > 1 && commentOnly(s - 1)) s--
                e = m; while (e < last && commentOnly(e + 1)) e++
                for (i = s; i <= e; i++) EXEMPT[i] = 1
                d = e + 1
                while (d <= last && trim(BRC[d]) == "") d++
                depth = 0
                for (i = d; i <= last && i < d + 400; i++) {
                    EXEMPT[i] = 1
                    k = BRC[i]
                    for (j = 1; j <= length(k); j++) {
                        ch = substr(k, j, 1)
                        if (ch == "{" || ch == "[" || ch == "(") depth++
                        else if (ch == "}" || ch == "]" || ch == ")") depth--
                    }
                    if (depth <= 0) break
                }
            }

            for (i = 1; i <= last; i++) print (i in EXEMPT) ? "" : CMT[i]
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
        code=$(view_of "$file" code)
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
        code=$(view_of "$file" code)
        while IFS= read -r hit; do
            [ -n "$hit" ] || continue
            report "$file:${hit%%:*}: $(hit_text golden-hasher "$message")"
        done < <(printf '%s\n' "$code" |
            grep -nE -- '(^|[^A-Za-z0-9_])Hasher([^A-Za-z0-9_]|$)' || true)
    done
}

# --- check 3: process history in a comment ----------------------------------

# The baseline's key is the comment text, not the line it is on. A line number
# moves with every edit above it, so a baseline keyed on one would go stale on
# any commit that touched an unrelated part of the file — and a baseline nobody
# can trust to be accurate is a baseline people regenerate, which is how a
# burn-down list turns into a rubber stamp. The text moves only when the comment
# is rewritten, which is the moment the line should leave the file anyway.
#
# What this costs: two hits with the same normalised text in one file collapse to
# one key, so one baseline line covers both. That is a real loss of precision and
# a deliberate one — the same sentence twice in a file is the same judgement
# twice — and the count the lint prints is of hits, not of keys, so the two are
# still counted separately.
normalise_comment() {
    sed -e 's/	/ /g' \
        -e 's/^[[:space:]]*//' \
        -e 's|^//*||' \
        -e 's/^\*\**//' \
        -e 's/[[:space:]][[:space:]]*/ /g' \
        -e 's/^ //' -e 's/ $//'
}

# `path <TAB> rule <TAB> key` per carried line, comments and blanks dropped. The
# `|| true` is not decoration: grep -v exits 1 when it selects nothing, which is
# what a baseline that has finally burned down to its own explanation does, and
# under `set -o pipefail` that would kill the script on the one day it should be
# celebrating.
baseline_keys() {
    local file=$1
    { grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$file" || true; } |
        awk -F'\t' 'NF >= 3 { print $1 "\t" $2 "\t" $3 }' | sort -u
}

comment_message() {
    printf '%s\n' "$comment_rules" | awk -F'\t' -v id="$1" '$1 == id { print $3 }'
}

# Collected as `path <TAB> line <TAB> rule <TAB> key` rows rather than reported
# directly, because what happens to a hit depends on the baseline, and the
# baseline is read once for all of them.
history_rows=""

scan_comments() {
    local file text id pattern message hit line key
    for file in "$@"; do
        text=$(view_of "$file" comment)
        while IFS=$'\t' read -r id pattern message; do
            [ -n "$id" ] || continue
            while IFS= read -r hit; do
                [ -n "$hit" ] || continue
                line=${hit%%:*}
                key=$(printf '%s' "${hit#*:}" | normalise_comment)
                history_rows="$history_rows$file"$'\t'"$line"$'\t'"$id"$'\t'"$key"$'\n'
            done < <(printf '%s\n' "$text" | grep -niE -- "$pattern" || true)
        done <<<"$comment_rules"
    done
}

history_total=0
history_carried=0
history_stale=""

# Splits the collected rows against a baseline: anything not carried is reported
# as a violation, and every carried line that matched nothing is collected as
# stale. Stale lines do not fail the lint — a gate that stays red over something
# already fixed is a gate people learn to route around — but they are printed, so
# the file burns down instead of accumulating.
settle_comments() {
    local baseline=$1 carried seen violations stale path rule key file line id message
    if [ ! -f "$baseline" ]; then
        echo "lint-sim: $baseline is missing — every process-history hit would fail" >&2
        exit 2
    fi
    carried=$(baseline_keys "$baseline")
    history_total=$(printf '%s' "$history_rows" | sed '/^$/d' | wc -l | tr -d ' ')
    history_carried=$(printf '%s\n' "$carried" | sed '/^$/d' | wc -l | tr -d ' ')

    violations=$(printf '%s' "$history_rows" |
        awk -F'\t' -v carried="$carried" '
            BEGIN {
                split(carried, lines, "\n")
                for (i in lines) if (lines[i] != "") known[lines[i]] = 1
            }
            NF >= 4 && !(($1 "\t" $3 "\t" $4) in known) { print }')

    seen=$(printf '%s' "$history_rows" |
        awk -F'\t' 'NF >= 4 { print $1 "\t" $3 "\t" $4 }' | sort -u)
    history_stale=$(printf '%s\n' "$carried" |
        awk -F'\t' -v seen="$seen" '
            BEGIN {
                split(seen, lines, "\n")
                for (i in lines) if (lines[i] != "") have[lines[i]] = 1
            }
            NF >= 3 && !(($1 "\t" $2 "\t" $3) in have) { print }')

    while IFS=$'\t' read -r file line id key; do
        [ -n "$file" ] || continue
        message=$(comment_message "$id")
        report "$file:$line: $(hit_text "$id" "$message")"
    done <<<"$violations"

    # In --self-test a stale line is a hit of its own, at line 0, so expected.txt
    # can name it and the burn-down report is pinned like everything else.
    if [ "$mode" = self-test ]; then
        while IFS=$'\t' read -r path rule key; do
            [ -n "$path" ] || continue
            report "$path:0: baseline-stale"
        done <<<"$history_stale"
    fi
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

    fixture_comments=()
    while IFS= read -r file; do
        fixture_comments+=("$file")
    done < <(find "$fixtures/comments" -name '*.swift' 2>/dev/null | sort)

    if [ "${#fixture_sources[@]}" -eq 0 ] || [ "${#fixture_goldens[@]}" -eq 0 ] ||
        [ "${#fixture_comments[@]}" -eq 0 ]; then
        echo "lint-sim: the fixture tree under $fixtures/ is missing or empty" >&2
        exit 2
    fi

    scan_sources "${fixture_sources[@]}"
    scan_goldens "${fixture_goldens[@]}"
    scan_comments "${fixture_comments[@]}"
    settle_comments "$fixtures/baseline.txt"

    actual=$(printf '%s' "$found" | sort -t: -k1,1 -k2,2n)
    want=$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$expected" |
        sort -t: -k1,1 -k2,2n)

    if [ "$actual" = "$want" ]; then
        echo "lint-sim: self-test clean — $hits hit(s) from" \
            "${#fixture_sources[@]} source fixtures," \
            "${#fixture_goldens[@]} golden fixture(s) and" \
            "${#fixture_comments[@]} comment fixtures, all of them expected."
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

# --- 3. no process history in a comment -------------------------------------

# Globbed, where the `packages` array above is written out, and the difference is
# not an oversight. Check 1 must skip FMPersistence because SwiftData lives there
# by design; a comment that says which issue it was filed under is no more use to
# a reader there than anywhere else, so check 3 takes every Sources/ and Tests/
# tree under Packages/ and Tools/ as it finds them, including the ones that do
# not exist yet.
history_files=()
for dir in Packages/*/Sources Packages/*/Tests Tools/*/Sources Tools/*/Tests; do
    [ -d "$dir" ] || continue
    before=${#history_files[@]}
    # Hidden directories are pruned so a built `.build` tree, which holds
    # generated .swift files, cannot change what the lint scans.
    while IFS= read -r file; do
        history_files+=("$file")
    done < <(find "$dir" -name '.*' -type d -prune -o -name '*.swift' -print | sort)
    if [ "${#history_files[@]}" -eq "$before" ]; then
        echo "lint-sim: $dir holds no .swift files — it would be scanned as nothing" >&2
        exit 2
    fi
done

if [ "${#history_files[@]}" -eq 0 ]; then
    echo "lint-sim: no Sources/ or Tests/ tree under Packages/ or Tools/ —" \
        "the comment check would pass by scanning nothing" >&2
    exit 2
fi

scan_comments "${history_files[@]}"

# --baseline prints the file the tree would need to pass. It is how the baseline
# was first filled and how you check what is left in it; it is NOT a way to make
# a red lint green. A new hit means a comment was written that says what the
# backlog did rather than what the code does, and the fix is the comment.
if [ "$mode" = baseline ]; then
    printf '%s' "$history_rows" |
        awk -F'\t' 'NF >= 4 { print $1 "\t" $3 "\t" $4 }' | sort -u
    exit 0
fi

settle_comments "$comment_baseline"

# --- verdict ----------------------------------------------------------------

echo "lint-sim: $history_total process-history hit(s) in comments;" \
    "$history_carried line(s) carried in $comment_baseline."

# Printed before the verdict rather than inside it, so a clean exit still carries
# the number. A stale line is a comment that has already been rewritten, and the
# only thing left to do about it is to take the line out.
if [ -n "$history_stale" ]; then
    echo
    printf '%s\n' "$history_stale" | sed 's/^/  stale: /'
    echo
    echo "lint-sim: the baseline line(s) above matched nothing — the comments they" \
        "carried are gone. Delete them from $comment_baseline."
    echo "  Reported, not failed: the burn-down is the point, and a gate that goes red"
    echo "  when somebody fixes something teaches people to stop fixing things."
fi

if [ "$hits" -gt 0 ]; then
    echo
    printf '%s' "$found" | sort -t: -k1,1 -k2,2n
    echo
    echo "lint-sim: $hits violation(s) in ${#sources[@]} source files," \
        "${#goldens[@]} golden test files and ${#history_files[@]} files read for comments."
    exit 1
fi

echo "lint-sim: clean — ${#sources[@]} source files, ${#goldens[@]} golden test files," \
    "${#history_files[@]} files read for comments."
