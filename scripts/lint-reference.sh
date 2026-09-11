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
# Three checks:
#
#   1. REPRODUCED TEXT IN THE TREE. Runs of N words (default 10) that the tree
#      and the rulebook have in common. Any run not carried in the baseline is a
#      violation. A reproduction SHORTER than N is invisible — see "The blind
#      spot" below, which says how short and what was measured.
#   2. REPRODUCED TEXT IN THE COMMIT MESSAGES a branch adds against its merge
#      base — the same scanner, the same two passes, the same controls. See
#      "Commit messages" below for why they are scanned separately from the tree
#      and what a hit in one does.
#   3. CITATIONS RESOLVE. Every `rule-section-article` number cited in the four
#      reference documents names an article the rulebook actually has.
#
# ## What this script CANNOT check, and says so on every run
#
# It cannot tell whether a cited article *supports* the claim written beside it.
# `8-5-4` exists, so check 3 passes on it; it is nonetheless the wrong article
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
#      as the branch's. This script scans whole files and whole commit messages,
#      never a diff and never a line range, and prints how many of each it
#      scanned; it exits 2 rather than 0 if any policed directory has gone
#      missing, because a lint that passes by scanning nothing is the failure it
#      is meant to prevent. A commit range is the one range it takes, and it is
#      the whole of what the branch adds — see "Commit messages" below.
#   3. A CONTROL THAT COULD NOT FIRE. An agent's control phrase was not in the
#      book, so the control returned 0 and its clean run meant nothing. This
#      script's controls are cut from the corpus at runtime, so they cannot be
#      a phrase the corpus does not have; if the positive controls do not fire,
#      or the negative one does, it prints no count at all and exits 2. A count
#      without a firing control is not a measurement.
#
# ## Commit messages
#
# A commit message is in the repository as permanently as a file is, and rule 8
# does not stop at the tree. It is also the harder of the two to put right:
# a file is edited, a published message is only rewritten by rewriting history,
# which the conventions forbid on a shared branch. The one run this check exists
# for was caught while its branch was still local and the commits could be
# replayed; one push later the choice would have been between leaving it and
# rewriting published history. So the whole value is in catching it BEFORE the
# push, and the design follows from that.
#
# WHAT IS SCANNED. The commits the branch adds against its merge base —
# `git merge-base <base> HEAD`..HEAD, oldest first, one message at a time, whole.
# Not the whole history: every commit already on the integration branch was
# scanned when it was somebody's branch, and re-reporting them for ever is how a
# gate becomes wallpaper. `<base>` is `origin/main`, or `main` if there is no
# remote; `--base` and `--range` override it, and `--range` is what to reach for
# when auditing history rather than a branch.
#
# WHAT A HIT DOES, and why:
#
#   * A commit NOT yet on the base branch is a VIOLATION and the script exits 1.
#     It can still be reworded, and that is the only moment at which it can. This
#     is the case the check is for.
#   * A commit already on the base branch is REPORTED and does not fail. Nothing
#     can be done about it: the message is published and a merge does not rewrite
#     it. A gate that goes red for ever over something nobody can fix is a gate
#     people learn to pass with `--no-verify`, and then it is not protecting the
#     case above either. The count is still printed, every run, because a number
#     nobody can act on is still a number somebody should know.
#
# Only a range that reaches back past the merge base can hold a published commit,
# so in ordinary use the second arm is silent and `--range` is what wakes it.
#
# NO BASELINE FOR MESSAGES. A run in the tree can be irreducible — an article
# whose nouns are all defined terms leaves nothing to reword — and that is what
# the baseline is for. A commit message has no such constraint: it is prose its
# author wrote freely and can write again, and the remedy for a hit is to say it
# in our own words and cite the article. If the run is genuinely unavoidable, the
# message can cite rather than quote. So a message hit has no way to be carried,
# on purpose.
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
# ## THE BLIND SPOT: a reproduction of nine words or fewer is invisible here
#
# The gate is ten words. Nine is not a gap in the implementation, it is the
# threshold — so a clean run means "no run of ten", and it does NOT mean the tree
# holds none of the book's prose. Eight-word reproductions happen: one was written
# into a commit message and found only because somebody scanned at eight while the
# branch was still local, below what this script asks for. Nothing about rule 8
# comes with a word count.
#
# Eight was then measured across the whole policed tree rather than argued about,
# and REJECTED. Shared runs, whole tree, 214 files, against a plain-text extraction
# of the book:
#
#      n = 10        0 runs                              (the state this ships in)
#      n =  9       32 runs, 12 distinct, 18 files       29 baseline lines
#      n =  8      130 runs, 57 distinct, 26 files      116 baseline lines
#      n =  7      382 runs
#      n =  6     1039 runs
#
# Every distinct run at 8 and at 9 was read against its own article. At 9, none is
# a reproduction. At 8, two were — one a clause of prose lifted from the
# ten-second-runoff article, one a quotation of a clock window set in quote marks
# and announced as the article's words — and both were reworded, which is what the
# counts above already reflect. The other 57 are chains of defined terms the sport
# has no synonym for, a penalty's own name beside the article number rule 10
# requires, a rule's title used as a heading, and plain coincidence.
#
# That is the successor to the twenty-three. At ten, twenty-three runs and every
# one of them reducible: a gate whose every hit was worth acting on. At eight, 116
# baseline lines standing around two findings — and a baseline line is a claim that
# somebody opened the article and judged the run. A hundred and sixteen of those
# would be a rubber stamp, and the baseline is the one part of this script that
# only works if somebody reads it. So the cost of eight is not the runtime, it is
# that it converts the gate into noise and buries the next real run inside it.
#
# Two things follow, and neither is fixed by a threshold:
#
#   * THE THRESHOLD IS NOT WHAT MADE COMMIT MESSAGES INVISIBLE. Until check 2
#     existed this script read files and nothing else, so the run that prompted
#     the measurement above — which was in a message — would have escaped at any
#     `--n`. Check 2 closes that, at the same ten words and with the same two
#     passes; what it does NOT close is the same nine-word blind spot, now in one
#     more place. A merged message cannot be un-written, so the gate is the push.
#   * A SHORT RUN IS A READING PROBLEM. At eight the script cannot tell a
#     quotation from the same defined terms in the same order — the quoted clock
#     window above sat among nine innocent uses of the identical words. Only
#     opening the article separates them.
#
# `--n 8` runs the tree at eight on demand and is worth doing on a branch that
# added football prose. Expect the count above, not zero, and read what moved.
#
# Usage:
#   scripts/lint-reference.sh              lint the tree and the branch's commit
#                                          messages
#   scripts/lint-reference.sh --messages   the commit messages only — what to run
#                                          immediately before a push, which is
#                                          the last moment a message can be fixed
#   scripts/lint-reference.sh --list       print a baseline line per run found
#                                          in the tree (messages are not
#                                          baselineable — see above)
#   scripts/lint-reference.sh --self-test  run against the fixture corpus, the
#                                          fixture documents and a throwaway
#                                          repository built from the fixture
#                                          commit messages, and compare the hits
#                                          against what is expected
#   --n <N>                                run length, default 10. Anything
#                                          shorter than the default is advisory:
#                                          the gate is ten, and the counts a
#                                          shorter run prints are in "The blind
#                                          spot" above.
#   --base <ref>                           the integration branch commit messages
#                                          are measured against. Default
#                                          `origin/main`, then `main`. It decides
#                                          both the default range and which hits
#                                          are published and therefore advisory.
#   --range <a>..<b>                       scan these commit messages instead of
#                                          the branch's own. Reach for it to
#                                          audit history, not to lint a branch.
#
# Exit codes: 0 clean or skipped, 1 violations, 2 the lint could not measure.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

