#!/usr/bin/env bash
# Fetch the data sets the calibration bands were derived from, outside the repository,
# and record exactly which release was read.
#
#   scripts/fetch-calibration-data.sh [OUTPUT_DIR] [--seasons 2023,2024]
#
# Writes the play-by-play, participation and weekly-roster releases of the nflverse-data
# project to <OUTPUT_DIR>, writes a MANIFEST.txt beside them, and prints the lines
# scripts/calibration-sources.py wants. OUTPUT_DIR defaults to $FM_CALIBRATION_DATA_DIR,
# else a temporary directory outside the repository.
#
# WHY THIS EXISTS. Every band in Tools/simharness/Sources/simharness/Targets.swift was
# derived by scripts/calibration-sources.py from these three releases, and by policy no
# data set is in this repository. Nothing in the tree fetched them, so the derivation
# could not be re-run at all: each session that needed it re-discovered the URLs by hand.
#
# Three things that are not discoverable from a failure:
#
#   1. **The releases move under you.** These are rolling release tags, not versioned
#      files: the same URL serves a corrected data set later. Eleven bands already differ
#      from a fresh derivation in the last digit, which is what that looks like. So a
#      derivation must cite the release it read and not merely the season — which is what
#      MANIFEST.txt is for: quote its line beside the number you derived.
#   2. **The derivation reads more seasons than the bands are sourced from.** The bands
#      come from 2023 and 2024, but calibration-sources.py folds every season in its
#      SEASONS list and fails on a missing file. So the default season list here is read
#      out of that script rather than typed, per asset, and this script stops if it cannot
#      read it rather than fetching a set that will not run.
#   3. **An error page saved as a CSV looks exactly like data** until the derivation dies
#      somewhere unrelated, so every file is checked for the columns the derivation reads
#      before it is accepted.
#
# NOTHING THIS SCRIPT DOWNLOADS MAY ENTER THE REPOSITORY. ADR-0005 and CLAUDE.md rule 8
# keep real-league data out of the tree; a derived aggregate typed into Targets.swift is
# allowed, the data set it was derived from is not. The containment guard below is
# fetch-rulebook.sh's, copied rather than shared: that script must keep working on its own
# and a sourced library is one more thing that can be missing at the moment the guard is
# the only thing standing between a copyrighted PDF, or half a million rows about real
# players, and `git add -A`. Fix a hole in both.

set -euo pipefail

readonly RELEASE_BASE="https://github.com/nflverse/nflverse-data/releases/download"

say() { printf 'fetch-calibration-data: %s\n' "$*"; }
die() { printf 'fetch-calibration-data: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
usage: scripts/fetch-calibration-data.sh [OUTPUT_DIR] [--seasons 2023,2024]

  OUTPUT_DIR   where to put the data. Defaults to $FM_CALIBRATION_DATA_DIR, else a
               temporary directory. It may not be inside any checkout of this repository.
  --seasons    override the season list for all three assets. The default is per asset,
               read from scripts/calibration-sources.py, and is what the derivation needs.
  FORCE=1      re-download files that are already there.
EOF
}

# The three assets, by kind. Each line is: tag, filename pattern with @ for the season,
# and the columns the derivation reads, which are what a file is checked for. Bash 3.2 is
# the floor here (macOS ships it and the owner runs these on a Mac), so no associative
# arrays: one case, three arms.
asset_tag() {
    case "$1" in
        pbp) echo "pbp" ;;
        participation) echo "pbp_participation" ;;
        rosters) echo "weekly_rosters" ;;
    esac
}

asset_file() {
    case "$1" in
        pbp) echo "play_by_play_$2.csv.gz" ;;
        participation) echo "pbp_participation_$2.csv" ;;
        rosters) echo "roster_weekly_$2.csv" ;;
    esac
}

asset_columns() {
    case "$1" in
        pbp) echo "play_id game_id season_type posteam home_team" ;;
        participation) echo "nflverse_game_id play_id offense_personnel defenders_in_box" ;;
        rosters) echo "season status years_exp birth_date week game_type" ;;
    esac
}

# Which constant in calibration-sources.py names the seasons this asset is read for.
asset_seasons_constant() {
    case "$1" in
        pbp) echo "SEASONS" ;;
        participation) echo "PARTICIPATION_SEASONS" ;;
        rosters) echo "ROSTER_SEASONS" ;;
    esac
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        die "neither sha256sum nor shasum is available, so a fetched file cannot be
  identified. Identifying it is not optional: the manifest is what a derivation cites."
    fi
}

script_dir=$(cd "$(dirname "$0")" && pwd -P)
readonly DERIVATION="$script_dir/calibration-sources.py"

# --------------------------------------------------------------- 0. arguments

out=""
seasons_override=""
while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        --seasons)
            [ $# -ge 2 ] || die "--seasons needs a comma-separated list, e.g. --seasons 2023,2024"
            seasons_override=$(printf '%s' "$2" | tr ',' ' ')
            shift 2
            ;;
        --seasons=*)
            seasons_override=$(printf '%s' "${1#--seasons=}" | tr ',' ' ')
            shift
            ;;
        -*)
            usage >&2
            die "unknown option $1"
            ;;
        *)
            [ -z "$out" ] || die "give at most one output directory (got '$out' and '$1')"
            out=$1
            shift
            ;;
    esac
