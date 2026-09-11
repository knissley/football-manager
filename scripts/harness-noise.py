#!/usr/bin/env python3
"""harness-noise.py — how far a calibration row moves when nothing changes.

Every branch in this backlog reports moved harness rows and has to answer the same
question: is this a mechanism, or did the games just resample? The last step of that
answer used to be a model — "assume each game is an independent draw, rates are binomial
and counts Poisson" — and nobody had ever measured what the harness actually does. This
script measures it.

## What it measures, and the distinction that matters

`simharness` takes ONE `--seed`, and that seed does two separate things (read
`Tools/simharness/Sources/simharness/main.swift`): it generates the world — rosters,
schemes, stadiums, who is good — and it seeds every game's weather and play draws. There
is no flag that holds one fixed and varies the other, so a plain seed-to-seed spread is a
COMBINED figure: sampling noise plus world-to-world variation. Calling that "sampling
noise" is the error this script exists to stop.

The two components are separated without changing the harness, by using the one thing the
seeding path does give us. Every per-game quantity is derived from the loop index alone
(`seed &+ index &* 7919` for the play draw, `seed &+ index &* 104_729` for the weather,
and home, away and week from `index`), so **a 200-game run is exactly the first 200 games
of the 400-game run at the same seed** — same world, same games, same draws. That makes
the pair a within-world contrast:

    D(s) = value(200 games, seed s) - value(400 games, seed s)

Both halves of D come from the same world, so the world cancels and what is left is the
run's own sampling. For a row that is a mean over games, value(400) = (A + B) / 2 where A
and B are the two 200-game halves, so D = (A - B) / 2 and

    Var(D) = Var(A)/4 + Var(B)/4 = (c/200)/2 = c/400 = Var_within(400 games)

taking Var(A) = c/200 for a mean over 200 games. The same answer falls out of the
covariance for any smooth statistic of the run, because Cov(value(200), value(400)) is
Var(value(200))/2. So the spread of D across seeds IS the within-world sampling floor of a
400-game run, and

    sigma_world = sqrt(max(0, sigma_total^2 - sigma_within^2))

is what is left: how much the row moves because the league is a different league.

## What it reads, and the rounding it has to undo

The printed table, because there is no unrounded source: `simharness` has no
machine-readable mode, and giving it one would mean editing the reporting code, which this
measurement must not move. So a row printed to one decimal is read to one decimal.

Rounding adds an independent uniform error of width q, variance q^2/12, and every sigma
here has that variance removed (Sheppard's correction). The width is taken **per reading,
not per row**: a row graded outside its band prints the decimals that put it outside
(docs/tools.md), so one row's precision differs between seeds according to its own verdict,
and a per-row constant would be wrong for exactly the rows near an edge. A sigma whose raw
spread was not more than twice the rounding removed from it is marked rather than reported
as a measurement — its floor is below what the printed column resolves.

Fields are runs of two or more spaces and the value is a plain decimal carrying the row's
own unit, which is the format `simharness` guarantees; a row printing more digits than its
band's nominal precision parses unchanged.

## How much to believe it

Three checks, each of which can fail:

1. `--self-test` builds a synthetic sweep whose league and sampling components are set by
   hand and requires the decomposition to recover both.
2. Every sweep runs a third, 100-game prefix. It is a longer lever arm on the same
   quantity than the 200-game one and must give the same sigma once the lever is divided
   out; `--summary` prints the agreement.
3. `--replicate <other.tsv>` compares the floors against a sweep on a disjoint set of seeds.

## Usage

    scripts/harness-noise.py --sweep                 run the sweep, write the TSV
    scripts/harness-noise.py --report                read the TSV, print the markdown table
    scripts/harness-noise.py --summary               the findings rather than the table
    scripts/harness-noise.py --replicate OTHER.TSV   the floors against another sweep
    scripts/harness-noise.py --self-test             fixtures; needs no harness and no data

`--sweep` needs a release build of the harness:

    swift build -c release --package-path Tools/simharness

Runs inside one invocation are back to back, and `--resume` records each chunk separately
so a sweep taken in pieces says so. Nothing about the wall clock can reach a value — two
runs of one binary at one seed are byte-identical, which CI asserts on every push — but
when a measurement was taken is a fact about it and belongs in the file.
"""

import argparse
import math
import os
import platform
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGETS = os.path.join(ROOT, "Tools", "simharness", "Sources", "simharness", "Targets.swift")
HARNESS = os.path.join(ROOT, "Tools", "simharness", ".build", "release", "simharness")
SWEEP = os.path.join(ROOT, "docs", "reference", "harness-noise-sweep.tsv")

FULL_GAMES = 400
HALF_GAMES = 200
# A third, shorter prefix. It is not needed for the floor — the half already gives it —
# but it gives the same quantity a second lever arm, and two lever arms that disagree
# would say the estimator is wrong before the numbers reach a doc. See `within_at`.
QUARTER_GAMES = 100
GAME_COUNTS = (FULL_GAMES, HALF_GAMES, QUARTER_GAMES)
DEFAULT_SEEDS = list(range(1, 31))

VERDICTS = {"ok", "OFF", "(ok)", "(OFF)", "stale", "unsourced", "n/a"}

FIELDS = re.compile(r" {2,}")


# --- Targets.swift ----------------------------------------------------------


class Target:
    """One calibration row as `Targets.swift` declares it."""

    def __init__(self, id, label, low, high, season, gate, decimals, unit):
        self.id = id
        self.label = label
        self.low = low
        self.high = high
        self.season = season
        self.gate = gate
        self.decimals = decimals
        self.unit = unit

    @property
    def key(self):
        """What identifies the row in a printed run: its label and its season.

        The rule-sensitive rows print one line per rulebook under the same label — the
        2025 variant and the 2024 one it is kept beside — and the season column is what
        tells them apart.
        """
        return (self.label, self.season)

    @property
    def step(self):
        """The printed value's last digit: the width of its rounding."""
        return 10.0 ** (-self.decimals)


def _season_printed(chunk):
    match = re.search(r"season:\s*\.seasons\((\d+)\.\.\.(\d+)\)", chunk)
    if match:
        low, high = int(match.group(1)), int(match.group(2))
        return str(low) if low == high else "%d-%02d" % (low, high % 100)
    match = re.search(r"season:\s*\.season\((\d+)\)", chunk)
    if match:
        return match.group(1)
    if re.search(r"season:\s*\.unsourced", chunk):
        return "-"
    return None


def parse_targets(text):
    """Every `CalibrationTarget(...)` in `Targets.swift`, in declaration order."""
    targets = []
    for chunk in text.split("CalibrationTarget(")[1:]:
        ident = re.search(r'id:\s*"([^"]+)"', chunk)
        label = re.search(r'label:\s*"([^"]+)"', chunk)
        if not ident or not label:
            continue
        season = _season_printed(chunk)
        if season is None:
            continue

        def number(name):
            match = re.search(r"%s:\s*(nil|-?[0-9]+(?:\.[0-9]+)?)" % name, chunk)
            if not match or match.group(1) == "nil":
                return None
            return float(match.group(1))

        gate = re.search(r"gate:\s*(true|false)", chunk)
        decimals = re.search(r"decimals:\s*([0-9]+)", chunk)
        unit = re.search(r'unit:\s*"([^"]*)"', chunk)
        targets.append(
            Target(
                id=ident.group(1),
                label=label.group(1),
                low=number("low"),
                high=number("high"),
                season=season,
                gate=bool(gate and gate.group(1) == "true"),
                decimals=int(decimals.group(1)) if decimals else 1,
                unit=unit.group(1) if unit else "",
            )
        )
    return targets


