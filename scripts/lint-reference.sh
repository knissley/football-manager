#!/usr/bin/env bash
#
# lint-reference.sh — the rulebook lint: reproduced text, and citations that
# resolve.
#
# CLAUDE.md rule 8 says a rulebook may be cited by number and season but never
# copied into the tree. CLAUDE.md rule 10 says a football claim carries an
# article number. Until this script existed neither was checked by anything: a
# reviewer who happened to have the book open found three reproduced runs in
# `docs/reference/playing-rules.md`, and a second reviewer found the same
# article number cited wrongly in six places across three documents. Both were
# found by reading. Reading does not scale and does not run in CI.
#
# `InvariantsTraceabilityTests` already checks the other half of this: that every
# `test:` and `row:` name in the four reference documents resolves to something
# that exists. It checks names and length. It does not look at the article
# numbers beside them and it has never seen the rulebook. That gap is what this
# script is for.
#
# Two checks:
#
#   1. REPRODUCED TEXT. Runs of N words (default 10) that the tree and the
#      rulebook have in common. Any run not carried in the baseline is a
#      violation.
#   2. CITATIONS RESOLVE. Every `rule-section-article` number cited in the four
#      reference documents names an article the rulebook actually has.
#
# ## What this script CANNOT check, and says so on every run
#
# It cannot tell whether a cited article *supports* the claim written beside it.
# `8-5-4` exists, so check 2 passes on it; it is nonetheless the wrong article
# for the pass-interference penalties, which is where the substance lives. Six
# entries cited it that way for weeks. A green run of this script means "no
# reproduced run, and every number names a real article" — it does not mean the
# citations are right. That stays a reading problem, and the script prints the
# sentence above so a clean run cannot be mistaken for the stronger claim.
#
# ## Why a sibling script and not a rule inside lint-sim.sh
#
# `lint-sim.sh` scans the FM* `Sources/` trees for banned primitives and
# framework imports. It needs nothing but the tree, it is always decisive, and
# its exit code means one thing. This check needs an external corpus that is not
# in the repository and cannot be (the corpus is the copyrighted document rule 8
# is about), so it must be able to skip — and a lint that sometimes skips must
# not share an exit code with one that never does. Folding it in would make a
# clean `lint-sim.sh` ambiguous between "no banned primitives" and "no banned
# primitives, and either no reproduced text or no corpus to look for it in".
#
# ## The corpus
#
# Not in the repository, and never will be. Point the script at a plain-text
# extraction of the rulebook:
#
#     FM_RULEBOOK_TEXT=/path/to/rulebook.txt scripts/lint-reference.sh
#
# Failing that it looks for `.rulebook.txt` at the repository root (which
# `.gitignore` keeps out of the tree). With no corpus it prints why and exits 0:
# CI has no rulebook and a skipped check must not be a red build. `--self-test`
# needs no corpus at all — it ships its own.
#
# ## The three ways a shingle lies, and what is done about each
#
# Every one of these produced a false clean during the audit backlog:
#
#   1. A PER-LINE SCAN. A reproduction broken by a hard wrap contains no ten
#      consecutive words on any one line and hides completely. Measured on
#      `playing-rules.md`: 5 runs per line, 10 with the lines joined. This
#      script scans both and labels every hit `line` or `joined`, and its
#      positive control for the joined path is deliberately split across a wrap,
#      so a rewrite that scanned lines only would fail its own control at
#      runtime rather than printing a comfortable zero.
#   2. A SUB-RANGE. An agent shingled one commit's diff and reported the count
#      as the branch's. This script scans whole files, never a range or a diff,
#      and prints the number of files it scanned; it exits 2 rather than 0 if
#      any policed directory has gone missing, because a lint that passes by
#      scanning nothing is the failure it is meant to prevent.
#   3. A CONTROL THAT COULD NOT FIRE. An agent's control phrase was not in the
#      book, so the control returned 0 and its clean run meant nothing. This
#      script's controls are cut from the corpus at runtime, so they cannot be
#      a phrase the corpus does not have; if the positive controls do not fire,
#      or the negative one does, it prints no count at all and exits 2. A count
#      without a firing control is not a measurement.
#
# ## The baseline
#
# `scripts/lint-reference-baseline.txt` carries any run judged irreducible, one
# line each, by file and by content key — never by content, because writing the
# run into the repository is the thing being linted. Each carries a verdict and a
# note. The gate is: a run that is not in the baseline fails.
#
# It is empty, and it did not start that way. The tree shared twenty-three
# ten-word runs with the book when this script was written, and the first
# judgement was that all twenty-three were the sport's vocabulary rather than the
# book's prose, since terms of art are the one thing `docs/reference/README.md`
# says cannot be reworded. That was a defensible claim about two hundred files and
# a wrong one about the six entries it mattered for: read one at a time against
# its own article, every run had a paraphrase that cost nothing. The irreducible
# case is real — a rule whose nouns are all defined terms can run out of ways to
# be ten words long — it simply was not any of those twenty-three.
#
# So a line here is a claim that somebody opened the article and judged the run,
# not a way to quiet the script. `--list` prints the line to add, and the baseline
# file itself says more.
#
# Usage:
#   scripts/lint-reference.sh              lint the tree
#   scripts/lint-reference.sh --list       print a baseline line per run found
#   scripts/lint-reference.sh --self-test  run against the fixture corpus and
#                                          fixture documents, and compare the
#                                          hits against the expected list
#   --n <N>                                run length, default 10
#
# Exit codes: 0 clean or skipped, 1 violations, 2 the lint could not measure.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

