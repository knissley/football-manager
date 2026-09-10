#!/usr/bin/env bash
#
# harness-reach.sh — can this change reach the calibration harness?
#
# Every fix runs `simharness --games 400` at two seeds, on the branch and again in
# each review round, so that nothing tunes the engine by accident. For a change the
# harness cannot see — a hundred lines of rivalry generation the calibration world never
# draws (#64) — that is four sweeps and ten minutes spent proving a negative. The reason
# the rule was unconditional is that "the harness cannot see this change" was an argument
# a reviewer wrote, and an argument stays true only until someone adds rivalries to the
# harness world. This makes it a proof the tooling produces (#72).
#
# The claim it can make is narrow, and it is this: the harness's output is a function of
# the world it generates and the code it runs. If neither moved, neither did the output.
#
#   1. Nothing changed in the engine's own sources — the trees below — against the base.
#   2. The world `simharness` generates is byte-for-byte the same league at seeds 7 and
#      11, compared through `--world-checksum-only` on a build of the base and a build of
#      the working tree.
#
# Both, and the answer is `skip`. Either one fails and the answer is `run`, which is also
# what it answers when it cannot tell.
#
# Usage:
#   scripts/harness-reach.sh <base-ref>   decide against that ref, e.g. origin/main
#   scripts/harness-reach.sh --self-test  run the script against scripted changes whose
#                                         answers are known
#
# Prints exactly one line on stdout — `skip` or `run` and the reason — and everything
# else on stderr, so `scripts/harness-reach.sh origin/main | tail -1` is safe to paste
# into a PR. Exits 0 for `skip`, 1 for `run`, 2 when it could not decide.
#
# ## What it reads, and why that list
#
# `Packages/FMSimulation`, `Packages/FMCore` and `Packages/FMRandom` are the engine, the
# domain types it resolves over and the RNG that drives it; `Tools/simharness` is the
# harness itself, its world, its bands and its arithmetic. Each package's `Package.swift`
# is in the list too: a build setting is not source but it reaches the output all the
# same.
#
# `Packages/FMGeneration` is deliberately *not* in the list, because it is the whole
# point: generation reaches the harness only through the world it builds, and the checksum
# covers every part a `GeneratedWorld` stores that can reach a snap — the players map the
# engine is handed included, and every variable-length group with its length. What it
# leaves out is named in its own doc comment and is cosmetic: the college pool beyond its
# size, a club's colours, the boundary between its city and nickname. The exception is
# `WeatherGenerator.swift`, which the harness calls directly for every game: the weather is
# drawn per game from the stadium, the week and a seed, so a change there reaches a snap
# without changing anything a world stores, and no checksum of a world could notice. Its
# manifest is watched with it.
#
# ## What it does not check
#
# The toolchain. Two builds of the same source with different compilers can differ in the
# last bit of a `Double`, and this compares checksums from two builds made minutes apart
# on one machine, which is the case it is for. It also says nothing about tests, docs or
# any other tool — only about whether the calibration rows can move.
#
# ## The self-test
#
# `--self-test` is the test for this script, in the shape `lint-sim.sh --self-test` uses.
# It copies the working tree into a scratch repository, commits it as a base, and then
# applies six scripted changes whose answers are known: an engine constant (`run`), a
# docs-only edit (`skip`), a generator constant the harness world shows (`run`, and it
# must come from the checksum rather than the file list), a generator constant the
# harness world never draws (`skip`), and the two the first review round of #72 found —
# the players map diverging from the rosters, and a depth chart repartitioned over the
# same men (`run`, both by the checksum). It builds a harness per scenario that reaches
# one — a few minutes on a warm Linux container, longer from cold — so run it when you
# change this script. CI does not, deliberately: the determinism step in the `test` job is
# the cheap guard that runs on every push.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