# --- one run of the harness -------------------------------------------------


def parse_run(text, targets):
    """The value and verdict of every target row in one printed run, keyed by row id.

    Also the trial counts the run prints, keyed `count:<name>` — the denominators the
    binomial and Poisson models need. Without them the model cannot be evaluated at all,
    which is itself worth recording per row.
    """
    by_key = {}
    for target in targets:
        by_key.setdefault(target.key, []).append(target)

    values, verdicts, printed = {}, {}, {}
    for line in text.splitlines():
        if not line.startswith("  ") or line.startswith("   "):
            continue
        fields = FIELDS.split(line.strip())
        if len(fields) < 6:
            continue
        label, value, _band, verdict, season = fields[0], fields[1], fields[2], fields[3], fields[4]
        if verdict not in VERDICTS:
            continue
        matches = by_key.get((label, season))
        if not matches:
            continue
        # The value field is a plain decimal carrying the row's own unit and nothing else,
        # and the count of digits after the point varies by row AND by run: a row graded
        # outside its band prints the decimals that put it outside (docs/tools.md). So the
        # token is kept as printed — how many digits it carried is the width of the
        # rounding that observation was read through, and that is per observation rather
        # than per row.
        parsed, token = None, None
        if value not in ("—", "-"):
            token = value.rstrip("%x")
            try:
                parsed = float(token)
            except ValueError:
                parsed, token = None, None
        for target in matches:
            values[target.id] = parsed
            printed[target.id] = token
            verdicts[target.id] = verdict

    derived = counts(text, values)
    values.update(derived)
    printed.update({ident: _trim(value) for ident, value in derived.items()})
    return values, verdicts, printed


def counts(text, values):
    """The trial counts a run prints, and the ones a printed row implies.

    A derived count is the row's own arithmetic run backwards — `attempts` is the passing
    yards the run reports divided by its yards per attempt — so it inherits the printed
    value's rounding. That is fine at the precision a model comparison needs: a 1% error
    in a denominator is half a percent in the sigma it predicts.
    """
    found = {}

    header = re.search(r"^simharness — (\d+) games", text, re.M)
    games = float(header.group(1)) if header else None
    if games is None:
        return found
    found["count:games"] = games
    found["count:teamGames"] = 2 * games

    printed = {
        "count:kickoffs": r"kickoffs returned\s+\d+ of (\d+)",
        "count:punts": r"punts returned\s+\d+ of (\d+)",
        "count:onsideKicks": r"onside kicks \(recovered\)\s+(\d+) \(\d+\)",
    }
    for name, pattern in printed.items():
        match = re.search(pattern, text)
        if match:
            found[name] = float(match.group(1))

    # The carry-length histogram prints a count per bucket and every carry is in exactly
    # one bucket, so the total is the sum.
    section = text.split("the length of a carry")
    if len(section) > 1:
        body = section[1].split("three to nine")[0]
        buckets = re.findall(r"^\s+\S.*?\s{2,}(\d+)\s{2,}[\d.]+%\s*(?:#*)?\s*$", body, re.M)
        if buckets:
            found["count:carries"] = float(sum(int(one) for one in buckets))

    # Field goal attempts by distance, printed as a count and a made share.
    goals = re.findall(r"^\s+(\d+)-(\d+) yards\s+(\d+)\s+[\d.]+%\s*$", text, re.M)
    if len(goals) == 4:
        for (low, _high, attempts), name in zip(
            goals, ["under30", "30to39", "40to49", "50plus"]
        ):
            found["count:fieldGoals." + name] = float(attempts)
        found["count:fieldGoals"] = float(sum(int(one[2]) for one in goals))

    def row(name):
        value = values.get(name)
        return value if value is not None else None

    scrimmage = row("playsFromScrimmage")
    if scrimmage is not None:
        found["count:scrimmage"] = scrimmage * 2 * games
    plays = row("playsPerGame")
    if plays is not None:
        found["count:plays"] = plays * games
    drives = row("drivesPerTeamGame")
    if drives is not None:
        found["count:drives"] = drives * 2 * games

    passing, perAttempt = row("passingYards"), row("yardsPerAttempt")
    if passing is not None and perAttempt:
        found["count:attempts"] = passing * 2 * games / perAttempt
        completion = row("completionPercentage")
        if completion is not None:
            found["count:completions"] = found["count:attempts"] * completion / 100.0
        # A dropback is a pass attempt, a sack or a scramble (`PlayKind.isDropback`), and
        # the sack row is the sack share OF dropbacks, so solving for the whole gives
        # dropbacks = (attempts + scrambles) / (1 - sack rate).
        scrambles, sackRate = row("scramblesPerGame"), row("sackRate")
        if scrambles is not None and sackRate is not None and sackRate < 100:
            found["count:dropbacks"] = (found["count:attempts"] + scrambles * games) / (
                1 - sackRate / 100.0
            )

    tries = row("twoPointTries")
    if tries is not None:
        found["count:twoPointTries"] = tries * 2 * games
    goes, wentForIt = row("fourthDownAttempts"), row("fourthDownWentForIt")
    if goes is not None:
        found["count:fourthDownGoes"] = goes * 2 * games
        if wentForIt:
            found["count:fourthDowns"] = goes * 2 * games / (wentForIt / 100.0)
    return found


# --- what model, if any, each row has ---------------------------------------