mode=lint
n=10

while [ $# -gt 0 ]; do
    case "$1" in
        --self-test)
            mode=self-test
            shift
            ;;
        --list)
            mode=list
            shift
            ;;
        --n)
            n=${2-}
            shift 2 || true
            ;;
        -h | --help)
            echo "usage: scripts/lint-reference.sh [--self-test | --list] [--n N]"
            exit 0
            ;;
        *)
            echo "lint-reference: unknown argument: $1" >&2
            echo "usage: scripts/lint-reference.sh [--self-test | --list] [--n N]" >&2
            exit 2
            ;;
    esac
done

case "$n" in
    '' | *[!0-9]*)
        echo "lint-reference: --n wants a number, got '$n'" >&2
        exit 2
        ;;
esac
if [ "$n" -lt 4 ]; then
    echo "lint-reference: --n $n is below 4; a run that short is a coincidence, not a copy" >&2
    exit 2
fi

fixtures="scripts/lint-reference-fixtures"
baseline="scripts/lint-reference-baseline.txt"

# The documents whose article numbers are checked. The same four
# InvariantsTraceabilityTests reads: they are where a football claim is written
# down with a number beside it, and a number is only checkable where the
# convention for writing one is followed.
cited_documents=(
    "docs/invariants.md"
    "docs/reference/playing-rules.md"
    "docs/reference/calibration-sources.md"
    ".claude/skills/football-domain/references/game-rules.md"
)

# ---------------------------------------------------------------------------
# The scanner. One awk program: it reads the corpus first, then every file named
# after it. Written once and used by both the lint and the self-test, so the
# self-test exercises the code the lint runs and not a copy of it.
#
# Controls run between the corpus and the first real file, cut from the corpus's
# own last N words, and they go through the same scan() the files do.
# ---------------------------------------------------------------------------

