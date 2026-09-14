#!/usr/bin/env bash
#
# preflight.sh — one pre-push command, scoped to what the change can break.
#
# CLAUDE.md's *Before you push* list is twelve hand-typed commands and the standing brief
# adds a few more. Measured cold on a four-core container the whole list is about nine
# minutes, and a branch that moved one markdown file paid the same nine minutes as one
# that moved the resolver. Worse, each `swift test` run puts several hundred lines of
# green checkmarks into an agent's context and every later turn carries them.
#
# So: read the diff, pick the smallest set of checks that can still catch what this change
# could have broken, run them one at a time, and print one line each. The full output of
# every step goes to a file outside the checkout and only the summary reaches the
# terminal, so a run costs a dozen lines of context rather than a thousand.
#
# The claim it makes is narrow and it is this: the steps it ran are the ones CI runs over
# the trees this branch touched. It does not claim the branch is correct, and it replaces
# neither reading a game (`Tools/gamelog`) nor the before-and-after comparison a change to
# the engine owes.
#
# Usage:
#   scripts/preflight.sh                    pick a lane from the diff and run it
#   scripts/preflight.sh --full             force the engine lane (everything)
#   scripts/preflight.sh --lane docs        force one lane by name
#   scripts/preflight.sh --iterate <Suite>  the iteration loop: `swift test -c release
#                                           --filter <Suite>` in the package that owns it
#   scripts/preflight.sh --report           run, then print the summary fenced for a PR
#   scripts/preflight.sh --dry-run          print the plan and run nothing
#   scripts/preflight.sh --base <ref>       decide against a ref other than origin/main
#   scripts/preflight.sh --self-test        the script's own test; needs no toolchain
#
# Exits 0 when every step passed, 1 when a step failed — the summary names the step and
# its log path — and 2 when it could not set up: no toolchain, no base ref, a `$TMPDIR`
# inside the checkout.
#
# ## The lanes
#
# The blast radius is `git diff --name-only $(git merge-base <base> HEAD)`, which already
# includes the working tree, plus the files nothing tracks yet. Each path picks a lane and
# the run is the union of what those lanes ask for; the name printed is the highest one
# reached.
#
#   docs    everything that is not source: docs, scripts, fixtures, the skills. The lints,
#           the census, the reference lint over the tree and over the branch's commit
#           messages, the two Python self-tests, the two documents that are diffed against
#           a command's output — `docs/testing.md`'s census table and
#           `docs/play-record.md`'s footprint — and the traceability suite by `--filter`,
#           which is the one test that reads the reference documents.
#   tests   the docs lane, plus the full debug suite of each package whose `Tests/` moved.
#   tools   the docs lane, plus the build and suite of each tool whose sources moved, and
#           `playsize` — which is also the proof that the FM* modules link standalone.
#   engine  everything in CLAUDE.md's Commands block, `harness-reach.sh` against the base,
#           and — when it says `run` — a release build of the harness and 400 games at
#           seeds 7 and 11, each captured to a file `harness-compare.sh` can read.
#
# A change under `Packages/*/Sources` is the engine lane, so a test file and a source file
# together escalate to it: the union of a `tests` path and an `engine` path is `engine`.
# Any `Package.swift`, and anything under `.github/workflows/`, select `engine` too — a
# build setting or a CI step reaches the output as surely as source does, which is the
# reasoning `harness-reach.sh` already uses for watching the manifests.
#
# `Tools/simharness/Sources` selects `engine` rather than `tools`, because that tree is on
# `harness-reach.sh`'s watched list: the harness's own world, bands and arithmetic can
# move a calibration row. The issue that asked for this script did not say which lane that
# tree belonged to; this is the conservative reading, written down here so the next reader
# can disagree with it on purpose rather than by accident.
#
# A change under `scripts/` adds that script's own self-test to whatever lane the rest of
# the diff picked. Most of those self-tests are in the docs lane already; the two that are
# not — `harness-reach.sh`'s, which builds a harness per scenario, and this script's — run
# only when their own script moved.
#
# ## Why it stops at the first failure
#
# A failing step is going to be fixed and the run repeated, so spending the remaining
# minutes gathering findings nobody will read is waste. The summary names the step that
# failed and its log path, and the tail of that log goes to stderr so the reason is in
# front of you without the preceding thousand lines of green.
#
# ## Where the logs go
#
# `${TMPDIR:-/tmp}/preflight-<date>-<pid>/`, one file per step, never inside the checkout —
# a log under the tree is a file the next `git status` reports and somebody eventually
# commits. If `$TMPDIR` resolves inside this repository the script refuses to run rather
# than quietly writing there.
#
# ## The self-test
#
# `--self-test` is the test for this script, in the shape `harness-reach.sh --self-test`
# uses. It builds a throwaway repository under `$TMPDIR` holding nothing but the paths the
# lane rules name, applies a scripted change per lane plus the escalation case, and
# asserts the lane chosen and the steps listed through `--dry-run`. No Swift runs, so it
# costs about a second and CI runs it on every push.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