# ("count", denominator) — a Poisson count over that many units; sigma = sqrt(mean/n).
# ("share", denominator) — a binomial share of that many trials; sigma = 100*sqrt(p(1-p)/n).
# ("none", why)          — no naive model applies, or the harness prints no trial count.
#
# Every denominator names a `count:` key from `counts()` above, so the model is evaluated
# per seed against that run's own trial count rather than against a remembered one.
MODEL = {
    # Counts per game.
    "penaltiesPerGame": ("count", "count:games"),
    "playsPerGame": ("count", "count:games"),
    "tiesPerGame": ("count", "count:games"),
    "onsideKicks": ("count", "count:games"),
    "scramblesPerGame": ("count", "count:games"),
    "kneelsPerGame": ("count", "count:games"),
    "spikesPerGame": ("count", "count:games"),
    "timeoutsPerGame": ("count", "count:games"),
    "interferenceDrawnPerGame": ("count", "count:games"),
    "passesDefensedPerGame": ("count", "count:games"),
    # Counts per team-game.
    "points": ("count", "count:teamGames"),
    "playsFromScrimmage": ("count", "count:teamGames"),
    "firstDownsPerTeamGame": ("count", "count:teamGames"),
    "drivesPerTeamGame": ("count", "count:teamGames"),
    "puntsPerTeamGame": ("count", "count:teamGames"),
    "twoPointTries": ("count", "count:teamGames"),
    "fieldGoalsPerTeamGame": ("count", "count:teamGames"),
    "fourthDownAttempts": ("count", "count:teamGames"),
    "fumblesLost": ("count", "count:teamGames"),
    "fumblesKept": ("count", "count:teamGames"),
    "turnovers": ("count", "count:teamGames"),
    "nonOffensiveTouchdowns": ("count", "count:teamGames"),
    "defensiveReturnTouchdowns": ("count", "count:teamGames"),
    "kickReturnTouchdowns": ("count", "count:teamGames"),
    "snapsInsideOwn10": ("count", "count:teamGames"),
    "safeties": ("count", "count:teamGames"),
    "snaps.quarterback": ("count", "count:teamGames"),
    "snaps.backfield": ("count", "count:teamGames"),
    "snaps.receiver": ("count", "count:teamGames"),
    "snaps.tightEnd": ("count", "count:teamGames"),
    "snaps.offensiveLine": ("count", "count:teamGames"),
    "snaps.frontSeven": ("count", "count:teamGames"),
    "snaps.defensiveBack": ("count", "count:teamGames"),
    # Shares of a trial the run counts.
    "completionPercentage": ("share", "count:attempts"),
    "interceptionRate": ("share", "count:attempts"),
    "sackRate": ("share", "count:dropbacks"),
    "pressureRate": ("share", "count:dropbacks"),
    "dropbackLoss": ("share", "count:dropbacks"),
    "dropbackNoGain": ("share", "count:dropbacks"),
    "dropback10plus": ("share", "count:dropbacks"),
    "dropback20plus": ("share", "count:dropbacks"),
    "dropback40plus": ("share", "count:dropbacks"),
    "completionsZeroOrFewer": ("share", "count:completions"),
    "carriesStuffed": ("share", "count:carries"),
    "carries2orFewer": ("share", "count:carries"),
    "carries10plus": ("share", "count:carries"),
    "carries20plus": ("share", "count:carries"),
    "personnel11": ("share", "count:scrimmage"),
    "packageNickel": ("share", "count:scrimmage"),
    "packageBase": ("share", "count:scrimmage"),
    "driveEndPunt": ("share", "count:drives"),
    "driveEndTouchdown": ("share", "count:drives"),
    "driveEndDowns": ("share", "count:drives"),
    "drives3orFewer": ("share", "count:drives"),
    "drives4to7": ("share", "count:drives"),
    "drives8plus": ("share", "count:drives"),
    "threeAndOut": ("share", "count:drives"),
    "ownHalfStarts": ("share", "count:drives"),
    "kickoffTouchbacks": ("share", "count:kickoffs"),
    "kickoffsReturned": ("share", "count:kickoffs"),
    "puntsReturned": ("share", "count:punts"),
    "onsideRecovery": ("share", "count:onsideKicks"),
    "twoPointConversion": ("share", "count:twoPointTries"),
    "fieldGoalsUnder30": ("share", "count:fieldGoals.under30"),
    "fieldGoals30to39": ("share", "count:fieldGoals.30to39"),
    "fieldGoals40to49": ("share", "count:fieldGoals.40to49"),
    "fieldGoals50plus": ("share", "count:fieldGoals.50plus"),
    "fieldGoalAttemptsUnder30": ("share", "count:fieldGoals"),
    "fieldGoalAttempts30to39": ("share", "count:fieldGoals"),
    "fieldGoalAttempts40to49": ("share", "count:fieldGoals"),
    "fieldGoalAttempts50plus": ("share", "count:fieldGoals"),
    "fourthDownPunted": ("share", "count:fourthDowns"),
    "fourthDownKicked": ("share", "count:fourthDowns"),
    "fourthDownWentForIt": ("share", "count:fourthDowns"),
    "fourthDownConversion": ("share", "count:fourthDownGoes"),
    "gamesWithin3": ("share", "count:games"),
    "gamesWithin7": ("share", "count:games"),
    "gamesBy14plus": ("share", "count:games"),
    "overtimeRate": ("share", "count:games"),
}

NO_MODEL = {
    "yardsPerCarry": "a ratio of two sums, not a share or a count",
    "yardsPerAttempt": "a ratio of two sums, not a share or a count",
    "yardsPerPlay": "a ratio of two sums, not a share or a count",
    "yardsPerCompletion": "a ratio of two sums, not a share or a count",
    "passingYards": "a sum of yards per team-game, not a count of events",
    "rushingYards": "a sum of yards per team-game, not a count of events",
    "thirdDownDistance": "a mean distance, not a share or a count",
    "firstDownGain": "a mean gain, not a share or a count",
    "playsPerDrive": "a ratio of two sums, not a share or a count",
    "netPunt": "a mean over punts, not a share or a count",
    "grossPunt": "a mean over punts, not a share or a count",
    "puntReturnYards": "a mean over returns, not a share or a count",
    "kickoffReturnYards": "a mean over returns, not a share or a count",
    "averageStart": "a mean starting yard line, not a share or a count",
    "overtimeLength": "a mean over overtime games, not a share or a count",
    "ypcEvenCount": "a ratio of two sums, not a share or a count",
    "ypcOutnumberedByOne": "a ratio of two sums, not a share or a count",
    "marginSigma": "a standard deviation; neither model describes one",
    "betweenTeamSigma": "a standard deviation; neither model describes one",
    "winTotalSigma": "a standard deviation; neither model describes one",
    "preSnapRoadVsHome": "a ratio of two rates; neither model describes one",
    "pointsFromTouchdowns": "a share of points, and points are not Bernoulli trials",
    "pointsFromFieldGoals": "a share of points, and points are not Bernoulli trials",
    "playerGamesLost": "a per-team-season projection, not a count over the run",
    "heavyRainPoints": "a difference of two means, not a share or a count",
    "dropsPerTarget": "the harness prints no target count",
    "thirdDownConversion": "the harness prints no third-down count",
    "redZoneTouchdownRate": "the harness prints no red zone drive count",
    "fourthAndOneWentForIt": "the harness prints no fourth-and-one count",
    "extraPointsMade": "the harness prints no extra point count",
    "interferenceOnCompletions": "the harness prints no flag count for the denominator",
}


def model_sigma(target, mean, denominators):
    """The sigma the binomial/Poisson model predicts for this row, or None with a reason."""
    base = target.id.split(".")[0] if target.id.split(".")[-1].isdigit() else target.id
    spec = MODEL.get(base)
    if spec is None:
        return None, NO_MODEL.get(base, "no model has been written for this row")
    kind, key = spec
    n = denominators.get(key)
    if not n or mean is None:
        return None, "the run printed no %s to model against" % key.split(":")[1]
    if kind == "count":
        if mean <= 0:
            return None, "the row is zero over the whole sweep"
        return math.sqrt(mean / n), "Poisson over %s, n=%d" % (key.split(":")[1], round(n))
    share = mean / 100.0
    if share <= 0 or share >= 1:
        return None, "the row is 0%% or 100%% over the whole sweep"
    return 100.0 * math.sqrt(share * (1 - share) / n), "binomial over %s, n=%d" % (
        key.split(":")[1],
        round(n),
    )


# --- statistics -------------------------------------------------------------


def mean(values):
    return sum(values) / len(values)


def stdev(values):
    """Sample standard deviation, about the sample's own mean."""
    if len(values) < 2:
        return 0.0
    middle = mean(values)
    return math.sqrt(sum((one - middle) ** 2 for one in values) / (len(values) - 1))


