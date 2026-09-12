#!/usr/bin/env bash
# Fetch the playing rules and extract them to plain text, for verification only.
#
#   scripts/fetch-rulebook.sh [OUTPUT_DIR]
#
# Writes <OUTPUT_DIR>/rulebook.pdf and <OUTPUT_DIR>/rulebook.txt and prints the
# export line that scripts/lint-reference.sh wants. OUTPUT_DIR defaults to
# $FM_RULEBOOK_DIR, else a temporary directory outside the repository.
#
# WHY THIS EXISTS. Three things cost a session an hour each, every time, and none
# of them is discoverable from the failure:
#
#   1. The download URL is a Cloudinary asset with an opaque id that encodes
#      nothing about the season. It is not guessable and it is not linked from
#      anywhere obvious; it has to be scraped off the rules page.
#   2. `import pypdf` fails on this image's system Python with a missing
#      _cffi_backend and a Rust panic, because its `cryptography` is broken. The
#      error says nothing about needing a virtual environment.
#   3. **The asset behind that URL has been replaced in place.** The same link
#      that served the 2025 edition now serves 2026. A session that downloads
#      without checking gets a different rulebook than the one the project
#      targets and has no way to notice.
#
# So this script identifies the edition by checksum and refuses to guess. See
# docs/reference/rulebook-acquisition.md for what the editions differ by.
#
# NOTHING THIS SCRIPT PRODUCES MAY ENTER THE REPOSITORY. The rulebook is a
# copyrighted document; CLAUDE.md rule 8 allows a citation and forbids a copy.
# The script refuses to write inside any checkout of this repository — linked
# worktrees included — and, if it cannot work out where those are, refuses to run
# at all rather than run unguarded.

set -euo pipefail

readonly RULES_PAGE="https://operations.nfl.com/the-rules/nfl-rulebook/"
# Fallback only. Prefer the scrape: the id is opaque, so a new edition may appear
# at a new id, and a hardcoded link would then silently serve a stale document.
readonly FALLBACK_URL="https://static.www.nfl.com/image/upload/fl_attachment/league/tqivdkzt9mu6wdgsh1ku.pdf"

# Editions identified by checksum. Add a row when a new one is confirmed.
readonly MD5_2026="02dc74eecd96472eae1957b9917ad267"
readonly MD5_2025="883457f1f405bb4a4c78234941a23af2"

# Page counts, for cross-checking the extraction. The checksum already pins the edition;
# these catch an extractor that read only part of a document it correctly identified.
readonly PAGES_2026=91
readonly PAGES_2025=243

readonly TARGET_SEASON=2025   # CLAUDE.md. Changing it is deliberate, separate work.

say() { printf 'fetch-rulebook: %s\n' "$*"; }
die() { printf 'fetch-rulebook: %s\n' "$*" >&2; exit 1; }

# GNU coreutils on CI and in containers, BSD on a Mac. CLAUDE.md advertises this script
# and this project's developers are on Macs, where md5sum does not exist.
md5_of() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" | cut -d' ' -f1
    elif command -v md5 >/dev/null 2>&1; then
        md5 -q "$1"
    else
        die "neither md5sum nor md5 is available, so the edition cannot be identified.
  Identifying it is not optional: see the header of this script."
    fi
}

script_dir=$(cd "$(dirname "$0")" && pwd -P)

# Every worktree of this repository, the main checkout and the linked ones alike. NOT
# `rev-parse --show-toplevel`, which answers with whichever worktree you are standing in:
# run from one worktree, it calls a sibling worktree "outside the repository" and writes
# the book into it. Agents dispatched on this project each get their own worktree, so
# siblings are the normal case here, not an exotic one.
worktrees=$(git -C "$script_dir" worktree list --porcelain 2>/dev/null \
            | sed -n 's/^worktree //p' || true)

# Fail closed. `git` can fail for reasons that say nothing about where we are — missing
# from PATH, refusing a checkout owned by another uid as dubious, a stale GIT_DIR — and
# reading every one of those as "not in a repository" is precisely what disables the
# guard below. The previous version did exactly that, and would then download a
# copyrighted PDF into the tree. So: if git could not answer and a .git is sitting above
# us, stop rather than proceed unguarded.
if [ -z "$worktrees" ]; then
    d=$script_dir
    while [ "$d" != "/" ]; do
        if [ -e "$d/.git" ]; then
            die "cannot list this repository's worktrees, yet $d/.git exists — so this
  script is inside a checkout and the containment check cannot run.

  That check is the only thing keeping a copy of the copyrighted rulebook out of
  the tree (CLAUDE.md rule 8), so this script will not run without it. Usually git
  is missing from PATH, or is refusing the checkout as dubiously owned. Try
  'git -C $script_dir status'; if it is the latter,
  'git config --global --add safe.directory $d'."
        fi
        d=$(dirname "$d")
    done
fi

out=${1-${FM_RULEBOOK_DIR-}}
if [ -z "$out" ]; then
    out=$(mktemp -d "${TMPDIR:-/tmp}/rulebook.XXXXXX")
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