targets_file=Tools/simharness/Sources/simharness/Targets.swift
seeds=(7 11)

# Progress and diagnosis go to stderr; the summary block is the only thing on stdout, so
# `scripts/preflight.sh > block.txt` is the block and nothing else.
note() { printf '%s\n' "$*" >&2; }

die() {
    note "preflight: $*"
    exit 2
}

usage() {
    cat <<'USAGE'
usage: scripts/preflight.sh [--lane docs|tests|tools|engine | --full]
                            [--base REF] [--report] [--dry-run]
       scripts/preflight.sh --iterate <SuiteName>
       scripts/preflight.sh --self-test
USAGE
}

# --- the two documents that are diffed against a command's output ------------
#
# Both are steps CI runs as inline shell. They are functions here rather than one-liners
# because a step command is `eval`ed in this shell, so a function name is a step; and
# because the awk that pulls the marked block out of the document is the part that goes
# wrong quietly, and it should read the same here as it does in the workflow.

census_table_matches_doc() {
    local doc="$log_dir/census-table-doc.md" fresh="$log_dir/census-table-fresh.md"
    awk '/<!-- test-census:begin -->/ { inside = 1; next }
         /<!-- test-census:end -->/   { inside = 0 }
         inside' docs/testing.md >"$doc"
    if [ ! -s "$doc" ]; then
        printf 'docs/testing.md has lost its test-census markers, so the table below\n'
        printf 'them is checked against nothing.\n'
        return 1
    fi
    ./scripts/test-census.sh --markdown >"$fresh" || return 1
    if ! diff -u "$doc" "$fresh"; then
        printf '\ndocs/testing.md'"'"'s census table is not the tree'"'"'s census.\n'
        printf 'Regenerate it between the markers with ./scripts/test-census.sh --markdown\n'
        return 1
    fi
    printf 'docs/testing.md carries the census the tree produces.\n'
}