scanner=$(
    cat <<'AWK'
function keyof(s,   i, c, h1, h2, len) {
    # Two polynomial hashes over the run, concatenated. The baseline has to name
    # a run without containing it — writing the run into the repository is the
    # thing this script exists to stop — so it names it by content key.
    h1 = 0
    h2 = 0
    len = length(s)
    for (i = 1; i <= len; i++) {
        c = ORD[substr(s, i, 1)]
        h1 = (h1 * 131 + c) % 2147483647
        h2 = (h2 * 137 + c) % 1073741789
    }
    return h1 "-" h2
}

function tokenise(line, words,   lower, count) {
    lower = tolower(line)
    gsub(/[^a-z0-9]+/, " ", lower)
    return split(lower, words, " ")
}

# Scans one document's word stream. `w` is the words, `wl` the line each came
# from, `count` how many. A run whose first and last word share a line is
# reported `line`; one that does not exists only once the lines are joined, and
# is reported `joined`. Returns the number of runs found.
function scan(w, wl, count, label, report,   i, j, gram, found, scope) {
    found = 0
    for (i = 1; i + N - 1 <= count; i++) {
        gram = w[i]
        for (j = i + 1; j <= i + N - 1; j++) gram = gram " " w[j]
        if (!(gram in G)) continue
        found++
        if (!report) continue
        scope = (wl[i] == wl[i + N - 1]) ? "line" : "joined"
        print label "\t" wl[i] "\t" scope "\t" keyof(gram)
    }
    return found
}

function flush(   i) {
    if (current == "") return
    scan(w, wl, wn, current, 1)
    filesscanned++
    current = ""
    wn = 0
}

# Cuts the three controls from the corpus's own last N words and runs them
# through scan(). Positive control A is one line; positive control B is the same
# words split across a wrap, so only a scan that joins lines can find it;
# the negative control is the same words in reverse order, which must not be a
# run of the corpus.
function controls(   i, half, ok) {
    if (ctrln < N) {
        print "CONTROL\tcorpus holds fewer than " N " words" > "/dev/stderr"
        exit 2
    }
    for (i = 1; i <= N; i++) {
        cw[i] = ctrl[i]
        cl[i] = 1
    }
    posline = scan(cw, cl, N, "control", 0)

    half = int(N / 2)
    for (i = 1; i <= N; i++) {
        cw[i] = ctrl[i]
        cl[i] = (i <= half) ? 1 : 2
    }
    posjoined = scan(cw, cl, N, "control", 0)

    for (i = 1; i <= N; i++) {
        cw[i] = ctrl[N + 1 - i]
        cl[i] = (i <= half) ? 1 : 2
    }
    negative = scan(cw, cl, N, "control", 0)

    ok = (posline >= 1 && posjoined >= 1 && negative == 0)
    print "CONTROL\t" posline "\t" posjoined "\t" negative "\t" (ok ? "ok" : "FAILED")
    if (!ok) exit 2
}

BEGIN {
    chars = "abcdefghijklmnopqrstuvwxyz0123456789 "
    for (i = 1; i <= length(chars); i++) ORD[substr(chars, i, 1)] = i
    corpusdone = 0
    current = ""
    wn = 0
    bn = 0
    cn = 0
    ctrln = 0
    filesscanned = 0
}

FILENAME == CORPUS {
    count = tokenise($0, a)
    for (i = 1; i <= count; i++) {
        buf[++bn] = a[i]
        if (bn < N) continue
        gram = buf[bn - N + 1]
        for (j = bn - N + 2; j <= bn; j++) gram = gram " " buf[j]
        G[gram] = 1
        cn++
        # The rolling window doubles as the control: whatever it holds when the
        # corpus ends is N consecutive corpus words, so the control cannot be a
        # phrase the corpus does not have.
        for (j = 1; j <= N; j++) ctrl[j] = buf[bn - N + j]
        ctrln = N
        # Keep the buffer from growing to the size of the book.
        if (bn > 4 * N) {
            for (j = 1; j <= N; j++) buf[j] = buf[bn - N + j]
            bn = N
        }
    }
    next
}

{
    if (!corpusdone) {
        corpusdone = 1
        distinct = 0
        for (g in G) distinct++
        print "CORPUS\t" distinct
        controls()
    }
    if (FILENAME != current) {
        flush()
        current = FILENAME
        wn = 0
    }
    count = tokenise($0, a)
    for (i = 1; i <= count; i++) {
        w[++wn] = a[i]
        wl[wn] = FNR
    }
}

END {
    if (!corpusdone) {
        distinct = 0
        for (g in G) distinct++
        print "CORPUS\t" distinct
        controls()
    }
    flush()
    print "FILES\t" filesscanned
}
AWK
)

# ---------------------------------------------------------------------------
# The citation index. Same shape: the corpus first, the documents after.
# ---------------------------------------------------------------------------