done

case "$seasons_override" in
    *[!0-9\ ]*) die "--seasons takes four-digit seasons separated by commas" ;;
esac

# ------------------------------------------- 1. the seasons the derivation reads

# Read them out of the derivation rather than typing them here. The bands are sourced from
# 2023 and 2024, but the script folds every season in SEASONS and dies on a missing file,
# so a list typed here would drift into fetching a set the derivation cannot run on. If
# the constant cannot be read, stop: guessing produces exactly that failure, one 20 MB
# download later.
seasons_for() {
    local constant value
    constant=$(asset_seasons_constant "$1")
    # `awk 'NR==1'` rather than `head -1`, here and below: `head` closes the pipe on the
    # line it wanted, the writer dies of SIGPIPE, and `set -o pipefail` reads that as a
    # failed pipeline — so the script exits 141 somewhere that looks nothing like the
    # cause. awk reads its input out.
    value=$(sed -n "s/^$constant = \[\([0-9, ]*\)\].*/\1/p" "$DERIVATION" | tr -d ' ' | tr ',' ' ' | awk 'NR==1')
    if [ -z "$value" ]; then
        die "cannot read $constant out of $DERIVATION, so the seasons the derivation
  needs are unknown. That list is not guessable from here: the bands are sourced from two
  seasons and the script folds four. Read the constant yourself and pass --seasons."
    fi
    printf '%s' "$value"
}

[ -r "$DERIVATION" ] || die "$DERIVATION is missing; it is what the season lists are read from."

# ------------------------------------------------------- 2. where we may write

# Every worktree of this repository, the main checkout and the linked ones alike. NOT
# `rev-parse --show-toplevel`, which answers with whichever worktree you are standing in:
# run from one worktree, it calls a sibling worktree "outside the repository" and writes
# the data into it. Agents dispatched on this project each get their own worktree, so
# siblings are the normal case here, not an exotic one.
worktrees=$(git -C "$script_dir" worktree list --porcelain 2>/dev/null \
    | sed -n 's/^worktree //p' || true)

# Fail closed. `git` can fail for reasons that say nothing about where we are — missing
# from PATH, refusing a checkout owned by another uid as dubious, a stale GIT_DIR — and
# reading every one of those as "not in a repository" is precisely what disables the guard
# below.
if [ -z "$worktrees" ]; then
    d=$script_dir
    while [ "$d" != "/" ]; do
        if [ -e "$d/.git" ]; then
            die "cannot list this repository's worktrees, yet $d/.git exists — so this
  script is inside a checkout and the containment check cannot run.

  That check is the only thing keeping half a million rows of real-league data out of the
  tree (ADR-0005, CLAUDE.md rule 8), so this script will not run without it. Usually git is
  missing from PATH, or is refusing the checkout as dubiously owned. Try
  'git -C $script_dir status'; if it is the latter,
  'git config --global --add safe.directory $d'."
        fi
        d=$(dirname "$d")
    done
fi

if [ -z "$out" ]; then
    out=${FM_CALIBRATION_DATA_DIR-}
fi
if [ -z "$out" ]; then
    out=$(mktemp -d "${TMPDIR:-/tmp}/calibration-data.XXXXXX")
    say "no output directory given; using $out"
fi

# Resolve $out absolutely and through symlinks WITHOUT creating it: the check has to run
# before the mkdir, or a refusal still leaves a directory behind inside the tree. `pwd -P`
# is the portable symlink resolver and it needs a directory that exists, so resolve the
# nearest existing ancestor and re-attach the tail.
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
tail=""
probe=$out
while [ ! -d "$probe" ] && [ "$probe" != "/" ]; do
    tail="/$(basename "$probe")$tail"
    probe=$(dirname "$probe")
done
out="$(cd "$probe" && pwd -P)$tail"
case "$out" in /) ;; *) out=${out%/} ;; esac