mode=lint
n=10
base_ref=""
commit_range=""

usage="usage: scripts/lint-reference.sh [--self-test | --list | --messages]"
usage="$usage [--n N] [--base REF] [--range A..B]"

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
        --messages)
            mode=messages
            shift
            ;;
        --n)
            n=${2-}
            shift 2 || true
            ;;
        --base)
            base_ref=${2-}
            shift 2 || true
            ;;
        --range)
            commit_range=${2-}
            shift 2 || true
            ;;
        -h | --help)
            echo "$usage"
            exit 0
            ;;
        *)
            echo "lint-reference: unknown argument: $1" >&2
            echo "$usage" >&2
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

# One scratch directory for the run. The commit-message pass has to put each
# message somewhere the scanner can be pointed at, because the scanner reports by
# FILENAME and a message is not a file until it is written out.
scratch=$(mktemp -d "${TMPDIR:-/tmp}/lint-reference.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

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
# Running the passes
# ---------------------------------------------------------------------------

reproduced_out=""
citation_out=""

# The scan's own failure — a control that did not fire, a corpus too short — comes
# back as a non-zero exit from awk, and `set -e` would end the script there without
# a word. Refusing to print a count is the point; refusing to say why is not, so
# the status is captured and reported rather than allowed to abort.
# The run length is a parameter rather than the global, because the self-test has to
# scan the same fixtures at two lengths to pin the blind spot, and a check that reaches
# past its arguments for the number it is testing is a check that cannot test two.
run_scan() {
    local length=$1 corpus=$2 status=0 out
    shift 2
    set +e
    out=$(awk -v CORPUS="$corpus" -v N="$length" "$scanner" "$corpus" "$@" 2>&1)
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

# ---------------------------------------------------------------------------
# Check 2 — reproduced text in the commit messages a branch adds
#
# Scans the messages in a commit range with the SAME scanner, the same per-line
# and joined passes and the same runtime controls the tree gets. A message is not
# a file, and the scanner reports by FILENAME, so each one is written out to the
# scratch directory under its own short sha and scanned whole.
#
# `repo` is a parameter because --self-test builds a throwaway repository and
# points this at it. A check that can only read the history it happens to be
# sitting in can only be tested by committing fixtures into the real history,
# which is the opposite of what this check is for.
#
# Sets, and sets all of them on every path so a caller never reads a stale one:
#
#   msg_state       scanned | skipped
#   msg_why         why, when skipped
#   msg_base        the ref publishedness is judged against
#   msg_range       the range that was read
#   msg_commits     how many messages were read
#   msg_control     the CONTROL line, so the caller can insist it fired
#   msg_hits        how many runs were found
#   msg_violations  report lines for commits not yet on the base — these fail
#   msg_advisories  report lines for commits already on it — these do not
# ---------------------------------------------------------------------------

scan_messages() {
    local repo=$1 corpus=$2
    local base="" candidate range revs status=0 sha short subject state
    local dir info="" out hits
    local -a files=()

    msg_state=skipped
    msg_why=""
    msg_base=""
    msg_range=""
    msg_commits=0
    msg_control=""
    msg_hits=0
    msg_violations=""
    msg_advisories=""

    if ! git -C "$repo" rev-parse --git-dir > /dev/null 2>&1; then
        msg_why="$repo is not a git repository, so there is no branch to read"
        return 0
    fi

    # An explicit --base that names nothing is a mistake worth stopping for. A
    # missing default is not: a shallow clone has no origin/main and that is a
    # reason to say the check did not run, not to fail a build over it.
    if [ -n "$base_ref" ]; then
        if ! git -C "$repo" rev-parse --verify --quiet "${base_ref}^{commit}" > /dev/null; then
            echo "lint-reference: --base $base_ref names no commit in $repo." >&2
            exit 2
        fi
        base=$base_ref
    else
        for candidate in origin/main main; do
            if git -C "$repo" rev-parse --verify --quiet "${candidate}^{commit}" > /dev/null; then
                base=$candidate
                break
            fi
        done
        if [ -z "$base" ]; then
            msg_why="no origin/main and no main in $repo — pass --base, or --range to read a"
            msg_why="$msg_why particular set of messages"
            return 0
        fi
    fi
    msg_base=$base

    # The commits the branch ADDS. `<base>...HEAD` would be the symmetric
    # difference and would drag in everything the base has that the branch does
    # not; the merge base is what makes this the branch's own work.
    if [ -n "$commit_range" ]; then
        range=$commit_range
    else
        range="$base..HEAD"
    fi
    msg_range=$range

    set +e
    revs=$(git -C "$repo" rev-list --reverse "$range" 2>&1)
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        echo "lint-reference: could not list the commits in '$range'." >&2
        printf '%s\n' "$revs" | sed 's/^/  /' >&2
        exit 2
    fi

    dir="$scratch/messages"
    rm -rf "$dir"
    mkdir -p "$dir"

    while IFS= read -r sha; do
        [ -n "$sha" ] || continue
        short=$(git -C "$repo" rev-parse --short=9 "$sha")
        git -C "$repo" log -1 --format=%B "$sha" > "$dir/$short"
        subject=$(git -C "$repo" log -1 --format=%s "$sha" | tr '\t' ' ')
        set +e
        git -C "$repo" merge-base --is-ancestor "$sha" "$base" > /dev/null 2>&1
        status=$?
        set -e
        state=$([ "$status" -eq 0 ] && echo published || echo unpublished)
        info="$info$short	$state	$subject
"
        files+=("$dir/$short")
    done <<< "$revs"

    msg_state=scanned
    msg_commits=${#files[@]}

    # Run the scanner even with nothing to scan: the controls live inside it, and
    # an empty range still has to prove the scanner works before it reports zero.
    out=$(run_scan "$n" "$corpus" "${files[@]+"${files[@]}"}")
    msg_control=$(printf '%s\n' "$out" | grep '^CONTROL' || true)

    hits=$(printf '%s\n' "$out" |
        awk -F'\t' -v d="$dir/" -v N="$n" -v info="$info" '
            BEGIN {
                rows = split(info, line, "\n")
                for (i = 1; i <= rows; i++) {
                    if (line[i] == "") continue
                    split(line[i], f, "\t")
                    state[f[1]] = f[2]
                    subject[f[1]] = f[3]
                }
            }
            $1 ~ /^(CORPUS|FILES|CONTROL)$/ { next }
            NF >= 4 {
                short = $1
                if (index(short, d) == 1) short = substr(short, length(d) + 1)
                printf "%s\tcommit %s, message line %s: a %s-word run the rulebook also has (%s), key %s — \"%s\"\n",
                    state[short], short, $2, N, $3, $4, subject[short]
            }')

    msg_hits=$(printf '%s\n' "$hits" | sed '/^$/d' | wc -l | tr -d ' ')
    msg_violations=$(printf '%s\n' "$hits" | awk -F'\t' '$1 == "unpublished" { print $2 }' | sed '/^$/d')
    msg_advisories=$(printf '%s\n' "$hits" | awk -F'\t' '$1 == "published" { print $2 }' | sed '/^$/d')
}

# How many of each the last scan_messages found. A run in a message that is not
# yet on the integration branch can still be reworded; one that is on it cannot
# be, and is reported rather than failed — a gate that stays red over history
# nobody can change is a gate people route around, and then it is not guarding
# the case it exists for either.
count_lines() {
    printf '%s\n' "$1" | sed '/^$/d' | wc -l | tr -d ' '
}

# Says what the message pass did, clean or not. The range and the number of
# messages read are printed every time: a pass that quietly read nothing is the
# failure this whole script is built against, and a count is the only thing that
# shows it.
report_messages() {
    local mpos_line mpos_joined mnegative

    if [ "$msg_state" != scanned ]; then
        echo "lint-reference: commit messages NOT SCANNED — $msg_why."
        echo "  Check 2 did not run. Shingle them by hand before you push, or say so."
        return 0
    fi

    if [ -z "$msg_control" ] || ! printf '%s' "$msg_control" | grep -q 'ok$'; then
        echo "lint-reference: the commit-message controls did not fire — printing no count." >&2
        echo "  $msg_control" >&2
        exit 2
    fi
    read -r _ mpos_line mpos_joined mnegative _ <<< "$(printf '%s' "$msg_control" | tr '\t' ' ')"

    echo "lint-reference: commit messages — $msg_commits message(s) in $msg_range," \
        "read whole; published-ness judged against $msg_base."
    echo "lint-reference: message controls — positive (one line) $mpos_line," \
        "positive (split across a wrap) $mpos_joined, negative $mnegative."
    if [ "$msg_commits" -eq 0 ]; then
        echo "  The range is empty: HEAD adds nothing to $msg_base. Nothing was scanned," \
            "and that is why the count above is zero."
    fi
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

    scan_out=$(run_scan "$n" "$corpus" "${fixture_docs[@]}")
    control=$(printf '%s\n' "$scan_out" | grep '^CONTROL' || true)
    cite_out=$(run_citations "$corpus" 2 "$fixtures/docs/citations.md")

    if [ -z "$control" ] || ! printf '%s' "$control" | grep -q 'ok$'; then
        echo "lint-reference: the self-test's controls did not fire — printing nothing." >&2
        echo "  $control" >&2
        exit 2
    fi

    # The blind spot, pinned in both directions. `docs/blind-spot.md` carries nine
    # consecutive words of the fixture corpus and no ten of them, so the gate as shipped
    # must walk past it and a scan one word shorter must find it. The header explains why
    # ten and not eight; this is what stops that from being only an explanation. Asserting
    # the miss alone would be satisfied by a scanner that had stopped working, so the
    # hit at nine is the half that carries the weight.
    #
    # Both lengths are literal rather than derived from the default, because a check that
    # reads the number it is testing from the thing it is testing passes whatever that
    # number becomes. Widen the gate and this goes red on purpose.
    blind_spot="$fixtures/docs/blind-spot.md"
    if [ ! -f "$blind_spot" ]; then
        echo "lint-reference: $blind_spot is missing — the blind spot is unpinned" >&2
        exit 2
    fi

    count_hits() {
        printf '%s\n' "$1" |
            awk -F'\t' '$1 !~ /^(CORPUS|FILES|CONTROL)$/ && NF >= 4' |
            sed '/^$/d' | wc -l | tr -d ' '
    }

    blind_at_ten=$(count_hits "$(run_scan 10 "$corpus" "$blind_spot")")
    blind_at_nine=$(count_hits "$(run_scan 9 "$corpus" "$blind_spot")")

    if [ "$blind_at_ten" -ne 0 ] || [ "$blind_at_nine" -lt 1 ]; then
        echo "lint-reference: SELF-TEST FAILED — the blind spot is not where the header says." >&2
        echo "  $blind_spot must yield 0 runs at 10 words and at least 1 at 9;" >&2
        echo "  it yielded $blind_at_ten at 10 and $blind_at_nine at 9." >&2
        echo "  Either the fixture's planted run changed length, or the gate did." >&2
        exit 1
    fi

    # ------------------------------------------------------------------
    # Check 2, on a repository built for the purpose.
    #
    # Four fixture messages are committed into a throwaway repository: two on
    # `main`, two on a branch cut from it. `main`'s first message carries a
    # ten-word run of the fixture corpus and the branch's second carries another,
    # split across a wrap the way a wrapped message body splits one.
    #
    # That shape is what makes the check testable in both directions at once. The
    # branch's run must be found — a scanner that has quietly stopped working
    # cannot satisfy that — and `main`'s must NOT be, because it is behind the
    # merge base and the range is what the branch adds. Widen the range to the
    # whole history and the second half goes red; narrow the scan back to files
    # and the first half does.
    #
    # A throwaway repository rather than this one: the fixtures would otherwise
    # have to be committed into the real history to be readable, which is both
    # permanent and the exact thing this check exists to stop.
    # ------------------------------------------------------------------
    # Absolute: `git -C` moves git's working directory, so a path relative to the
    # repository root would be read relative to the throwaway repository instead.
    message_fixtures="$root/$fixtures/messages"
    for required in 00-before-the-merge-base 01-the-merge-base 02-paraphrase 03-wrapped-run; do
        if [ ! -f "$message_fixtures/$required.txt" ]; then
            echo "lint-reference: $message_fixtures/$required.txt is missing —" \
                "the commit-message check is unpinned" >&2
            exit 2
        fi
    done

    msgrepo="$scratch/fixture-repo"
    mkdir -p "$msgrepo"

    # The ambient git configuration is cut out deliberately: a global hooksPath, a
    # signing key or a template directory would otherwise decide whether the
    # self-test passes on this machine, and a check whose answer depends on whose
    # laptop it runs on is not a check.
    fixture_git() {
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
            env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
            git -C "$msgrepo" \
            -c user.name="lint-reference self-test" \
            -c user.email="self-test@example.invalid" \
            -c commit.gpgsign=false \
            -c core.hooksPath=/dev/null \
            "$@"
    }

    fixture_commit() {
        fixture_git commit -q --allow-empty --cleanup=verbatim -F "$message_fixtures/$1.txt"
    }

    fixture_git init -q -b main > /dev/null 2>&1
    fixture_commit 00-before-the-merge-base
    fixture_commit 01-the-merge-base
    fixture_git checkout -q -b work
    fixture_commit 02-paraphrase
    fixture_commit 03-wrapped-run

    planted=$(fixture_git rev-parse --short=9 HEAD)

    # The gate. No --range, so the range is the one the script works out for
    # itself: merge-base(main, HEAD)..HEAD, which is the two commits `work` adds.
    base_ref=main
    commit_range=""
    scan_messages "$msgrepo" "$corpus"
    gate_violations=$(count_lines "$msg_violations")
    gate_advisories=$(count_lines "$msg_advisories")

    if [ "$msg_state" != scanned ] ||
        [ "$msg_commits" -ne 2 ] ||
        [ "$msg_hits" -ne 1 ] ||
        [ "$gate_violations" -ne 1 ] ||
        [ "$gate_advisories" -ne 0 ] ||
        ! printf '%s' "$msg_violations" | grep -q "commit $planted," ||
        ! printf '%s' "$msg_violations" | grep -q '(joined)'; then
        echo "lint-reference: SELF-TEST FAILED — the commit-message check does not do" \
            "what the header says." >&2
        echo "  Expected: 2 messages read (the two the branch adds, not all four)," \
            "1 run, found" >&2
        echo "  in commit $planted, labelled joined, counted as a violation and not as" \
            "published." >&2
        echo "  Got: state $msg_state, $msg_commits message(s), $msg_hits run(s)," \
            "$gate_violations violation(s), $gate_advisories advisory(ies)." >&2
        printf '%s\n' "$msg_violations" "$msg_advisories" | sed '/^$/d; s/^/    /' >&2
        echo "  Either a planted run changed length, or the range stopped being the" \
            "branch's own." >&2
        exit 1
    fi

    if [ -z "$msg_control" ] || ! printf '%s' "$msg_control" | grep -q 'ok$'; then
        echo "lint-reference: SELF-TEST FAILED — the message pass ran without its" \
            "controls firing." >&2
        echo "  $msg_control" >&2
        exit 1
    fi

    # The same hit, judged against a base that already contains it: it must be
    # reported and must not count as a violation. This is the half of the design
    # that keeps the gate from going permanently red over history nobody can
    # rewrite, and without a case it would only be a paragraph in the header.
    base_ref=work
    commit_range="main..HEAD"
    scan_messages "$msgrepo" "$corpus"
    pub_violations=$(count_lines "$msg_violations")
    pub_advisories=$(count_lines "$msg_advisories")
    base_ref=""
    commit_range=""

    if [ "$msg_hits" -ne 1 ] || [ "$pub_violations" -ne 0 ] || [ "$pub_advisories" -ne 1 ]; then
        echo "lint-reference: SELF-TEST FAILED — a run in a published message is not" \
            "being reported as advisory." >&2
        echo "  Expected the same 1 run, 0 violation(s), 1 advisory; got $msg_hits run(s)," \
            "$pub_violations violation(s), $pub_advisories advisory(ies)." >&2
        exit 1
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
    echo "lint-reference: self-test blind spot — the planted nine-word run is invisible at" \
        "10 ($blind_at_ten hit(s)) and found at 9 ($blind_at_nine hit(s)), as the header says."
    echo "lint-reference: self-test commit messages — 4 fixture messages committed, the 2" \
        "the branch adds were read, the planted wrapped run in $planted was found and" \
        "counted as a violation, the one behind the merge base was not read, and the same" \
        "run judged against a base that holds it came back advisory."

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
# --messages: check 2 on its own
#
# The pre-push run. A message can only be fixed while it is unpublished, so the
# useful moment to ask is the one before `git push`, and at that moment nobody
# wants to wait for two hundred files and a citation index.
# ---------------------------------------------------------------------------

if [ "$mode" = messages ]; then
    scan_messages "$root" "$corpus"
    report_messages

    violations=$(count_lines "$msg_violations")
    advisories=$(count_lines "$msg_advisories")
    echo "lint-reference: $msg_hits shared run(s) in the messages read —" \
        "$violations still fixable, $advisories already published."

    if [ "$advisories" -gt 0 ]; then
        echo
        printf '%s\n' "$msg_advisories"
        echo
        echo "lint-reference: the $advisories run(s) above are in messages already on" \
            "$msg_base."
        echo "  Nothing rewrites a published message but rewriting published history, so"
        echo "  these are reported and do not fail. They are counted so the number is known."
    fi

    if [ "$violations" -gt 0 ]; then
        echo
        printf '%s\n' "$msg_violations"
        echo
        echo "lint-reference: $violations run(s) in commit messages that are not yet on" \
            "$msg_base."
        echo "  This is the moment they can still be fixed: reword the message to say it in"
        echo "  our own words and cite the article, then replay the commits. After the push"
        echo "  the only remedies are leaving it or rewriting published history."
        exit 1
    fi

    echo "lint-reference: clean — no reproduced run in the $msg_commits message(s) read."
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

scan_out=$(run_scan "$n" "$corpus" "${targets[@]}")

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
# Check 2 — reproduced text in the commit messages the branch adds
# ---------------------------------------------------------------------------

scan_messages "$root" "$corpus"
report_messages

msg_violation_count=$(count_lines "$msg_violations")
msg_advisory_count=$(count_lines "$msg_advisories")
echo "lint-reference: $msg_hits shared run(s) in the messages read —" \
    "$msg_violation_count still fixable, $msg_advisory_count already published."

# ---------------------------------------------------------------------------
# Check 3 — citations resolve
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

# A published message is reported wherever it is found and never fails. It is
# printed before the verdict rather than inside it, so a clean exit still carries
# the number: a run nobody can remove is still a run somebody should know about.
if [ "$msg_advisory_count" -gt 0 ]; then
    echo
    printf '%s\n' "$msg_advisories"
    echo
    echo "lint-reference: the $msg_advisory_count run(s) above are in messages already on" \
        "$msg_base, and only rewriting published history would remove them."
    echo "  Reported, not failed. A gate that stays red over what nobody can change is a"
    echo "  gate people route around, and then it stops guarding what they can."
fi

if [ "$violation_count" -gt 0 ] || [ "$msg_violation_count" -gt 0 ] || [ "${cite_bad:-0}" -gt 0 ]; then
    echo
    [ "$violation_count" -gt 0 ] && printf '%s\n' "$violations" | sed '/^$/d'
    [ "$msg_violation_count" -gt 0 ] && printf '%s\n' "$msg_violations" | sed '/^$/d'
    [ "${cite_bad:-0}" -gt 0 ] && printf '%s\n' "$bad_citations" | sed '/^$/d'
    echo
    echo "lint-reference: $violation_count reproduced run(s) in the tree not in the baseline," \
        "$msg_violation_count in commit messages that can still be reworded," \
        "$cite_bad citation(s) that name no article."
    echo "  A run you have judged to be the sport's vocabulary rather than the book's"
    echo "  prose goes in $baseline with a note saying so;"
    echo "  scripts/lint-reference.sh --list prints the line to add."
    echo "  A run in a message has no baseline and is not meant to: reword the message and"
    echo "  replay the commits, which is possible now and not after the push."
    note_on_what_is_unchecked
    exit 1
fi

echo "lint-reference: clean — $files_scanned files and $msg_commits commit message(s)," \
    "$hit_count shared run(s) in the tree all carried," \
    "$cite_seen citation(s) all resolved."
note_on_what_is_unchecked