citations=$(
    cat <<'AWK'
BEGIN {
    # The extractor breaks a heading word across a line now and then — a line
    # holding just "SEC", the next opening "TION 4". A line that is a proper
    # prefix of one of the three heading words is carried onto the next line
    # rather than dropped, which is worth six sections and two articles of the
    # index and, without it, eight citations that resolve in the book and not
    # here.
    split("RULE SECTION ARTICLE", keywords, " ")
    for (k = 1; k <= 3; k++) {
        word = keywords[k]
        for (i = 1; i < length(word); i++) prefix[substr(word, 1, i)] = 1
    }
    carry = ""
    rule = ""
    section = ""
    corpusdone = 0
    seen = 0
    unresolved = 0
}

FILENAME == CORPUS {
    line = carry $0
    carry = ""
    trimmed = line
    gsub(/^[ \t\r]+|[ \t\r]+$/, "", trimmed)
    if (trimmed in prefix) {
        carry = trimmed
        next
    }
    if (match(trimmed, /^(RULE|SECTION|ARTICLE)[ \t]+[0-9]+/)) {
        split(trimmed, parts, /[ \t]+/)
        kind = parts[1]
        num = parts[2]
        sub(/[^0-9].*$/, "", num)
        if (kind == "RULE") {
            rule = num
            section = ""
            rules[rule] = 1
        } else if (kind == "SECTION") {
            if (rule != "") {
                section = num
                sections[rule "-" section] = 1
            }
        } else {
            if (rule != "" && section != "") articles[rule "-" section "-" num] = 1
        }
    }
    next
}

{
    if (!corpusdone) {
        corpusdone = 1
        count = 0
        for (a in articles) count++
        print "INDEX\t" count
        if (count < MINARTICLES) {
            print "INDEX\tthe corpus yielded " count " articles, fewer than " \
                MINARTICLES "; it is not a rulebook or the extraction lost its headings" \
                > "/dev/stderr"
            exit 2
        }
    }
    rest = $0
    offset = 0
    while (match(rest, /[0-9][0-9]?-[0-9][0-9]?-([0-9][0-9]?|Penalty)/)) {
        start = RSTART
        len = RLENGTH
        cite = substr(rest, start, len)
        before = (start == 1) ? "" : substr(rest, start - 1, 1)
        after = substr(rest, start + len, 1)
        rest = substr(rest, start + len)
        offset += start + len - 1
        # A citation is bounded: a digit or a letter on the left means this is
        # the tail of a longer number (a date, a checksum), and a digit on the
        # right means the same on the other side. A hyphen on the right is the
        # clause letter of a real citation — 8-6-1-b — and is allowed.
        if (before ~ /[0-9A-Za-z.]/) continue
        if (after ~ /[0-9]/) continue
        seen++
        split(cite, part, "-")
        if (part[3] == "Penalty") {
            if (!((part[1] "-" part[2]) in sections)) {
                unresolved++
                print FILENAME "\t" FNR "\t" cite "\tno such section"
            }
            continue
        }
        if ((part[1] "-" part[2] "-" part[3]) in articles) continue
        unresolved++
        why = ((part[1] "-" part[2]) in sections) ? "no such article" \
            : ((part[1] in rules) ? "no such section" : "no such rule")
        print FILENAME "\t" FNR "\t" cite "\t" why
    }
}

END {
    if (!corpusdone) {
        print "INDEX\t0"
        print "INDEX\tno document was scanned after the corpus" > "/dev/stderr"
        exit 2
    }
    print "SEEN\t" seen "\t" unresolved
}
AWK
)

# ---------------------------------------------------------------------------
# Running the two passes
# ---------------------------------------------------------------------------

reproduced_out=""
citation_out=""

# The scan's own failure — a control that did not fire, a corpus too short — comes
# back as a non-zero exit from awk, and `set -e` would end the script there without
# a word. Refusing to print a count is the point; refusing to say why is not, so
# the status is captured and reported rather than allowed to abort.
run_scan() {
    local corpus=$1 status=0 out
    shift
    set +e
    out=$(awk -v CORPUS="$corpus" -v N="$n" "$scanner" "$corpus" "$@" 2>&1)
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        echo "lint-reference: the scan could not measure and printed no count." >&2
        printf '%s\n' "$out" | sed 's/^/  /' >&2
        echo "  A count without a firing control is not a measurement, so there is none." >&2
        exit 2
    fi
    printf '%s\n' "$out"
}