footprint_matches_doc() {
    local doc="$log_dir/footprint-doc.txt" fresh="$log_dir/footprint-fresh.txt"
    awk '/<!-- playsize:begin -->/ { inside = 1; next }
         /<!-- playsize:end -->/   { inside = 0 }
         inside' docs/play-record.md | sed '/^```/d' >"$doc"
    if [ ! -s "$doc" ]; then
        printf 'docs/play-record.md has lost its playsize markers, so the footprint\n'
        printf 'below them is checked against nothing.\n'
        return 1
    fi
    swift run --package-path Tools/playsize >"$fresh" || return 1
    if ! diff -u "$doc" "$fresh"; then
        printf '\ndocs/play-record.md'"'"'s footprint is not what the types measure.\n'
        printf 'Regenerate it between the markers with swift run --package-path Tools/playsize\n'
        return 1
    fi
    printf 'docs/play-record.md carries the footprint the types measure.\n'
}

# --- the plan ---------------------------------------------------------------
#
# Four parallel arrays, appended in the order the steps run. `st_kind` is `normal` for a
# step whose exit code is its verdict, `reach` for `harness-reach.sh` — whose exit 1 means
# "run the harness", not "failed" — and `harness` for a step that verdict gates.

st_name=()
st_cmd=()
st_kind=()
st_skip=()

add_step() {
    local name=$1 cmd=$2 kind=${3:-normal} skip=${4:-}
    local existing
    for existing in ${st_cmd[@]+"${st_cmd[@]}"}; do
        if [ "$existing" = "$cmd" ]; then
            return 0
        fi
    done
    st_name+=("$name")
    st_cmd+=("$cmd")
    st_kind+=("$kind")
    st_skip+=("$skip")
}

# The lints, the census and the self-tests that need nothing but the tree. Every lane runs
# these: they are a few seconds together and they are what CI fails on first.
plan_docs() {
    add_step "format lint" \
        "swift format lint --strict --recursive --parallel Packages/ Tools/"
    add_step "lint-sim" "./scripts/lint-sim.sh"
    add_step "lint-sim self-test" "./scripts/lint-sim.sh --self-test"
    add_step "test census" "./scripts/test-census.sh"
    add_step "test census self-test" "./scripts/test-census.sh --self-test"
    add_step "census table in docs/testing.md" "census_table_matches_doc"
    add_step "footprint in docs/play-record.md" "footprint_matches_doc"
    add_step "lint-reference (tree)" "./scripts/lint-reference.sh"
    add_step "lint-reference self-test" "./scripts/lint-reference.sh --self-test"
    add_step "lint-reference (messages)" "./scripts/lint-reference.sh --messages"
    add_step "harness-compare self-test" "./scripts/harness-compare.sh --self-test"
    add_step "calibration-sources self-test" \
        "python3 scripts/calibration-sources.py --self-test"
    add_step "harness-noise self-test" "python3 scripts/harness-noise.py --self-test"
}

# The one suite that reads the reference documents, by --filter. In the engine lane the
# whole FMSimulation suite runs and this would be a second pass over the same corpus, so
# there it is listed as skipped rather than dropped: a step that vanishes from the summary
# reads as a step nobody thought about.
plan_traceability() {
    local skip=${1:-}
    add_step "FMSimulation traceability (--filter)" \
        "swift test --package-path Packages/FMSimulation --filter InvariantsTraceabilityTests" \
        normal "$skip"
}

plan_package_suite() {
    add_step "$1" "swift test --package-path Packages/$1"
}

plan_tool() {
    case "$1" in
        playsize)
            add_step "playsize" "swift run --package-path Tools/playsize"
            ;;
        worldgen)
            # worldgen has no suite; nothing else compiles it, so the build is the check.
            add_step "worldgen (build)" "swift build --package-path Tools/worldgen"
            ;;
        *)
            add_step "$1 (build)" "swift build --package-path Tools/$1"
            add_step "$1" "swift test --package-path Tools/$1"
            ;;
    esac
}

# Everything in CLAUDE.md's Commands block, in its order, plus the harness decision and
# the two sweeps that decision gates.
plan_engine() {
    plan_docs
    plan_traceability "the full FMSimulation suite covers it"
    add_step "FMRandom" "swift test --package-path Packages/FMRandom"
    add_step "FMRandom (release)" "swift test -c release --package-path Packages/FMRandom"
    add_step "FMCore" "swift test --package-path Packages/FMCore"
    add_step "FMGeneration" "swift test --package-path Packages/FMGeneration"
    add_step "FMSimulation" "swift test --package-path Packages/FMSimulation"
    plan_tool playsize
    plan_tool worldgen
    plan_tool gamelog
    add_step "simharness" "swift test --package-path Tools/simharness"
    add_step "harness-reach" "./scripts/harness-reach.sh $base" reach
    add_step "harness release build" \
        "swift build -c release --package-path Tools/simharness" harness
    local seed
    for seed in "${seeds[@]}"; do
        add_step "harness 400 games, seed $seed" \
            "swift run -c release --skip-build --package-path Tools/simharness simharness --games 400 --no-timing --seed $seed" \
            harness
    done
}

# The self-test a changed script owes. Most are in the docs lane already and dedupe away;
# these two are the ones that are not.
script_self_test() {
    case "$1" in
        scripts/harness-reach.sh)
            add_step "harness-reach self-test" "./scripts/harness-reach.sh --self-test"
            ;;
        scripts/preflight.sh)
            add_step "preflight self-test" "./scripts/preflight.sh --self-test"
            ;;
    esac
}

# --- the blast radius -------------------------------------------------------

lane_rank() {
    case "$1" in
        docs) echo 0 ;;
        tests) echo 1 ;;
        tools) echo 2 ;;
        engine) echo 3 ;;
        *) echo -1 ;;
    esac
}

classify() {
    case "$1" in
        Package.swift | */Package.swift) echo engine ;;
        .github/workflows/*) echo engine ;;
        Packages/*/Sources/*) echo engine ;;
        Tools/simharness/Sources/*) echo engine ;;
        Packages/*/Tests/*) echo tests ;;
        Tools/*/Sources/* | Tools/*/Tests/*) echo tools ;;
        *) echo docs ;;
    esac
}

# `git diff --name-only <commit>` compares the working tree to that commit, so staged and
# unstaged changes are both in it. Files nothing tracks are not, and without them a new
# file in FMSimulation/Sources that has not been committed is invisible and the lane would
# be confidently too small — the same hole `harness-reach.sh` closes the same way.
changed_files() {
    {
        git -c core.quotepath=false diff --name-only "$1"
        git -c core.quotepath=false ls-files --others --exclude-standard
    } | grep -v '^[[:space:]]*$' | sort -u || true
}

sha256_of_stdin() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        echo "no-sha256-tool"
    fi
}

sha256_at() {
    if git cat-file -e "$1:$2" 2>/dev/null; then
        git show "$1:$2" | sha256_of_stdin
    else
        echo "absent"
    fi
}

# --- running ----------------------------------------------------------------

log_dir=""

make_log_dir() {
    local base_dir
    base_dir=${TMPDIR:-/tmp}
    base_dir=${base_dir%/}
    [ -d "$base_dir" ] || die "\$TMPDIR names $base_dir, which is not a directory"
    base_dir=$(cd "$base_dir" && pwd -P)
    # Never under the checkout: a log inside the tree is a file `git status` reports and
    # somebody eventually commits.
    case "$base_dir/" in
        "$root"/*)
            die "\$TMPDIR ($base_dir) is inside this checkout; point it somewhere else"
            ;;
    esac
    log_dir="$base_dir/preflight-$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$log_dir"
}

reach_verdict=""
reach_line=""

main_run() {
    local i j count name cmd kind skip log leaf started elapsed status
    local failed_index=-1
    count=${#st_name[@]}
    res_secs=()
    res_status=()
    res_detail=()
    res_log=()

    for ((i = 0; i < count; i++)); do
        name=${st_name[$i]}
        cmd=${st_cmd[$i]}
        kind=${st_kind[$i]}
        skip=${st_skip[$i]}

        if [ "$kind" = harness ] && [ "$reach_verdict" = skip ]; then
            skip="harness-reach says skip"
        fi
        if [ -n "$skip" ]; then
            res_secs+=(0)
            res_status+=("skipped")
            res_detail+=("$skip")
            res_log+=("-")
            continue
        fi

        # The log's name is the step's, so the summary's last column is enough to find
        # it under the directory the header names.
        leaf="$(printf '%02d' "$((i + 1))")-$(printf '%s' "$name" | tr -c 'A-Za-z0-9' '-').log"
        log="$log_dir/$leaf"
        note "preflight: [$((i + 1))/$count] $name"
        started=$(date +%s)
        status=0
        eval "$cmd" >"$log" 2>&1 || status=$?
        elapsed=$(($(date +%s) - started))

        if [ "$kind" = reach ]; then
            # 0 is `skip`, 1 is `run`, 2 is "could not decide" — which is also run.
            reach_line=$(tail -1 "$log")
            case "$status" in
                0) reach_verdict=skip ;;
                1) reach_verdict=run ;;
                *)
                    reach_verdict=run
                    reach_line="run  harness-reach could not decide (exit $status) — running the harness"
                    ;;
            esac
            res_secs+=("$elapsed")
            res_status+=("ok")
            res_detail+=("$leaf")
            res_log+=("$log")
            continue
        fi

        res_secs+=("$elapsed")
        res_log+=("$log")
        res_detail+=("$leaf")
        if [ "$status" -eq 0 ]; then
            res_status+=("ok")
        else
            res_status+=("FAILED (exit $status)")
            failed_index=$i
            # Nothing after a failure is attempted — see the header. They are recorded so
            # the summary still accounts for every step the lane planned.
            for ((j = i + 1; j < count; j++)); do
                res_secs+=(0)
                res_status+=("skipped")
                res_detail+=("an earlier step failed")
                res_log+=("-")
            done
            break
        fi
    done

    if [ "$failed_index" -ge 0 ]; then
        note ""
        note "preflight: ${st_name[$failed_index]} FAILED — the last 30 lines of its log:"
        tail -30 "${res_log[$failed_index]}" | sed 's/^/  /' >&2
    fi
    return 0
}

# --- the summary ------------------------------------------------------------

summary() {
    local i count name failed=0 total=0 ok=0 skipped=0
    count=${#st_name[@]}
    printf 'preflight  lane=%s  base=%s (%.10s)  %s file(s) changed\n' \
        "$lane" "$base" "$merge_base" "$changed_count"
    printf '  logs: %s\n' "$log_dir"
    printf '  Targets.swift sha256  head %.12s  base %.12s  (%s)\n' \
        "$targets_head" "$targets_base" "$targets_note"
    if [ -n "$reach_line" ]; then
        printf '  harness-reach: %s\n' "$reach_line"
    else
        printf '  harness-reach: not consulted (lane %s)\n' "$lane"
    fi
    printf '  %-36s %5s  %-16s %s\n' "step" "secs" "result" "log / why not"
    for ((i = 0; i < count; i++)); do
        name=${st_name[$i]}
        printf '  %-36s %5s  %-16s %s\n' \
            "$name" "${res_secs[$i]}" "${res_status[$i]}" "${res_detail[$i]}"
        total=$((total + res_secs[i]))
        case "${res_status[$i]}" in
            ok) ok=$((ok + 1)) ;;
            skipped*) skipped=$((skipped + 1)) ;;
            *)
                failed=$((failed + 1))
                failing_name=$name
                failing_log=${res_log[$i]}
                ;;
        esac
    done
    printf '  %s step(s): %s ok, %s skipped, %s failed — %ss total\n' \
        "$count" "$ok" "$skipped" "$failed" "$total"
    if [ "$failed" -gt 0 ]; then
        printf '  FAILED: %s — %s\n' "$failing_name" "$failing_log"
    fi
    summary_failed=$failed
}

# --- --iterate --------------------------------------------------------------

# The iteration loop the throughput proposal measured: FMSimulation's debug suite spends
# most of its time building the shared game corpus in an unoptimised binary, and the same
# suite under `-c release` is an order of magnitude faster. One suite at a time in release
# is how you iterate; the full debug suite runs once before the push.
iterate() {
    local suite=$1 file pkg
    command -v swift >/dev/null 2>&1 || die "no swift on PATH — see docs/tools.md"
    file=$(grep -rl --include='*.swift' -E "(struct|final class|class|enum)[[:space:]]+${suite}\b" \
        Packages/*/Tests Tools/*/Tests 2>/dev/null | head -1 || true)
    [ -n "$file" ] || die "no test target declares a suite named '$suite'"
    pkg=$(printf '%s\n' "$file" | cut -d/ -f1-2)
    note "preflight: $suite lives in $pkg"
    swift test -c release --package-path "$pkg" --filter "$suite"
}

# --- the self-test ----------------------------------------------------------

self_test_failures=0
sandbox=""
base_sha=""

# Nothing here is real: the lane rules read paths, not contents, so a one-word file at
# each path the rules name is the whole fixture tree.
fixture_tree() {
    local f
    for f in \
        docs/tools.md \
        docs/invariants.md \
        scripts/lint-sim.sh \
        scripts/harness-reach.sh \
        .github/workflows/ci.yml \
        Packages/FMCore/Package.swift \
        Packages/FMCore/Sources/FMCore/Cap.swift \
        Packages/FMCore/Tests/FMCoreTests/CapTests.swift \
        Packages/FMSimulation/Sources/FMSimulation/Fumbles.swift \
        Packages/FMSimulation/Tests/FMSimulationTests/ClockTests.swift \
        Tools/gamelog/Sources/gamelog/main.swift \
        Tools/gamelog/Tests/gamelogTests/DriveTests.swift \
        Tools/simharness/Sources/simharness/Targets.swift; do
        mkdir -p "$sandbox/$(dirname "$f")"
        printf 'fixture\n' >"$sandbox/$f"
    done
}

# name, expected lane, `;`-separated substrings the plan must list, `;`-separated
# substrings it must not, and the edit as a shell command run inside the sandbox.
scenario() {
    local name=$1 expect=$2 must=$3 must_not=$4 edit=$5
    local plan got_lane ok=1 needle old_ifs

    git -C "$sandbox" checkout --quiet -- .
    git -C "$sandbox" clean --quiet -fd
    if ! (cd "$sandbox" && eval "$edit"); then
        die "the self-test could not set up '$name' — see above"
    fi

    if ! plan=$(cd "$sandbox" && ./scripts/preflight.sh --dry-run --base "$base_sha" 2>&1); then
        note "  FAIL  $name — --dry-run exited non-zero"
        printf '%s\n' "$plan" | sed 's/^/        /' >&2
        self_test_failures=$((self_test_failures + 1))
        return 0
    fi

    got_lane=$(printf '%s\n' "$plan" | sed -n 's/^  lane=\([a-z]*\) .*/\1/p' | head -1)
    [ "$got_lane" = "$expect" ] || ok=0

    old_ifs=$IFS
    IFS=';'
    for needle in $must; do
        [ -n "$needle" ] || continue
        if ! printf '%s\n' "$plan" | grep -qF -- "$needle"; then
            ok=0
            note "        missing step: $needle"
        fi
    done
    for needle in $must_not; do
        [ -n "$needle" ] || continue
        if printf '%s\n' "$plan" | grep -qF -- "$needle"; then
            ok=0
            note "        unwanted step: $needle"
        fi
    done
    IFS=$old_ifs

    if [ "$ok" -eq 1 ]; then
        note "  ok    $name → $expect"
        return 0
    fi
    self_test_failures=$((self_test_failures + 1))
    note "  FAIL  $name — expected lane $expect, got '${got_lane:-none}'"
    printf '%s\n' "$plan" | sed 's/^/        /' >&2
    return 0
}

self_test() {
    local scratch docs_steps engine_steps no_engine
    scratch=$(mktemp -d "${TMPDIR:-/tmp}/preflight-self-test.XXXXXX")
    trap 'rm -rf "$scratch"' EXIT
    sandbox="$scratch/tree"
    mkdir -p "$sandbox/scripts"
    note "preflight: self-test — a scripted repository under $scratch"

    # The script as it is in the working tree, not as it was last committed.
    cp "$root/scripts/preflight.sh" "$sandbox/scripts/preflight.sh"
    chmod +x "$sandbox/scripts/preflight.sh"
    fixture_tree

    git -C "$sandbox" init --quiet
    git -C "$sandbox" add -A
    git -C "$sandbox" -c user.name=self-test -c user.email=self-test@invalid \
        -c commit.gpgsign=false commit --quiet -m "preflight self-test base"
    base_sha=$(git -C "$sandbox" rev-parse HEAD)

    docs_steps="swift format lint --strict"
    docs_steps="$docs_steps;./scripts/lint-sim.sh --self-test"
    docs_steps="$docs_steps;./scripts/lint-reference.sh --messages"
    docs_steps="$docs_steps;python3 scripts/harness-noise.py --self-test"
    docs_steps="$docs_steps;census_table_matches_doc"
    docs_steps="$docs_steps;footprint_matches_doc"
    docs_steps="$docs_steps;--filter InvariantsTraceabilityTests"

    # The two steps only the engine lane has. Both are checked as absences elsewhere, so
    # neither may be a substring of anything another lane lists.
    engine_steps="swift test -c release --package-path Packages/FMRandom"
    engine_steps="$engine_steps;--games 400 --no-timing --seed 11"
    no_engine="swift test -c release --package-path Packages/FMRandom;--games 400"

    note "preflight: ten scenarios"

    scenario "a docs-only change" docs \
        "$docs_steps" \
        "$no_engine;swift test --package-path Packages/FMCore;swift build --package-path Tools/gamelog" \
        "printf 'edited\n' >> docs/tools.md"

    scenario "a package's tests moved" tests \
        "$docs_steps;swift test --package-path Packages/FMCore" \
        "$no_engine;swift test --package-path Packages/FMGeneration;swift build --package-path Tools/gamelog" \
        "printf 'edited\n' >> Packages/FMCore/Tests/FMCoreTests/CapTests.swift"

    scenario "a tool's sources moved" tools \
        "$docs_steps;swift build --package-path Tools/gamelog;swift test --package-path Tools/gamelog;swift run --package-path Tools/playsize" \
        "$no_engine;swift test --package-path Packages/FMCore" \
        "printf 'edited\n' >> Tools/gamelog/Sources/gamelog/main.swift"

    scenario "an engine source moved" engine \
        "$engine_steps;swift test --package-path Packages/FMSimulation;swift test --package-path Packages/FMGeneration;harness-reach" \
        "" \
        "printf 'edited\n' >> Packages/FMSimulation/Sources/FMSimulation/Fumbles.swift"

    # The escalation case: on its own the test file is the `tests` lane, and the source
    # file beside it takes the whole run to `engine`.
    scenario "a test file and a source file together" engine \
        "$engine_steps;swift test --package-path Packages/FMSimulation;harness-reach" \
        "" \
        "printf 'edited\n' >> Packages/FMCore/Tests/FMCoreTests/CapTests.swift
         printf 'edited\n' >> Packages/FMCore/Sources/FMCore/Cap.swift"

    scenario "a manifest moved" engine \
        "$engine_steps;swift test --package-path Packages/FMGeneration" \
        "" \
        "printf 'edited\n' >> Packages/FMCore/Package.swift"

    scenario "the CI workflow moved" engine \
        "$engine_steps" \
        "" \
        "printf 'edited\n' >> .github/workflows/ci.yml"

    scenario "the harness's own sources moved" engine \
        "$engine_steps" \
        "" \
        "printf 'edited\n' >> Tools/simharness/Sources/simharness/Targets.swift"

    scenario "a script moved, and owes its self-test" docs \
        "$docs_steps;./scripts/harness-reach.sh --self-test" \
        "$no_engine" \
        "printf '# edited\n' >> scripts/harness-reach.sh"

    # The working-tree arm: a file nothing tracks yet is invisible to `git diff`.
    scenario "an uncommitted engine file nothing tracks" engine \
        "$engine_steps;swift test --package-path Packages/FMSimulation" \
        "" \
        "printf 'new\n' > Packages/FMSimulation/Sources/FMSimulation/Kickoff.swift"

    if [ "$self_test_failures" -eq 0 ]; then
        note "preflight: self-test clean — ten scenarios, all as expected."
        exit 0
    fi
    note "preflight: SELF-TEST FAILED — $self_test_failures scenario(s) planned wrongly."
    exit 1
}

# --- arguments --------------------------------------------------------------

base=origin/main
forced_lane=""
report=0
dry_run=0
mode=run
iterate_suite=""

while [ $# -gt 0 ]; do
    case "$1" in
        --self-test)
            mode=self-test
            shift
            ;;
        --full)
            forced_lane=engine
            shift
            ;;
        --lane)
            [ $# -ge 2 ] || die "--lane needs a name"
            forced_lane=$2
            [ "$(lane_rank "$forced_lane")" -ge 0 ] ||
                die "unknown lane '$forced_lane' — docs, tests, tools or engine"
            shift 2
            ;;
        --iterate)
            [ $# -ge 2 ] || die "--iterate needs a suite name"
            mode=iterate
            iterate_suite=$2
            shift 2
            ;;
        --base)
            [ $# -ge 2 ] || die "--base needs a ref"
            base=$2
            shift 2
            ;;
        --report)
            report=1
            shift
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            note "preflight: unknown argument: $1"
            usage >&2
            exit 2
            ;;
    esac
done

case "$mode" in
    self-test) self_test ;;
    iterate) iterate "$iterate_suite" ;;
esac

# --- deciding ---------------------------------------------------------------

git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"
base_commit=$(git rev-parse --verify --quiet "${base}^{commit}") ||
    die "'$base' is not a commit this repository knows — git fetch origin main first"
merge_base=$(git merge-base "$base_commit" HEAD 2>/dev/null) || merge_base=$base_commit

files=$(changed_files "$merge_base")
changed_count=$(printf '%s\n' "$files" | grep -c . || true)

lane=docs
tests_packages=()
tools_tools=()
scripts_changed=()

remember() {
    local -n arr=$1
    local value=$2 existing
    for existing in ${arr[@]+"${arr[@]}"}; do
        if [ "$existing" = "$value" ]; then
            return 0
        fi
    done
    arr+=("$value")
}

while IFS= read -r file; do
    [ -n "$file" ] || continue
    this=$(classify "$file")
    if [ "$(lane_rank "$this")" -gt "$(lane_rank "$lane")" ]; then
        lane=$this
    fi
    case "$file" in
        Packages/*/Tests/*)
            remember tests_packages "$(printf '%s\n' "$file" | cut -d/ -f2)"
            ;;
        Tools/*/Sources/* | Tools/*/Tests/*)
            remember tools_tools "$(printf '%s\n' "$file" | cut -d/ -f2)"
            ;;
    esac
    case "$file" in
        scripts/*) remember scripts_changed "$file" ;;
    esac
done <<EOF
$files
EOF

if [ -n "$forced_lane" ]; then
    lane=$forced_lane
fi

# A forced lane with nothing in the diff to name still has to mean something: `--lane
# tests` on a branch that changed no test runs every package's suite, and `--lane tools`
# every tool.
if [ "$lane" = tests ] && [ ${#tests_packages[@]} -eq 0 ]; then
    tests_packages=(FMRandom FMCore FMGeneration FMSimulation)
fi
if [ "$lane" = tools ] && [ ${#tools_tools[@]} -eq 0 ]; then
    tools_tools=(playsize worldgen gamelog simharness)
fi

case "$lane" in
    engine)
        plan_engine
        ;;
    *)
        plan_docs
        plan_traceability
        for pkg in ${tests_packages[@]+"${tests_packages[@]}"}; do
            plan_package_suite "$pkg"
        done
        if [ ${#tools_tools[@]} -gt 0 ]; then
            for tool in ${tools_tools[@]+"${tools_tools[@]}"}; do
                plan_tool "$tool"
            done
            plan_tool playsize
        fi
        ;;
esac
for script in ${scripts_changed[@]+"${scripts_changed[@]}"}; do
    script_self_test "$script"
done

targets_head=$(sha256_at HEAD "$targets_file")
targets_base=$(sha256_at "$merge_base" "$targets_file")
if [ "$targets_head" = "$targets_base" ]; then
    targets_note="unchanged"
else
    targets_note="MOVED — the bands are not the base's"
fi
if [ -f "$targets_file" ] && [ "$(sha256_of_stdin <"$targets_file")" != "$targets_head" ]; then
    targets_note="$targets_note; the working tree differs from HEAD"
fi

if [ "$dry_run" -eq 1 ]; then
    printf 'preflight: plan\n'
    printf '  lane=%s  base=%s (%.10s)  files=%s\n' \
        "$lane" "$base" "$merge_base" "$changed_count"
    printf '  steps:\n'
    for ((i = 0; i < ${#st_name[@]}; i++)); do
        if [ -n "${st_skip[$i]}" ]; then
            printf '    %-36s | skipped: %s\n' "${st_name[$i]}" "${st_skip[$i]}"
        else
            printf '    %-36s | %s\n' "${st_name[$i]}" "${st_cmd[$i]}"
        fi
    done
    exit 0
fi

command -v swift >/dev/null 2>&1 || die "no swift on PATH — see docs/tools.md"
command -v python3 >/dev/null 2>&1 || die "no python3 on PATH — two self-tests need it"

make_log_dir
note "preflight: lane $lane against $base, ${#st_name[@]} step(s); logs in $log_dir"
main_run

summary_failed=0
failing_name=""
failing_log=""
if [ "$report" -eq 1 ]; then
    printf '```text\n'
    summary
    printf '```\n'
else
    summary
fi

[ "$summary_failed" -eq 0 ] || exit 1
exit 0