# Rule 8 is not advice. Refuse to put a copy of the book inside any checkout of this
# repository.
while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    wt=$(cd "$wt" 2>/dev/null && pwd -P) || continue
    case "$out/" in
        "$wt"/*) die "refusing to write inside a checkout of this repository.
  $out is inside $wt.
  The rulebook is copyrighted and must never be committed (CLAUDE.md rule 8).
  Pass a directory outside every checkout, or set FM_RULEBOOK_DIR." ;;
    esac
done <<EOF
$worktrees
EOF

mkdir -p "$out"

pdf="$out/rulebook.pdf"
txt="$out/rulebook.txt"

# ---------------------------------------------------------------- 1. download

if [ -s "$pdf" ] && [ "${FORCE-}" != 1 ]; then
    say "reusing $pdf (set FORCE=1 to re-download)"
else
    say "finding the link on $RULES_PAGE"
    url=$(curl -sL --max-time 30 "$RULES_PAGE" 2>/dev/null \
          | grep -oiE 'https?://[^"'"'"' ]*\.pdf' \
          | grep -i 'fl_attachment' | head -1 || true)
    if [ -n "$url" ]; then
        say "found $url"
    else
        url=$FALLBACK_URL
        say "scrape found nothing; falling back to the recorded link"
        say "  -> if this keeps happening the page has changed; re-find the link and update this script"
    fi
    say "downloading"
    # --fail so an error page is not saved as a rulebook, and .part so an interrupted
    # transfer never lands at $pdf for the reuse path above to trust on the next run.
    curl -sSL --fail --max-time 300 -o "$pdf.part" "$url" || die "download failed from $url"
    [ -s "$pdf.part" ] || die "downloaded an empty file from $url"
    mv "$pdf.part" "$pdf"
fi

# ------------------------------------------------------- 2. identify the edition

md5=$(md5_of "$pdf")
bytes=$(wc -c < "$pdf")
say "md5 $md5 ($bytes bytes)"

case "$md5" in
    "$MD5_2025")
        say "this is the 2025 edition — the season this project targets. Use it directly."
        edition=2025
        expected_pages=$PAGES_2025
        ;;
    "$MD5_2026")
        say "this is the 2026 edition."
        edition=2026
        expected_pages=$PAGES_2026
        ;;
    *)
        die "UNRECOGNISED EDITION.

  FIRST, rule out a bad download. An interrupted transfer or an error page saved as
  a PDF lands here too, and looks exactly like a new edition. This file is $bytes
  bytes. Re-run with FORCE=1 before concluding anything about editions, and do not
  add this checksum to the script until a clean download reproduces it.

  Otherwise: this checksum matches neither edition on file. The likeliest cause is that the
  asset was replaced again, the way the 2025 book was replaced by 2026 at this
  same URL — so you may be holding a rulebook for a season this project does not
  target, and every citation verified against it would be verified against the
  wrong book.

  Do not proceed and do not 'just use it'. Identify the edition (the season is
  named on page 1 and the change list is on page 2), tell the owner, and add its
  checksum to this script once it is confirmed.

  Known: 2025 $MD5_2025
         2026 $MD5_2026"
        ;;
esac

# ------------------------------------------------------------- 3. extract text

if [ -s "$txt" ] && [ "${FORCE-}" != 1 ]; then
    say "reusing $txt (set FORCE=1 to re-extract)"
else
    venv="$out/venv"
    if [ ! -x "$venv/bin/python" ]; then
        say "creating a virtual environment for pypdf"
        say "  (the system Python's pypdf import fails with a missing _cffi_backend —"
        say "   its cryptography is broken. This is not your fault and not fixable in place.)"
        python3 -m venv "$venv" >/dev/null 2>&1 || die "python3 -m venv failed; is python3-venv installed?"
        "$venv/bin/pip" install --quiet --disable-pip-version-check pypdf \
            || die "pip install pypdf failed (no network to the package index?)"
    fi
    say "extracting text"
    "$venv/bin/python" - "$pdf" "$txt" <<'PY'
import sys
from pypdf import PdfReader
src, dst = sys.argv[1], sys.argv[2]
reader = PdfReader(src)
with open(dst, "w", encoding="utf-8") as out:
    for n, page in enumerate(reader.pages, 1):
        out.write(f"\n===== PAGE {n} =====\n")
        out.write(page.extract_text() or "")
print(f"fetch-rulebook: {len(reader.pages)} pages")
PY
fi

# -------------------------------------------------------------- 4. sanity check

articles=$(grep -c '^ *ARTICLE [0-9]' "$txt" || true)
pages=$(grep -c '^===== PAGE ' "$txt" || true)
say "$pages pages, $articles article headings"
[ "$articles" -ge 300 ] || die "only $articles article headings — extraction looks wrong, not usable"
[ "$pages" = "$expected_pages" ] || die "extracted $pages pages, but the $edition edition has $expected_pages.
  The checksum matched, so the PDF is the right document and the extraction is not.
  Re-run with FORCE=1; if it persists, the pypdf here cannot read this document and
  a citation verified against a partial text is not verified at all."

# ------------------------------------------------------------------ 5. report

echo
if [ "$edition" != "$TARGET_SEASON" ]; then
    cat <<EOF
fetch-rulebook: ⚠ THIS IS THE $edition EDITION AND THE PROJECT TARGETS $TARGET_SEASON.

  The editions differ in exactly four articles, measured: Rule 6, Section 1,
  Articles 3, 5 and 6, and Rule 19, Section 2. Everywhere else they are
  word-identical, so cite this text freely. Inside those four it is wrong for our
  purposes, and one of them is a trap that reads as a widening rather than an
  error: read docs/reference/rulebook-acquisition.md before citing any of them.

  Adopting a $edition rule is a defect, not an improvement (CLAUDE.md).

EOF
fi
cat <<EOF
fetch-rulebook: ready. For scripts/lint-reference.sh:

    export FM_RULEBOOK_TEXT=$txt

EOF