while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    wt=$(cd "$wt" 2>/dev/null && pwd -P) || continue
    case "$out/" in
        "$wt"/*) die "refusing to write inside a checkout of this repository.
  $out is inside $wt.
  These are real-league data sets: the tree carries derived aggregates and never the data
  (ADR-0005, CLAUDE.md rule 8). Pass a directory outside every checkout, or set
  FM_CALIBRATION_DATA_DIR." ;;
    esac
done <<EOF
$worktrees
EOF

mkdir -p "$out"

manifest="$out/MANIFEST.txt"
: >"$manifest.part"
{
    printf '# calibration data, fetched by scripts/fetch-calibration-data.sh\n'
    printf '# fetched-at\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '# release-base\t%s\n' "$RELEASE_BASE"
    printf '# A derivation cites the release it read, not just the season: quote the line\n'
    printf '# for the file you folded beside the number you derived.\n'
    printf '# file\tbytes\tsha256\trelease-last-modified\tetag\n'
} >>"$manifest.part"

# ------------------------------------------------------------- 3. the download

header_value() {
    # The LAST occurrence: curl -D over a redirect chain writes every response's headers,
    # and only the final one is the asset's.
    tr -d '\r' <"$1" | sed -n "s/^[Ll][Aa][Ss][Tt]-[Mm][Oo][Dd][Ii][Ff][Ii][Ee][Dd]: //p" | tail -1
}

header_etag() {
    tr -d '\r' <"$1" | sed -n "s/^[Ee][Tt][Aa][Gg]: //p" | tail -1
}

header_length() {
    tr -d '\r' <"$1" | sed -n "s/^[Cc][Oo][Nn][Tt][Ee][Nn][Tt]-[Ll][Ee][Nn][Gg][Tt][Hh]: //p" | tail -1
}

first_line_of() {
    # The header row, whether or not the file is gzipped. `|| true` around the gunzip
    # because `head` closing the pipe kills it with SIGPIPE, which `set -o pipefail` reads
    # as a failed pipeline: without this the script exits 141 with no message at all.
    case "$1" in
        *.gz) { gzip -cd <"$1" 2>/dev/null || true; } | head -1 ;;
        *) head -1 "$1" ;;
    esac
}

check_columns() {
    local file kind line column
    file=$1
    kind=$2
    line=$(first_line_of "$file" | tr -d '\r')
    for column in $(asset_columns "$kind"); do
        case ",$line," in
            *",$column,"*) ;;
            *) die "$file has no '$column' column, so it is not the $kind release the
  derivation reads — most likely an error page or a truncated transfer saved under the
  right name. Delete it and re-run with FORCE=1. Its first line begins:
  $(printf '%.120s' "$line")" ;;
        esac
    done
}

fetch_one() {
    local kind season file url dest hdr bytes sha modified etag remote_length
    kind=$1
    season=$2
    file=$(asset_file "$kind" "$season")
    url="$RELEASE_BASE/$(asset_tag "$kind")/$file"
    dest="$out/$file"
    hdr="$out/.headers.$$"

    if [ -s "$dest" ] && [ "${FORCE-}" != 1 ]; then
        say "reusing $file (set FORCE=1 to re-download)"
        # HEAD anyway: a rolling release tag is served from the same URL after the data
        # set is corrected, and a local copy from before that is the quiet way to derive a
        # band nobody can reproduce. Compare the lengths and say so.
        curl -sSI -L --fail --max-time 120 -D "$hdr" -o /dev/null "$url" \
            || say "  warning: could not re-check $url, so the release headers below are unknown"
    else
        say "downloading $file"
        # --fail so an error page is not saved as data, and .part so an interrupted
        # transfer never lands at $dest for the reuse path above to trust next run.
        curl -sSL --fail --max-time 900 -D "$hdr" -o "$dest.part" "$url" \
            || die "download failed from $url"
        [ -s "$dest.part" ] || die "downloaded an empty file from $url"
        mv "$dest.part" "$dest"
    fi

    case "$file" in
        *.gz) gzip -t "$dest" 2>/dev/null || die "$dest is not readable as gzip — a
  truncated transfer. Re-run with FORCE=1." ;;
    esac
    check_columns "$dest" "$kind"

    bytes=$(wc -c <"$dest" | tr -d ' ')
    sha=$(sha256_of "$dest")
    modified=""
    etag=""
    remote_length=""
    if [ -s "$hdr" ]; then
        modified=$(header_value "$hdr")
        etag=$(header_etag "$hdr")
        remote_length=$(header_length "$hdr")
    fi
    rm -f "$hdr"
    [ -n "$modified" ] || modified="unknown"
    [ -n "$etag" ] || etag="unknown"

    if [ -n "$remote_length" ] && [ "$remote_length" != "$bytes" ]; then
        say "  WARNING: the release now serves $remote_length bytes and the local $file is $bytes."
        say "  The release moved under this copy. Re-run with FORCE=1 before deriving anything."
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' "$file" "$bytes" "$sha" "$modified" "$etag" >>"$manifest.part"
    say "  $bytes bytes, sha256 $sha, release last modified: $modified"
}

for kind in pbp participation rosters; do
    if [ -n "$seasons_override" ]; then
        kind_seasons=$seasons_override
    else
        kind_seasons=$(seasons_for "$kind")
    fi
    say "$kind ($(asset_tag "$kind")): seasons $kind_seasons"
    for season in $kind_seasons; do
        fetch_one "$kind" "$season"
    done
done

mv "$manifest.part" "$manifest"

# ------------------------------------------------------------------ 4. report

echo
say "manifest written to $manifest:"
echo
sed 's/^/    /' "$manifest"
echo
cat <<EOF
fetch-calibration-data: ready.

    export FM_CALIBRATION_DATA_DIR=$out

  The derivation (docs/reference/calibration-sources.md):

    python3 scripts/calibration-sources.py $out
    python3 scripts/calibration-sources.py --rosters $out

  A band this produces is cited by the release it was read from, not just by the season:
  quote the MANIFEST.txt line for the file you folded. A number that differs from
  Targets.swift is reported, never applied here — correcting a band and retuning to one
  are different things (CLAUDE.md rule 9).

EOF