# The trees whose change can reach a calibration row other than through the generated
# world. See the header for why FMGeneration is not here and why one file of it is.
engine_paths=(
    Packages/FMSimulation/Sources
    Packages/FMCore/Sources
    Packages/FMRandom/Sources
    Tools/simharness/Sources
    Packages/FMSimulation/Package.swift
    Packages/FMCore/Package.swift
    Packages/FMRandom/Package.swift
    Tools/simharness/Package.swift
    Packages/FMGeneration/Sources/FMGeneration/WeatherGenerator.swift
    # WeatherGenerator is compiled by FMGeneration's manifest, and a build setting reaches
    # the output as surely as source does, so the manifest is watched even though the rest
    # of that package's sources deliberately are not.
    Packages/FMGeneration/Package.swift
)

# The seeds the backlog's before-and-after rule names.
seeds=(7 11)

usage() {
    echo "usage: scripts/harness-reach.sh <base-ref>"
    echo "       scripts/harness-reach.sh --self-test"
}

# Progress and diagnosis go to stderr; the verdict is the only thing on stdout.
note() { printf '%s\n' "$*" >&2; }

verdict() {
    printf '%s  %s\n' "$1" "$2"
    case "$1" in
        skip) exit 0 ;;
        run) exit 1 ;;
    esac
}