def _rounding(token):
    """The variance a value cell's own rounding contributes: q^2/12 for its last digit."""
    step = 10.0 ** (-digits(token))
    return step * step / 12.0


def deconvolve(sigma, variance):
    """`sigma` with a known independent variance removed, floored at zero.

    Reading a rounded column adds a uniform error of width q, variance q^2/12. Removing
    it is Sheppard's correction; a row whose whole spread is that error corrects to zero,
    which is the honest answer — its floor is below what the printed column can resolve.
    """
    return math.sqrt(max(0.0, sigma * sigma - variance))


# --- the sweep --------------------------------------------------------------


def run_harness(binary, games, seed):
    result = subprocess.run(
        [binary, "--games", str(games), "--seed", str(seed), "--no-timing"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


def sweep(binary, seeds, out, note="", resume=False):
    """Run every seed at both game counts and write the table.

    `resume` merges into an existing sweep instead of replacing it, so a long sweep can be
    taken in chunks that each fit inside a foreground call. Every chunk records its own
    `# run` line: the values cannot drift between chunks — the harness is byte-identical
    between two runs of one binary at one seed, which CI asserts on every push — but when
    a sweep was taken is a fact about the measurement and belongs in the file.
    """
    targets = parse_targets(open(TARGETS, encoding="utf-8").read())
    seen = {}
    for target in targets:
        if target.key in seen:
            raise SystemExit(
                "two rows print as the same label and season — %s and %s. The sweep keys "
                "a printed row by that pair; give one of them a distinct label or teach "
                "parse_run another field." % (seen[target.key], target.id)
            )
        seen[target.key] = target.id

    table, runs, known = {}, [], []
    if resume and os.path.exists(out):
        header, known, table = read_sweep(out)
        runs = [one for one in header if one.startswith("# run ")]

    already = {
        (games, seed)
        for (_ident, games, field), row in table.items()
        if field == "value"
        for seed in row
    }

    started = time.time()
    ran = []
    for games in GAME_COUNTS:
        for seed in seeds:
            if (games, seed) in already:
                continue
            ran.append((games, seed))
            text = run_harness(binary, games, seed)
            _values, verdicts, printed = parse_run(text, targets)
            for ident, token in printed.items():
                if token is not None:
                    table.setdefault((ident, games, "value"), {})[seed] = token
            for ident, verdict in verdicts.items():
                table.setdefault((ident, games, "verdict"), {})[seed] = verdict
            print(
                "  %d games, seed %-4d %d rows" % (games, seed, len(verdicts)),
                file=sys.stderr,
            )
    finished = time.time()
    if ran:
        runs.append(
            "# run               seeds %s at %s games, %s, %.0f s, back to back"
            % (
                _spans({seed for _games, seed in ran}),
                " and ".join(
                    str(one) for one in sorted({games for games, _seed in ran}, reverse=True)
                ),
                time.strftime("%Y-%m-%dT%H:%MZ", time.gmtime(started)),
                finished - started,
            )
        )

    columns = sorted(set(known) | set(seeds))
    head = subprocess.run(
        ["git", "-C", ROOT, "rev-parse", "HEAD"], capture_output=True, text=True
    ).stdout.strip()
    # Which files the sweep was taken with that the named commit does not have. The sweep
    # file itself is left out: it is the thing being written, and naming it here would say
    # nothing about the tree the harness was built from.
    written = os.path.relpath(os.path.abspath(out), ROOT)
    dirty = [
        line[3:]
        for line in subprocess.run(
            ["git", "-C", ROOT, "status", "--porcelain"], capture_output=True, text=True
        ).stdout.splitlines()
        if line.strip() and line[3:] != written
    ]

    with open(out, "w", encoding="utf-8") as handle:
        handle.write(
            "# simharness noise sweep — every graded row at %d seeds, one unchanged tree.\n"
            "# Written by scripts/harness-noise.py --sweep; read by --report. Do not hand-edit.\n"
            "#\n"
            "# tree              %s\n"
            "# working tree      %s\n"
            "# seeds             %s\n"
            "# games             %s — the shorter runs are the FIRST n games of the longest,\n"
            "#                   same world, same games, same draws\n"
            "# machine           %s, %s cores, %s\n"
            "%s"
            "#\n"
            "%s"
            "#\n"
            "# One line per row per game count: `value` is what the column printed, `verdict`\n"
            "# is the mark beside it. A `count:` row is a trial count the run printed or a\n"
            "# printed row implies, kept so the binomial and Poisson models can be recomputed\n"
            "# without re-running the sweep.\n"
            % (
                len(columns),
                head or "unknown",
                "clean"
                if not dirty
                else "%d file(s) differ from that commit: %s"
                % (len(dirty), ", ".join(sorted(dirty))),
                _spans(columns),
                ", ".join(str(one) for one in GAME_COUNTS),
                platform.machine(),
                os.cpu_count(),
                _cpu_name(),
                ("# note              %s\n" % note) if note else "",
                "\n".join(runs) + "\n",
            )
        )
        handle.write("id\tgames\tfield\t" + "\t".join("s%d" % one for one in columns) + "\n")
        for (ident, games, field) in sorted(table):
            row = table[(ident, games, field)]
            cells = [row.get(seed) or "—" for seed in columns]
            handle.write("%s\t%d\t%s\t%s\n" % (ident, games, field, "\t".join(cells)))
    print("wrote %s (%d seeds)" % (out, len(columns)), file=sys.stderr)


def _spans(seeds):
    """`1-30` for a run of consecutive seeds, `1-4, 9` when there is a gap."""
    spans, start, last = [], None, None
    for seed in sorted(seeds):
        if start is None:
            start = last = seed
        elif seed == last + 1:
            last = seed
        else:
            spans.append((start, last))
            start = last = seed
    if start is not None:
        spans.append((start, last))
    return ", ".join(
        str(low) if low == high else "%d-%d" % (low, high) for low, high in spans
    )


def _trim(value):
    text = "%.6f" % value
    text = text.rstrip("0").rstrip(".")
    return text or "0"


def _cpu_name():
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as handle:
            for line in handle:
                if line.startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or "unknown"


def read_sweep(path):
    """The header lines and the table `--sweep` wrote."""
    header, table, seeds = [], {}, []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if line.startswith("#"):
                header.append(line)
                continue
            cells = line.split("\t")
            if cells[0] == "id":
                seeds = [int(one[1:]) for one in cells[3:]]
                continue
            ident, games, field = cells[0], int(cells[1]), cells[2]
            row = {}
            for seed, cell in zip(seeds, cells[3:]):
                if cell == "—":
                    continue
                row[seed] = cell
            table[(ident, games, field)] = row
    return header, seeds, table


def as_number(token):
    """A value cell as a number."""
    return float(token)


def digits(token):
    """How many digits the value cell carried after the point.

    This is the observation's own rounding width, not the row's: the harness widens a
    row's precision in the run where the printed value would otherwise contradict its
    verdict, so two seeds of one row can be read through different roundings.
    """
    return len(token.split(".")[1]) if "." in token else 0


# --- the report -------------------------------------------------------------


class Floor:
    """One row's measured noise floor."""

    def __init__(self, target, values, prefixes, verdicts, denominators):
        self.target = target
        self.seeds = sorted(values)
        self.values = [as_number(values[one]) for one in self.seeds]
        self.mean = mean(self.values) if self.values else None
        self.low = min(self.values) if self.values else None
        self.high = max(self.values) if self.values else None
        self.total = stdev(self.values)

        # The rounding each reading was made through, averaged as a variance because that
        # is how it adds. A row printed at one precision everywhere gives the plain
        # q^2/12; a row the harness widened at some seeds gives less, which is the point
        # of the widening.
        rounding = mean([_rounding(values[one]) for one in self.seeds]) if self.seeds else 0.0
        self.total_true = deconvolve(self.total, rounding)
        # A sigma whose square is mostly the rounding it had to be corrected for is not a
        # measurement of the row; it is a measurement of the printed column's last digit.
        self.total_resolved = self.total**2 > 2 * rounding

        # The within-world floor, once per prefix length. A shorter prefix is a longer
        # lever arm on the same quantity, and the estimates have to agree.
        self.within_at, self.drift_at, self.resolved_at = {}, {}, {}
        for games, run in sorted(prefixes.items()):
            shared = [one for one in self.seeds if one in run]
            paired = [as_number(run[one]) - as_number(values[one]) for one in shared]
            if len(paired) < 2 or games >= FULL_GAMES:
                continue
            # Var(v_g - v_G) = c/g - c/G for a mean over independent games, so the
            # spread of the difference scales by sqrt(G/g - 1) and dividing it out
            # leaves sigma_within(G) whichever prefix it came from.
            lever = math.sqrt(FULL_GAMES / float(games) - 1.0)
            raw = stdev(paired) / lever
            # A difference is read through both readings' roundings.
            noise = (
                mean([_rounding(run[one]) + _rounding(values[one]) for one in shared])
                / (lever * lever)
            )
            self.within_at[games] = deconvolve(raw, noise)
            self.drift_at[games] = mean(paired)
            self.resolved_at[games] = raw**2 > 2 * noise

        self.within_true = self.within_at.get(HALF_GAMES)
        self.within_resolved = self.resolved_at.get(HALF_GAMES, False)
        if self.within_true is None:
            self.world = None
        else:
            self.world = deconvolve(self.total_true, self.within_true**2)

        self.verdicts = sorted({verdicts[one] for one in self.seeds if one in verdicts})
        self.model, self.model_note = model_sigma(target, self.mean, denominators)

    @property
    def lever_agreement(self):
        """The two lever arms' estimates of the same floor, as a ratio, or None.

        Both are estimates of sigma_within(400). If they disagree, the 1/games law they
        share does not hold for this row and neither number should be believed.
        """
        short, long = self.within_at.get(QUARTER_GAMES), self.within_at.get(HALF_GAMES)
        if not short or not long:
            return None
        return short / long

    @property
    def edge_margin(self):
        """Distance from the mean to the nearer band edge, in whole floors.

        `None` for a row with no band. Under one is a row whose ordinary spread reaches
        its own edge, which is a verdict that will flip on changes that did nothing.
        """
        edges = [one for one in (self.target.low, self.target.high) if one is not None]
        if not edges or self.mean is None or self.total <= 0:
            return None
        return min(abs(self.mean - one) for one in edges) / self.total

    @property
    def flips(self):
        """Whether the printed verdict is not the same at every seed."""
        return len({one for one in self.verdicts if one in ("ok", "OFF", "(ok)", "(OFF)")}) > 1

    @property
    def within_ratio(self):
        """Measured within-world sigma over the model's.

        This is the comparison the model was ever meant to make: a before-and-after at one
        seed plays the SAME league, so the only thing that moves is the run's own draw.
        """
        if not self.model or self.within_true is None or self.within_true <= 0:
            return None
        return self.within_true / self.model

    @property
    def total_ratio(self):
        """Measured seed-to-seed sigma over the model's.

        This is the comparison the model is often USED for — two seeds, or a change that
        moves the generated world — and the model has no term for the league at all.
        """
        if not self.model or self.total_true <= 0:
            return None
        return self.total_true / self.model

    def games_for(self, wanted):
        """Games needed for the within-world floor to reach `wanted`, or why none will.

        The world component does not shrink with games at all — a longer run plays more
        games in the SAME league — so a row whose world component already exceeds the
        requirement cannot be fixed by `--games` at any value.
        """
        if self.within_true is None or self.world is None or wanted <= 0:
            return None
        if self.world > wanted:
            return "more seeds"
        if self.within_true <= wanted:
            return FULL_GAMES
        return int(math.ceil(FULL_GAMES * (self.within_true / wanted) ** 2))


def analyse(path):
    targets = parse_targets(open(TARGETS, encoding="utf-8").read())
    header, seeds, table = read_sweep(path)
    denominators = {}
    for (ident, games, field), row in table.items():
        if ident.startswith("count:") and games == FULL_GAMES and field == "value" and row:
            denominators[ident] = mean([as_number(one) for one in row.values()])

    floors = []
    for target in targets:
        values = table.get((target.id, FULL_GAMES, "value"), {})
        verdicts = table.get((target.id, FULL_GAMES, "verdict"), {})
        prefixes = {
            games: table.get((target.id, games, "value"), {})
            for games in GAME_COUNTS
            if games < FULL_GAMES
        }
        if not values:
            continue
        floors.append(Floor(target, values, prefixes, verdicts, denominators))
    return header, seeds, floors


def number(value, decimals=2):
    if value is None:
        return "—"
    return ("%%.%df" % decimals) % value


def report(path):
    """The per-row table, as markdown, for `docs/reference/calibration-sources.md`."""
    _header, _seeds, floors = analyse(path)
    print(
        "| row | mean | min–max | σ seed-to-seed | σ same league | σ league | model σ | "
        "same league / model | seed-to-seed / model | edge margin | verdicts seen |"
    )
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |")
    for floor in floors:
        target = floor.target
        decimals = max(2, target.decimals + 1)

        def sigma(value, resolved=True):
            if value is None:
                return "—"
            text = number(value, decimals)
            return text if resolved else text + " †"

        margin = floor.edge_margin
        print(
            "| `row:%s` | %s | %s–%s | %s | %s | %s | %s | %s | %s | %s | %s |"
            % (
                target.id,
                number(floor.mean, decimals),
                number(floor.low, decimals),
                number(floor.high, decimals),
                sigma(floor.total_true, floor.total_resolved),
                sigma(floor.within_true, floor.within_resolved),
                sigma(floor.world),
                number(floor.model, decimals) if floor.model else "—",
                "—" if floor.within_ratio is None else number(floor.within_ratio, 2) + "x",
                "—" if floor.total_ratio is None else number(floor.total_ratio, 2) + "x",
                "—" if margin is None else number(margin, 1),
                " ".join(floor.verdicts),
            )
        )


def summary(path):
    """The findings the table is read for, printed rather than eyeballed."""
    _header, seeds, floors = analyse(path)
    print("seeds: %d     rows measured: %d" % (len(seeds), len(floors)))

    flipped = [one for one in floors if one.flips]
    print("\nrows whose printed verdict is not the same at every seed (%d):" % len(flipped))
    for floor in flipped:
        print(
            "  %-34s %s   mean %s, range %s–%s, band %s–%s"
            % (
                floor.target.id,
                "/".join(floor.verdicts),
                number(floor.mean),
                number(floor.low),
                number(floor.high),
                number(floor.target.low),
                number(floor.target.high),
            )
        )

    close = [
        one
        for one in floors
        if one.edge_margin is not None and one.edge_margin < 1.0 and not one.flips
    ]
    print("\nrows within one floor of their own band edge but not seen to flip (%d):" % len(close))
    for floor in sorted(close, key=lambda one: one.edge_margin):
        print(
            "  %-34s margin %.2f floors   mean %s, σ %s, band %s–%s"
            % (
                floor.target.id,
                floor.edge_margin,
                number(floor.mean),
                number(floor.total_true),
                number(floor.target.low),
                number(floor.target.high),
            )
        )

    modelled = [one for one in floors if one.within_ratio is not None and one.within_resolved]
    print(
        "\nthe model against the SAME-LEAGUE floor — a before-and-after at one seed (%d rows):"
        % len(modelled)
    )
    _spread_of_ratios([one.within_ratio for one in modelled])
    for floor in sorted(modelled, key=lambda one: -one.within_ratio):
        if floor.within_ratio < 1.4 and floor.within_ratio > 1 / 1.4:
            continue
        print(
            "  %-34s measured %s vs model %s  (%.2fx, %s)"
            % (
                floor.target.id,
                number(floor.within_true, 3),
                number(floor.model, 3),
                floor.within_ratio,
                floor.model_note,
            )
        )

    crossing = [one for one in floors if one.total_ratio is not None and one.total_resolved]
    print(
        "\nthe model against the SEED-TO-SEED floor — two seeds, or a changed world (%d rows):"
        % len(crossing)
    )
    _spread_of_ratios([one.total_ratio for one in crossing])
    for floor in sorted(crossing, key=lambda one: -one.total_ratio)[:12]:
        print(
            "  %-34s measured %s vs model %s  (%.2fx)"
            % (floor.target.id, number(floor.total_true, 3), number(floor.model, 3), floor.total_ratio)
        )

    levers = [one for one in floors if one.lever_agreement and one.within_resolved]
    off = [one for one in levers if one.lever_agreement > 1.4 or one.lever_agreement < 1 / 1.4]
    print(
        "\nthe estimator against itself — the %d-game prefix's answer over the %d-game "
        "prefix's (%d rows):" % (QUARTER_GAMES, HALF_GAMES, len(levers))
    )
    _spread_of_ratios([one.lever_agreement for one in levers])
    print("  rows where the two lever arms disagree by more than 1.4x: %d" % len(off))
    for floor in sorted(off, key=lambda one: -one.lever_agreement):
        print("  %-34s %.2fx" % (floor.target.id, floor.lever_agreement))

    dominated = [
        one
        for one in floors
        if one.world is not None and one.within_true is not None and one.world > 2 * one.within_true
    ]
    print("\nrows whose spread is mostly the league rather than the games (%d):" % len(dominated))
    for floor in sorted(dominated, key=lambda one: -(one.world / max(one.within_true, 1e-9))):
        print(
            "  %-34s league %s vs same-league %s  (%.1fx)"
            % (
                floor.target.id,
                number(floor.world, 3),
                number(floor.within_true, 3),
                floor.world / max(floor.within_true, 1e-9),
            )
        )

    unseparated = [
        one
        for one in floors
        if one.within_true is not None and one.within_true > one.total_true
    ]
    print(
        "\nrows where the two components cannot be told apart at %d seeds — the same-league "
        "floor came out at or above the seed-to-seed one, so the league's share is not "
        "distinguishable from zero (%d):" % (len(seeds), len(unseparated))
    )
    for floor in unseparated:
        print(
            "  %-34s same-league %s vs seed-to-seed %s"
            % (floor.target.id, number(floor.within_true, 3), number(floor.total_true, 3))
        )

    print(
        "\nwhat --games a row needs for its band to be four floors wide, which is what it "
        "takes for a seed to land inside it reliably:"
    )
    for floor in floors:
        target = floor.target
        if target.low is None or target.high is None:
            continue
        wanted = (target.high - target.low) / 4.0
        answer = floor.games_for(wanted)
        if answer is None or answer == FULL_GAMES:
            continue
        print(
            "  %-34s %s   (band %s–%s, same-league σ %s, league σ %s)"
            % (
                target.id,
                "%d games" % answer if isinstance(answer, int) else answer,
                number(target.low),
                number(target.high),
                number(floor.within_true, 3),
                number(floor.world, 3),
            )
        )

    narrow = []
    for floor in floors:
        target = floor.target
        if target.low is None or target.high is None or floor.total_true <= 0:
            continue
        width = (target.high - target.low) / floor.total_true
        if width < 4.0:
            narrow.append((width, floor))
    print(
        "\nrows whose whole band is narrower than the four floors a run needs to sit "
        "inside it — a seed can land outside with the engine exactly on target (%d):"
        % len(narrow)
    )
    for width, floor in sorted(narrow):
        print(
            "  %-34s band %s–%s is %.1f floors wide (σ %s)"
            % (
                floor.target.id,
                number(floor.target.low),
                number(floor.target.high),
                width,
                number(floor.total_true, 3),
            )
        )

    unresolved = [one for one in floors if not one.total_resolved]
    print(
        "\nrows whose spread is at or below what the printed column resolves — read the "
        "floor as an upper bound (%d):" % len(unresolved)
    )
    for floor in unresolved:
        print(
            "  %-34s prints to %s, σ %s"
            % (floor.target.id, number(floor.target.step, 3), number(floor.total, 3))
        )


def replicate(path, other):
    """The published floor against the same measurement on a disjoint set of seeds.

    A sigma from n seeds is itself an estimate with about 1/sqrt(2(n-1)) relative error —
    13% at 30 seeds — so two independent sweeps should agree to roughly that, and a row
    where they do not is a row whose floor is not a property of the row.
    """
    _header, seeds, here = analyse(path)
    _other_header, other_seeds, there = analyse(other)
    print(
        "published floor: seeds %s     replication: seeds %s"
        % (_spans(seeds), _spans(other_seeds))
    )
    by_id = {one.target.id: one for one in there}

    for name, pick in (
        ("seed-to-seed σ", lambda one: one.total_true if one.total_resolved else None),
        ("same-league σ", lambda one: one.within_true if one.within_resolved else None),
    ):
        ratios, worst = [], []
        for floor in here:
            twin = by_id.get(floor.target.id)
            if twin is None:
                continue
            mine, theirs = pick(floor), pick(twin)
            if not mine or not theirs:
                continue
            ratios.append(theirs / mine)
            worst.append((theirs / mine, floor.target.id, mine, theirs))
        print("\n%s, replication over published (%d rows):" % (name, len(ratios)))
        _spread_of_ratios(ratios)
        worst.sort(key=lambda one: -abs(math.log(one[0])) if one[0] > 0 else 0)
        for ratio, ident, mine, theirs in worst[:8]:
            print("  %-34s %.2fx   %s vs %s" % (ident, ratio, number(mine, 3), number(theirs, 3)))


def _spread_of_ratios(ratios):
    if not ratios:
        print("  (none)")
        return
    ordered = sorted(ratios)
    middle = ordered[len(ordered) // 2]
    over = len([one for one in ratios if one >= 2 or one <= 0.5])
    print(
        "  median %.2fx, range %.2f–%.2fx, %d of %d outside a factor of two"
        % (middle, ordered[0], ordered[-1], over, len(ratios))
    )


# --- the self-test ----------------------------------------------------------

FIXTURE_TARGETS = """
        CalibrationTarget(
            id: "points", label: "points", low: 20.6, high: 24.1, season: .seasons(2023...2024),
            source: playByPlay, rulesSensitiveTo: [], gate: true),
        CalibrationTarget(
            id: "safeties", label: "safeties per team-game", low: 0.01, high: 0.05,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: true,
            decimals: 2),
        CalibrationTarget(
            id: "kickoffTouchbacks.2025", label: "kickoff touchbacks", low: 18.9, high: 22.4,
            season: .season(2025), source: playByPlay, rulesSensitiveTo: [.kickoff], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "kickoffTouchbacks.2024", label: "kickoff touchbacks", low: 61.1, high: 67.6,
            season: .season(2024), source: playByPlay, rulesSensitiveTo: [.kickoff], gate: true,
            unit: "%"),
        CalibrationTarget(
            id: "winTotalSigma", label: "spread of team win totals (σ)", low: 2.5, high: 3.8,
            season: .seasons(2023...2024), source: playByPlay, rulesSensitiveTo: [], gate: false),
        CalibrationTarget(
            id: "dropsPerTarget", label: "drops per target", low: nil, high: nil,
            season: .unsourced, source: "", rulesSensitiveTo: [], gate: false, unit: "%"),
"""

# A run whose shape carries every case the parser has to survive: a plain row, a row
# printing MORE digits than its band's precision (what #108 makes the harness do near an
# edge), the two variants of one label told apart only by their season, a row with no
# value, a line that looks tabular but is not a target row, and the trial counts.
FIXTURE_RUN = """simharness — 400 games, seed 7
  32 teams, strength offset -2.8 to 2.5
  world checksum 23d435eb36f88a39  (no target: it names the league, it does not grade it)

  metric (per team per game)            value    target        verdict    season   src  sensitive to
  points                                25.34    20.6-24.1     OFF        2023-24  S1
  safeties per team-game                0.03     0.01-0.05     ok         2023-24  S1
  kickoff touchbacks                    19.1%    18.9-22.4     ok         2025     S1   kickoff
  kickoff touchbacks                    19.1%    61.1-67.6     stale      2024     S1   kickoff
  spread of team win totals (σ)         —        2.5-3.8       n/a        2023-24  S1
  drops per target                      12.8%    none          unsourced  -        -
    sacks taken inside own 10 31 in 800 team-games   (no target: not in the source)
    kickoffs returned             3404 of 4397
    punts returned                1407 of 3122
    onside kicks (recovered)      77 (9)
      0-29 yards                  365    96.7%
      30-39 yards                 413    93.0%
      40-49 yards                 446    82.1%
      50-70 yards                 163    73.6%
    the length of a carry
      -3 or worse   203     0.8%    #
      0             2992    12.1%   #############################
      20 or more    600     2.4%    #####
      three to nine         44.7%   derived floor 42.3, ceiling 49.8
"""


def self_test():
    failures = []

    def check(name, got, want):
        if got != want:
            failures.append("%s: got %r, wanted %r" % (name, got, want))

    def close(name, got, want, tolerance):
        if got is None or abs(got - want) > tolerance:
            failures.append("%s: got %r, wanted %r ± %r" % (name, got, want, tolerance))

    targets = parse_targets(FIXTURE_TARGETS)
    check("targets parsed", len(targets), 6)
    by_id = {one.id: one for one in targets}
    check("band low", by_id["points"].low, 20.6)
    check("band high", by_id["points"].high, 24.1)
    check("season range printed", by_id["points"].season, "2023-24")
    check("season single printed", by_id["kickoffTouchbacks.2025"].season, "2025")
    check("season unsourced printed", by_id["dropsPerTarget"].season, "-")
    check("nil band", by_id["dropsPerTarget"].low, None)
    check("default decimals", by_id["points"].decimals, 1)
    check("declared decimals", by_id["safeties"].decimals, 2)
    check("step", by_id["safeties"].step, 0.01)
    check("gate true", by_id["points"].gate, True)
    check("gate false", by_id["winTotalSigma"].gate, False)

    values, verdicts, printed = parse_run(FIXTURE_RUN, targets)
    # The point of the fixture: two decimals where the band prints one, parsed as written.
    close("extra digits parsed", values["points"], 25.34, 1e-9)
    check("extra digits kept as printed", printed["points"], "25.34")
    check("digits counted from the token", digits(printed["points"]), 2)
    check("digits of a whole number", digits("167"), 0)
    close("rounding of a two-decimal reading", _rounding("25.34"), 0.01**2 / 12, 1e-12)
    check("unit stripped", values["kickoffTouchbacks.2025"], 19.1)
    check("unit stripped from the token too", printed["kickoffTouchbacks.2025"], "19.1")
    check("same label, other season", values["kickoffTouchbacks.2024"], 19.1)
    check("stale verdict kept", verdicts["kickoffTouchbacks.2024"], "stale")
    check("no value", values["winTotalSigma"], None)
    check("no token for a row with no value", printed["winTotalSigma"], None)
    check("unsourced row still read", values["dropsPerTarget"], 12.8)
    check("printed kickoffs", values["count:kickoffs"], 4397.0)
    check("printed punts", values["count:punts"], 3122.0)
    check("printed onside kicks", values["count:onsideKicks"], 77.0)
    check("carry histogram summed", values["count:carries"], 203.0 + 2992.0 + 600.0)
    check("field goal attempts summed", values["count:fieldGoals"], 365.0 + 413 + 446 + 163)
    check("field goal bucket", values["count:fieldGoals.40to49"], 446.0)
    check("team games", values["count:teamGames"], 800.0)
    # A tabular-looking line that is not a target row must not become one.
    check("non-row ignored", "sacks taken inside own 10" in values, False)

    check("spans, contiguous", _spans([1, 2, 3, 4]), "1-4")
    check("spans, with a gap", _spans([9, 1, 2, 3, 4]), "1-4, 9")
    check("spans, one seed", _spans([7]), "7")

    # The TSV round trip, which is what makes a chunked sweep one file rather than two.
    import tempfile

    with tempfile.TemporaryDirectory() as scratch:
        path = os.path.join(scratch, "sweep.tsv")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("# tree              abc123\n")
            handle.write("# run               seeds 1-2 at 400 and 200 games\n")
            handle.write("id\tgames\tfield\ts1\ts2\n")
            handle.write("points\t400\tvalue\t25.1\t—\n")
            handle.write("points\t400\tverdict\tOFF\tOFF\n")
        header, seeds, table = read_sweep(path)
        check("round trip seeds", seeds, [1, 2])
        # Kept as the token, not a float: how many digits it carried is the measurement's
        # own rounding width and it would be lost the moment it became a number.
        check("round trip values", table[("points", 400, "value")], {1: "25.1"})
        check("round trip verdicts", table[("points", 400, "verdict")], {1: "OFF", 2: "OFF"})
        check("round trip keeps the run lines", len([one for one in header if one.startswith("# run ")]), 1)

    check("stdev of one value", stdev([1.0]), 0.0)
    close("stdev known answer", stdev([2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]), 2.13809, 1e-4)
    close("deconvolve removes variance", deconvolve(0.5, 0.09), 0.4, 1e-9)
    check("deconvolve floors at zero", deconvolve(0.1, 1.0), 0.0)

    # The within-world estimator on a synthetic sweep whose two components are known.
    # Each seed is a world offset plus two independent half-run errors; the estimator has
    # to recover the half-run scale and leave the world offset out of it.
    import random

    generator = random.Random(20260911)
    world_sigma, quarter_sigma = 1.0, 0.25 * math.sqrt(2.0)
    fulls, halves, quarters = {}, {}, {}
    for seed in range(1, 4001):
        world = generator.gauss(0.0, world_sigma)
        parts = [generator.gauss(0.0, quarter_sigma) for _ in range(4)]
        # As tokens, the way the sweep stores them, at a precision fine enough that the
        # rounding correction has nothing to do here.
        quarters[seed] = "%.6f" % (world + parts[0])
        halves[seed] = "%.6f" % (world + (parts[0] + parts[1]) / 2.0)
        fulls[seed] = "%.6f" % (world + sum(parts) / 4.0)
    half_sigma = quarter_sigma / math.sqrt(2.0)
    target = Target("synthetic", "synthetic", None, None, "-", False, 6, "")
    floor = Floor(
        target, fulls, {HALF_GAMES: halves, QUARTER_GAMES: quarters}, {}, {}
    )
    # A 400-game run averages two half-run errors, so its own sampling sigma is the
    # half-run's over root two — and that is exactly what the spread of D recovers.
    within = half_sigma / math.sqrt(2.0)
    close("within-world sigma recovered", floor.within_true, within, 0.01)
    close(
        "total sigma recovered",
        floor.total_true,
        math.sqrt(world_sigma**2 + within**2),
        0.05,
    )
    # The shorter prefix is a longer lever arm on the same quantity; dividing the lever out
    # has to leave the same answer, and the check that it does is what says the estimator
    # is not quietly reading something else.
    close("the shorter lever arm agrees", floor.lever_agreement, 1.0, 0.05)
    close("the shorter lever arm's own estimate", floor.within_at[QUARTER_GAMES], within, 0.01)
    close("world sigma recovered", floor.world, world_sigma, 0.05)

    # A verdict that is not the same at every seed is what "permanently unstable" means.
    flipping = Target("flipping", "flipping", 10.0, 20.0, "-", True, 1, "")
    floor = Floor(
        flipping,
        {1: "19.5", 2: "20.5", 3: "19.9"},
        {HALF_GAMES: {}},
        {1: "ok", 2: "OFF", 3: "ok"},
        {},
    )
    check("flip detected", floor.flips, True)
    check("verdicts listed", floor.verdicts, ["OFF", "ok"])
    steady = Floor(flipping, {1: "15.0", 2: "15.2"}, {HALF_GAMES: {}}, {1: "ok", 2: "ok"}, {})
    check("no flip", steady.flips, False)

    # The models, against hand arithmetic.
    counted = Target("points", "points", None, None, "-", True, 1, "")
    sigma, note = model_sigma(counted, 25.0, {"count:teamGames": 800.0})
    close("Poisson sigma", sigma, math.sqrt(25.0 / 800.0), 1e-9)
    check("Poisson note", note, "Poisson over teamGames, n=800")
    shared = Target("completionPercentage", "x", None, None, "-", True, 1, "")
    sigma, note = model_sigma(shared, 64.0, {"count:attempts": 25000.0})
    close("binomial sigma", sigma, 100 * math.sqrt(0.64 * 0.36 / 25000.0), 1e-9)
    sigma, why = model_sigma(Target("marginSigma", "x", None, None, "-", True, 1, ""), 14.0, {})
    check("no model for a standard deviation", sigma, None)
    check("no model says why", why, "a standard deviation; neither model describes one")
    sigma, why = model_sigma(counted, 25.0, {})
    check("missing denominator is not a model", sigma, None)
    # A rule-sensitive row carries its rulebook after a dot and models like its base row.
    sigma, _note = model_sigma(
        Target("kickoffTouchbacks.2025", "x", None, None, "2025", True, 1, "%"),
        20.0,
        {"count:kickoffs": 4400.0},
    )
    close("variant row models as its base", sigma, 100 * math.sqrt(0.2 * 0.8 / 4400.0), 1e-9)

    # The games recommendation, including the case no number of games can fix.
    reachable = Floor(
        Target("reachable", "reachable", None, None, "-", True, 6, ""),
        {seed: "0.000000" for seed in range(1, 31)},
        {HALF_GAMES: {seed: "0.000000" for seed in range(1, 31)}},
        {},
        {},
    )
    reachable.within_true, reachable.world = 0.4, 0.01
    check("already there", reachable.games_for(0.5), FULL_GAMES)
    check("four times the games halves the floor", reachable.games_for(0.2), 1600)
    reachable.world = 0.9
    check("the world is the floor", reachable.games_for(0.5), "more seeds")

    for failure in failures:
        print("  FAIL  %s" % failure)
    if failures:
        print("harness-noise: SELF-TEST FAILED — %d case(s)." % len(failures))
        return 1
    print("harness-noise: self-test clean.")
    return 0


# --- entry point ------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="measure how far each calibration row moves when nothing changes"
    )
    parser.add_argument("--sweep", action="store_true", help="run the sweep and write the TSV")
    parser.add_argument("--report", action="store_true", help="print the markdown table")
    parser.add_argument("--summary", action="store_true", help="print the findings")
    parser.add_argument(
        "--replicate",
        default="",
        metavar="OTHER.TSV",
        help="compare the floors in --out against a second sweep on other seeds",
    )
    parser.add_argument("--self-test", action="store_true", dest="self_test")
    parser.add_argument("--seeds", default="1-30", help="seeds to sweep, e.g. 1-30 or 1,2,3")
    parser.add_argument("--binary", default=HARNESS, help="the release simharness to run")
    parser.add_argument("--out", default=SWEEP, help="where --sweep writes and --report reads")
    parser.add_argument("--note", default="", help="a line recorded in the sweep's header")
    parser.add_argument(
        "--resume",
        action="store_true",
        help="merge into an existing sweep rather than replacing it, so a long sweep can "
        "be taken in chunks",
    )
    arguments = parser.parse_args()

    if arguments.self_test:
        return self_test()
    if arguments.sweep:
        if "-" in arguments.seeds:
            low, high = arguments.seeds.split("-")
            seeds = list(range(int(low), int(high) + 1))
        else:
            seeds = [int(one) for one in arguments.seeds.split(",")]
        if not os.path.exists(arguments.binary):
            raise SystemExit(
                "no harness at %s — build it first:\n"
                "  swift build -c release --package-path Tools/simharness" % arguments.binary
            )
        sweep(arguments.binary, seeds, arguments.out, arguments.note, arguments.resume)
        return 0
    if arguments.report:
        report(arguments.out)
        return 0
    if arguments.replicate:
        replicate(arguments.out, arguments.replicate)
        return 0
    if arguments.summary:
        summary(arguments.out)
        return 0
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