run_citations() {
    local corpus=$1 minimum=$2 status=0 out
    shift 2
    set +e
    out=$(awk -v CORPUS="$corpus" -v MINARTICLES="$minimum" "$citations" "$corpus" "$@" 2>&1)
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        echo "lint-reference: the citation index could not be built." >&2
        printf '%s\n' "$out" | sed 's/^/  /' >&2
        exit 2
    fi
    printf '%s\n' "$out"
}

# The `path <TAB> key` pairs a baseline file carries, comments and blank lines
# dropped.
#
# The `|| true` is not decoration. `grep -v` exits 1 when it selects nothing, which
# is exactly what a baseline holding only its own explanation does — and with
# `set -o pipefail` that ends the script mid-run, so the lint died on the day its
# baseline finally reached zero entries. The self-test pins the empty case.
baseline_keys() {
    local file=$1
    { grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$file" || true; } |
        awk -F'\t' 'NF >= 2 { print $1 "\t" $2 }' | sort -u
}

note_on_what_is_unchecked() {
    echo
    echo "lint-reference: what this did NOT check — whether a cited article actually"
    echo "  supports the claim written beside it. 8-5-4 is a real article, so a citation"
    echo "  to it passes here; it was still the wrong article in six entries. A clean run"
    echo "  means no reproduced run and no dangling number. It does not mean the"
    echo "  citations are right. Only reading the article does."
}

# ---------------------------------------------------------------------------
# --self-test
# ---------------------------------------------------------------------------

if [ "$mode" = self-test ]; then
    expected="$fixtures/expected.txt"
    corpus="$fixtures/corpus.txt"
    fixture_baseline="$fixtures/baseline.txt"

    for required in "$expected" "$corpus" "$fixture_baseline"; do
        if [ ! -f "$required" ]; then
            echo "lint-reference: $required is missing — the self-test has nothing to run" >&2
            exit 2
        fi
    done

    fixture_docs=()
    while IFS= read -r file; do
        fixture_docs+=("$file")
    done < <(find "$fixtures/docs" -name '*.md' 2>/dev/null | sort)

    if [ "${#fixture_docs[@]}" -lt 4 ]; then
        echo "lint-reference: the fixture tree under $fixtures/docs is missing or thin" >&2
        exit 2
    fi

    scan_out=$(run_scan "$corpus" "${fixture_docs[@]}")
    control=$(printf '%s\n' "$scan_out" | grep '^CONTROL' || true)
    cite_out=$(run_citations "$corpus" 2 "$fixtures/docs/citations.md")

    if [ -z "$control" ] || ! printf '%s' "$control" | grep -q 'ok$'; then
        echo "lint-reference: the self-test's controls did not fire — printing nothing." >&2
        echo "  $control" >&2
        exit 2
    fi

    # A baseline that holds only its own explanation must read as no keys and must
    # not end the run. It did end the run, once, because `grep -v` exits 1 when it
    # selects nothing and `pipefail` passed that on — on the day the real baseline
    # reached zero entries, which is the day the lint was working best.
    empty_baseline="$fixtures/baseline-empty.txt"
    if [ ! -f "$empty_baseline" ]; then
        echo "lint-reference: $empty_baseline is missing — the empty-baseline case is unpinned" >&2
        exit 2
    fi
    # Assigned, not tested inline. `[ -n "$(baseline_keys ...)" ]` would discard the
    # status of the substitution, and the status is the whole point of this check —
    # the bug was an abort, not a wrong answer.
    empty_keys=$(baseline_keys "$empty_baseline")
    if [ -n "$empty_keys" ]; then
        echo "lint-reference: $empty_baseline is meant to hold no keys and holds some" >&2
        exit 1
    fi

    # The fixture baseline carries one of the fixture runs, so a rewrite that
    # stopped honouring the baseline fails the self-test as well as the lint.
    carried_keys=$(baseline_keys "$fixture_baseline")

    actual=$(
        {
            printf '%s\n' "$scan_out" | awk -F'\t' -v carried="$carried_keys" '
                BEGIN {
                    split(carried, lines, "\n")
                    for (i in lines) if (lines[i] != "") known[lines[i]] = 1
                }
                $1 !~ /^(CORPUS|FILES|CONTROL)$/ && NF >= 4 && !(($1 "\t" $4) in known) {
                    print $1 ":" $2 ": reproduced-" $3
                }'
            printf '%s\n' "$cite_out" | awk -F'\t' '
                $1 !~ /^(INDEX|SEEN)$/ && NF >= 4 { print $1 ":" $2 ": citation-" $4 }'
        } | sed '/^$/d' | sort -t: -k1,1 -k2,2n
    )

    want=$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$expected" |
        sort -t: -k1,1 -k2,2n)

    echo "lint-reference: self-test controls — $control"

    if [ "$actual" = "$want" ]; then
        count=$(printf '%s\n' "$actual" | sed '/^$/d' | wc -l | tr -d ' ')
        echo "lint-reference: self-test clean — $count hit(s) from ${#fixture_docs[@]}" \
            "fixture documents against the fixture corpus, all of them expected."
        exit 0
    fi

    echo "lint-reference: SELF-TEST FAILED — the fixtures did not lint as $expected says." >&2
    echo "  '-' was expected and did not fire; '+' fired and was not expected." >&2
    { diff <(printf '%s\n' "$want") <(printf '%s\n' "$actual") || true; } |
        sed -n 's/^</  -/p; s/^>/  +/p' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# The corpus, or an honest skip