scratch=$(mktemp -d "${TMPDIR:-/tmp}/harness-reach.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

command -v swift >/dev/null 2>&1 || {
    note "harness-reach: no swift on PATH — see docs/tools.md#getting-a-toolchain"
    exit 2
}
git rev-parse --git-dir >/dev/null 2>&1 || {
    note "harness-reach: not inside a git repository"
    exit 2
}

# --- building and asking a tree --------------------------------------------

# Build the harness in a tree. The log is kept and printed only if the build fails, so a
# successful run says nothing that is not the verdict.
build_harness() {
    # Declared apart: `local` expands all of its arguments before it assigns any of them,
    # so `local a=$1 b=$a` reads an unset `a` and, under `set -u`, dies.
    local tree=$1 label=$2
    local log="$scratch/build-$label.log"
    note "harness-reach: building the $label harness (this is the slow part)"
    if ! (cd "$tree" && swift build --package-path Tools/simharness) >"$log" 2>&1; then
        note "harness-reach: the $label harness did not build:"
        sed 's/^/  /' "$log" >&2
        exit 2
    fi
}

# The world checksum a built tree reports for a seed.
world_checksum() {
    local tree=$1 seed=$2
    local log="$scratch/run-$seed.log" line
    if ! (cd "$tree" && swift run --skip-build --package-path Tools/simharness \
        simharness --world-checksum-only --seed "$seed") >"$log" 2>&1; then
        note "harness-reach: the harness in $tree could not report a checksum at seed $seed:"
        sed 's/^/  /' "$log" >&2
        note "  A base from before #72 has no --world-checksum-only and cannot be compared"
        note "  against; run the harness by hand for that one."
        exit 2
    fi
    line=$(awk '/^[[:space:]]*world checksum /{print $3; exit}' "$log")
    if [ -z "$line" ]; then
        note "harness-reach: no 'world checksum' line at seed $seed — the harness's header"
        note "  has changed shape and this script needs updating. It printed:"
        sed 's/^/  /' "$log" >&2
        exit 2
    fi
    printf '%s\n' "$line"
}

# A worktree of the base ref, extracted from the object database rather than checked out,
# so nothing touches the caller's index or working tree. HARNESS_REACH_CACHE keeps it
# between invocations, which is how the self-test builds the base once for all of them.
base_tree() {
    local sha=$1 dir
    if [ -n "${HARNESS_REACH_CACHE-}" ]; then
        dir="$HARNESS_REACH_CACHE/$sha"
    else
        dir="$scratch/base"
    fi
    if [ ! -e "$dir/.harness-reach-extracted" ]; then
        mkdir -p "$dir"
        git archive "$sha" | tar -x -C "$dir"
        : >"$dir/.harness-reach-extracted"
    fi
    printf '%s\n' "$dir"
}

# --- the decision -----------------------------------------------------------

decide() {
    local base=$1 sha changed untracked moved count listed base_dir here there
    if ! sha=$(git rev-parse --verify --quiet "${base}^{commit}"); then
        note "harness-reach: '$base' is not a commit this repository knows"
        exit 2
    fi
    note "harness-reach: against $base ($(printf '%.10s' "$sha"))"

    # Tracked changes and files that are not in the base at all. Without the second, a
    # new file in FMSimulation/Sources that has not been committed is invisible here and
    # the answer would be a confident, wrong `skip`.
    changed=$(git diff --name-only "$sha" -- "${engine_paths[@]}")
    untracked=$(git ls-files --others --exclude-standard -- "${engine_paths[@]}")
    moved=$(printf '%s\n%s\n' "$changed" "$untracked" | grep -v '^[[:space:]]*$' | sort -u || true)

    if [ -n "$moved" ]; then
        count=$(printf '%s\n' "$moved" | wc -l | tr -d ' ')
        listed=$(printf '%s\n' "$moved" | head -3 | tr '\n' ' ')
        verdict run "the engine's own sources moved against $base — $count file(s): ${listed}— run the harness"
    fi
    note "harness-reach: no engine source moved; comparing the world at seeds ${seeds[*]}"

    base_dir=$(base_tree "$sha")
    build_harness "$root" "working-tree"
    build_harness "$base_dir" "base"

    local here_sums=()
    for seed in "${seeds[@]}"; do
        here=$(world_checksum "$root" "$seed")
        there=$(world_checksum "$base_dir" "$seed")
        if [ "$here" != "$there" ]; then
            verdict run "the world at seed $seed is not the base's — $here here, $there at $base — run the harness"
        fi
        here_sums+=("$here")
    done

    verdict skip "no engine source moved against $base and the world is identical at seeds ${seeds[*]} (${here_sums[*]}) — the harness cannot see this change"
}

# --- the self-test ----------------------------------------------------------

# Replace text in a file, and fail if the text is not there: a fixture that stopped
# applying would otherwise quietly turn into a different scenario than the one named.
substitute() {
    local file=$1 expression=$2
    if [ ! -f "$file" ]; then
        note "harness-reach: self-test fixture $file no longer exists — update this script"
        exit 2
    fi
    sed "$expression" "$file" >"$file.harness-reach-tmp"
    if cmp -s "$file" "$file.harness-reach-tmp"; then
        rm -f "$file.harness-reach-tmp"
        note "harness-reach: self-test fixture edit no longer applies to $file:"
        note "  $expression"
        note "  Update the self-test to a constant that is still there. It must stay a real"
        note "  change to the thing it names, or the scenario tests nothing."
        exit 2
    fi
    mv "$file.harness-reach-tmp" "$file"
}

self_test_failures=0

# name, expected verdict, a word the reason must contain, and the edit as a shell command.
scenario() {
    local name=$1 expect=$2 must_say=$3 edit=$4 line status
    git -C "$sandbox" checkout --quiet -- .
    if ! (cd "$sandbox" && eval "$edit"); then
        note "harness-reach: the self-test could not set up '$name' — see above."
        exit 2
    fi

    set +e
    line=$(cd "$sandbox" && ./scripts/harness-reach.sh "$base_sha" 2>"$scratch/self-test.log")
    status=$?
    set -e

    local got=${line%%  *}
    local reason=${line#*  }
    local wanted_status=0
    [ "$expect" = run ] && wanted_status=1

    if [ "$got" = "$expect" ] && [ "$status" -eq "$wanted_status" ] &&
        printf '%s' "$reason" | grep -q "$must_say"; then
        note "  ok    $name → $expect"
        note "        $reason"
        return 0
    fi

    self_test_failures=$((self_test_failures + 1))
    note "  FAIL  $name"
    note "        expected $expect (exit $wanted_status) with a reason mentioning '$must_say'"
    note "        got '$line' (exit $status)"
    sed 's/^/        /' "$scratch/self-test.log" >&2
    return 0
}

self_test() {
    sandbox="$scratch/self-test-tree"
    mkdir -p "$sandbox"
    note "harness-reach: self-test — copying the working tree into a scratch repository"

    # HEAD's tracked content, then the working tree laid over it, so the self-test
    # exercises this script as it is now rather than as it was last committed.
    git archive HEAD | tar -x -C "$sandbox"
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        if [ -f "$file" ]; then
            mkdir -p "$sandbox/$(dirname "$file")"
            cp "$file" "$sandbox/$file"
        else
            rm -f "$sandbox/$file"
        fi
    done < <(
        git diff --name-only HEAD
        git ls-files --others --exclude-standard
    )

    git -C "$sandbox" init --quiet
    git -C "$sandbox" add -A
    git -C "$sandbox" -c user.name=self-test -c user.email=self-test@invalid \
        -c commit.gpgsign=false commit --quiet -m "harness-reach self-test base"
    base_sha=$(git -C "$sandbox" rev-parse HEAD)

    # One extraction and one build of the base serves every scenario.
    export HARNESS_REACH_CACHE="$scratch/base-cache"

    note "harness-reach: six scenarios; the five that reach a build take a few minutes"
    scenario "an engine constant changed" run "sources moved" \
        "$(
            cat <<'EDIT'
substitute Packages/FMSimulation/Sources/FMSimulation/Fumbles.swift \
    's/static let onSack = 0.085/static let onSack = 0.095/'
EDIT
        )"
    scenario "a docs-only change" skip "identical" \
        "printf '\n<!-- harness-reach self-test -->\n' >> docs/tools.md"
    scenario "a generator the harness world shows" run "world at seed" \
        "$(
            cat <<'EDIT'
substitute Packages/FMGeneration/Sources/FMGeneration/WorldGenerator.swift \
    's/public static let strengthSpread = 8.0/public static let strengthSpread = 9.0/'
EDIT
        )"
    scenario "a generator the harness world never draws" skip "identical" \
        "$(
            cat <<'EDIT'
substitute Packages/FMGeneration/Sources/FMGeneration/RivalryGenerator.swift \
    's/eventsPerPairPerSeason: Double = 0.55/eventsPerPairPerSeason: Double = 0.75/'
EDIT
        )"
    # The two the first review round found. Both are changes the checksum used to call
    # identical while the harness moved by hundreds of lines, so both belong here rather
    # than in a reviewer's memory.
    scenario "the players map diverging from the rosters" run "world at seed" \
        "$(
            cat <<'EDIT'