# ---------------------------------------------------------------------------

corpus=${FM_RULEBOOK_TEXT-}
if [ -z "$corpus" ] && [ -f ".rulebook.txt" ]; then
    corpus=".rulebook.txt"
fi

if [ -z "$corpus" ] || [ ! -f "$corpus" ]; then
    echo "lint-reference: SKIPPED — no rulebook corpus."
    echo "  Set FM_RULEBOOK_TEXT to a plain-text extraction of the rulebook, or put one"
    echo "  at .rulebook.txt in the repository root. docs/reference/README.md says how."
    echo "  The corpus is not in the repository and will not be: it is the copyrighted"
    echo "  document CLAUDE.md rule 8 is about."
    echo "  The self-test ships its own fixture corpus and runs without this one."
    exit 0
fi

# ---------------------------------------------------------------------------
# The policed set
# ---------------------------------------------------------------------------

targets=()

# Hidden directories are pruned, which is what keeps a `.build` tree out of the
# walk. SwiftPM writes generated `.swift` files under one, so without this the
# number of files scanned depends on whether the packages have been built — and a
# count nobody else can reproduce is the kind of measurement this script exists to
# stop. `InvariantsTraceabilityTests` skips them for the same reason.
add_tree() {
    local dir=$1 pattern=$2 before=${#targets[@]}
    if [ ! -d "$dir" ]; then
        echo "lint-reference: $dir does not exist — the lint would pass by scanning nothing" >&2
        exit 2
    fi
    while IFS= read -r file; do
        targets+=("$file")
    done < <(find "$dir" -name '.*' -type d -prune -o -name "$pattern" -print | sort)
    if [ "${#targets[@]}" -eq "$before" ]; then
        echo "lint-reference: $dir holds no $pattern — it would be scanned as nothing" >&2
        exit 2
    fi
}

add_tree docs '*.md'
add_tree .claude/skills '*.md'
add_tree Packages '*.swift'
add_tree Tools '*.swift'
add_tree scripts '*.sh'
for loose in CLAUDE.md README.md; do
    [ -f "$loose" ] && targets+=("$loose")
done

for document in "${cited_documents[@]}"; do
    if [ ! -f "$document" ]; then
        echo "lint-reference: $document is missing — the citation check has nothing to read" >&2
        exit 2
    fi
done

# ---------------------------------------------------------------------------
# Check 1 — reproduced text
# ---------------------------------------------------------------------------

scan_out=$(run_scan "$corpus" "${targets[@]}")

control_line=$(printf '%s\n' "$scan_out" | grep '^CONTROL' || true)
corpus_grams=$(printf '%s\n' "$scan_out" | awk -F'\t' '$1 == "CORPUS" { print $2 }')
files_scanned=$(printf '%s\n' "$scan_out" | awk -F'\t' '$1 == "FILES" { print $2 }')

if [ -z "$control_line" ] || ! printf '%s' "$control_line" | grep -q 'ok$'; then
    echo "lint-reference: the controls did not fire — printing no count." >&2
    echo "  $control_line" >&2
    exit 2
fi

read -r _ pos_line pos_joined negative _ <<<"$(printf '%s' "$control_line" | tr '\t' ' ')"

echo "lint-reference: corpus $corpus — $corpus_grams distinct $n-word runs."
echo "lint-reference: positive control (one line) fired $pos_line;" \
    "positive control (split across a wrap) fired $pos_joined;" \
    "negative control (the same words reversed) fired $negative."
echo "lint-reference: scanned $files_scanned files whole — no diff, no line range."

hits=$(printf '%s\n' "$scan_out" |
    awk -F'\t' '$1 !~ /^(CORPUS|FILES|CONTROL)$/ && NF >= 4 { print }')

if [ "$mode" = list ]; then
    echo
    echo "# baseline lines for every run found — path, key, verdict, note"
    printf '%s\n' "$hits" | awk -F'\t' 'NF >= 4 {
        printf "%s\t%s\tvocabulary\tTODO: read the article, then say in our own words why this run is carried (%s, line %s)\n",
            $1, $4, $3, $2
    }' | sort -u
    exit 0
fi

if [ ! -f "$baseline" ]; then
    echo "lint-reference: $baseline is missing — every run in the tree would fail" >&2
    exit 2
fi

carried_keys=$(baseline_keys "$baseline")

violations=$(printf '%s\n' "$hits" |
    awk -F'\t' -v carried="$carried_keys" -v N="$n" '
        BEGIN {
            split(carried, lines, "\n")
            for (i in lines) if (lines[i] != "") known[lines[i]] = 1
        }
        NF >= 4 && !(($1 "\t" $4) in known) {
            printf "%s:%s: a %s-word run the rulebook also has (%s), key %s\n",
                $1, $2, N, $3, $4
        }')

carried_count=$(printf '%s\n' "$carried_keys" | sed '/^$/d' | wc -l | tr -d ' ')
hit_count=$(printf '%s\n' "$hits" | sed '/^$/d' | wc -l | tr -d ' ')
violation_count=$(printf '%s\n' "$violations" | sed '/^$/d' | wc -l | tr -d ' ')

echo "lint-reference: $hit_count shared run(s); $carried_count carried in $baseline."

# ---------------------------------------------------------------------------
# Check 2 — citations resolve
# ---------------------------------------------------------------------------

cite_out=$(run_citations "$corpus" 100 "${cited_documents[@]}")
index_count=$(printf '%s\n' "$cite_out" | awk -F'\t' '$1 == "INDEX" && NF == 2 { print $2 }')
seen_line=$(printf '%s\n' "$cite_out" | awk -F'\t' '$1 == "SEEN" { print $2 "\t" $3 }')
cite_seen=$(printf '%s' "$seen_line" | cut -f1)
cite_bad=$(printf '%s' "$seen_line" | cut -f2)

bad_citations=$(printf '%s\n' "$cite_out" |
    awk -F'\t' '$1 !~ /^(INDEX|SEEN)$/ && NF >= 4 {
        printf "%s:%s: cites %s — %s in the rulebook\n", $1, $2, $3, $4
    }')

echo "lint-reference: rulebook index holds $index_count articles;" \
    "$cite_seen citation(s) in ${#cited_documents[@]} documents, $cite_bad unresolved."

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------

if [ "$violation_count" -gt 0 ] || [ "${cite_bad:-0}" -gt 0 ]; then
    echo
    [ "$violation_count" -gt 0 ] && printf '%s\n' "$violations" | sed '/^$/d'
    [ "${cite_bad:-0}" -gt 0 ] && printf '%s\n' "$bad_citations" | sed '/^$/d'
    echo
    echo "lint-reference: $violation_count reproduced run(s) not in the baseline," \
        "$cite_bad citation(s) that name no article."
    echo "  A run you have judged to be the sport's vocabulary rather than the book's"
    echo "  prose goes in $baseline with a note saying so;"
    echo "  scripts/lint-reference.sh --list prints the line to add."
    note_on_what_is_unchecked
    exit 1
fi

echo "lint-reference: clean — $files_scanned files, $hit_count shared run(s) all carried," \
    "$cite_seen citation(s) all resolved."
note_on_what_is_unchecked