substitute Packages/FMGeneration/Sources/FMGeneration/WorldGenerator.swift \
    's/for player in roster { players\[player.id\] = player }/for player in roster { var quicker = player; quicker.ratings[.speed] = min(99, (quicker.ratings[.speed] ?? 60) + 5); players[player.id] = quicker }/'
EDIT
        )"
    scenario "a depth chart repartitioned over the same men" run "world at seed" \
        "$(
            cat <<'EDIT'
substitute Packages/FMGeneration/Sources/FMGeneration/RosterGenerator.swift \
    's/return DepthChart(order: order)/return DepthChart(order: { () -> [Position: [PlayerID]] in var moved = order; let filled = Position.allCases.filter { !(moved[$0] ?? []).isEmpty }; if filled.count > 1, let last = moved[filled[0]]?.last { moved[filled[0]]?.removeLast(); moved[filled[1]]?.insert(last, at: 0) }; return moved }())/'
EDIT
        )"

    if [ "$self_test_failures" -eq 0 ]; then
        note "harness-reach: self-test clean — six scenarios, all as expected."
        exit 0
    fi
    note "harness-reach: SELF-TEST FAILED — $self_test_failures scenario(s) answered wrongly."
    exit 1
}

case "${1-}" in
    "")
        note "harness-reach: a base ref is required, e.g. origin/main"
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
        note "harness-reach: unknown argument: $1"
        usage >&2
        exit 2
        ;;
    *)
        [ $# -eq 1 ] || {
            usage >&2
            exit 2
        }
        decide "$1"
        ;;
esac
