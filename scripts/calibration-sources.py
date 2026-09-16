#!/usr/bin/env python3
"""Derive the calibration bands in Tools/simharness/Sources/simharness/Targets.swift.

Every band in the harness names a real-league season and a source. This script is the
derivation: it reads the nflverse play-by-play data set (built from the league's official
play-by-play feed; participation data from Next Gen Stats via the same project) and prints,
for every target row, the value in each season, the sampling noise of a 400-game harness
run, and the band that follows from the policy below. Nothing in the harness is typed from
memory; if a number in `Targets.swift` cannot be reproduced by this script, the script wins.

Usage:

    scripts/calibration-sources.py <dir with play_by_play_<season>.csv.gz and
                                    pbp_participation_<season>.csv>
    scripts/calibration-sources.py --rosters <dir with roster_weekly_<season>.csv>
    scripts/calibration-sources.py --self-test   # the accumulator's own test; needs no data

Input files are the release assets `pbp/play_by_play_<season>.csv.gz` and
`pbp_participation/pbp_participation_<season>.csv` of the nflverse-data project. They are
not checked in (about 20 MB per season compressed). `--rosters` reads
`weekly_rosters/roster_weekly_<season>.csv` from the same project and derives what a roster
is made of rather than what a game does — a band the harness cannot measure, and so one that
lives in a test rather than in `Targets.swift`.

Band policy, in one place:

- A row's band spans the values of the seasons it is sourced from, widened on each side by
  the larger of 5% of the mean and twice the standard error of the statistic in a 400-game
  run. The standard error is measured by resampling whole games from the sourced season, so
  rare-event rows (ties, return touchdowns) get the width their rarity demands.
- Regular-season games only. Postseason overtime and the extra week distort per-game rates.
- Per-play and per-drive rates are sourced from 2023 and 2024. A row that depends on a rule
  the 2025 rulebook changed (kickoff, onside kick, overtime) is sourced from 2025 alone, and
  the 2024 value is kept as a separate row so the harness can run under 2024 rules against
  2024 bands.
- A statistic that is not a ratio of per-game sums (the spread of win totals) takes the 5%
  margin only.
"""

import csv
import gzip
import math
import os
import random
import statistics
import sys
from collections import Counter, defaultdict

csv.field_size_limit(1 << 30)

SEASONS = [2022, 2023, 2024, 2025]
PARTICIPATION_SEASONS = [2023, 2024]
HARNESS_GAMES = 400
BOOTSTRAP_REPS = 200

SCRIMMAGE = {"pass", "run", "qb_kneel", "qb_spike"}
PRE_SNAP_OFFENSE = {
    "False Start",
    "Delay of Game",
    "Illegal Formation",
    "Illegal Shift",
    "Illegal Motion",
    "Offensive Offside",
    "Offensive Too Many Men on Field",
    "Illegal Substitution",
}
# The roster position a participation row lists a man at, folded into the engine's
# `PositionGroup`s for the snaps-per-group rows. Every man on the field is counted by the
# position the source lists him at, whichever side's string he appears in — a lineman
# reporting as an extra blocker is still a lineman — because the engine counts the roster
# position of each man `PlayRecord.onField` names. The defence's front is one group: the
# source writes a four-man front's edge rushers as DE and a three-man front's as OLB, so a
# line and a linebacker corps would be split by scheme rather than by job.
POSITION_GROUPS = [
    ("quarterback", {"QB"}),
    ("backfield", {"RB", "FB", "HB"}),
    ("receiver", {"WR"}),
    ("tightEnd", {"TE"}),
    ("offensiveLine", {"C", "G", "T", "OL", "OT", "OG"}),
    ("frontSeven", {"DE", "DT", "NT", "DL", "LB", "ILB", "OLB", "MLB"}),
    ("defensiveBack", {"CB", "S", "FS", "SS", "DB"}),
]

# How many more men the offence has at the point of attack than the defence has in the box,
# written as a component-key suffix. The harness names the same three buckets in its
# by-advantage block, and `Targets.swift` grades the ones with a sample.
ADVANTAGE_KEYS = {-1: "minusOne", 0: "even", 1: "plusOne"}

# The ten most common accepted fouls in 2023 and 2024 combined, mapped to `Foul` cases.
PENALTY_ROWS = [
    ("Offensive Holding", "offensiveHolding"),
    ("False Start", "falseStart"),
    ("Defensive Pass Interference", "defensivePassInterference"),
    ("Defensive Holding", "defensiveHolding"),
    ("Unnecessary Roughness", "unnecessaryRoughness"),
    ("Delay of Game", "delayOfGame"),
    ("Defensive Offside", "offside"),
    ("Illegal Formation", "illegalFormation"),
    ("Roughing the Passer", "roughingThePasser"),
    ("Neutral Zone Infraction", "neutralZoneInfraction"),
]


def sum_components(parts):
    """Add per-game component dicts together, keeping signed components.

    **Do not fold these with `Counter` addition.** `Counter.__add__` — which is what
    `sum(parts, Counter())` calls — discards every key whose running total is not strictly
    positive. That is documented, deliberate and right for counting, and silently wrong for
    summing a signed quantity: the home side's points less the road side's swings either
    way, and sack yardage is negative in every game, so one is understated by each partial
    sum that dipped below zero and the other vanishes from the result altogether. Nothing
    raises; the key is simply absent and reads back as 0.

    `Counter.update` does *not* drop, so a fold written that way is sound — but it reads
    exactly like the fold that is not, and the difference is invisible at the call site.
    One accumulator, a plain dict, and no way to get it wrong.

    A component no part mentions reads 0, which the metric functions rely on.
    """
    total = defaultdict(float)
    for part in parts:
        for key, value in part.items():
            total[key] += value
    return total


def flag(row, key):
    return row.get(key) == "1"


def num(row, key, default=None):
    value = row.get(key)
    if value in (None, "", "NA"):
        return default
    try:
        return float(value)
    except ValueError:
        return default


def personnel_count(text, units):
    """'1 RB, 1 TE, 3 WR' -> how many of `units` ('RB', or ('CB', 'FS', 'SS', 'S', 'DB'))."""
    if isinstance(units, str):
        units = (units,)
    total = 0
    for part in text.split(","):
        part = part.strip()
        pieces = part.split(" ")
        if len(pieces) == 2 and pieces[1] in units:
            try:
                total += int(pieces[0])
            except ValueError:
                return None
    return total if text else None


# The engine's `DownAndDistanceClass`, in the source's terms. Goal-to-go is its own
# class and takes precedence over the down, so a goal-line snap is in none of the nine
# by-down buckets on either side of the comparison; first down is one bucket whatever the
# distance. The three-way split is 1-3 / 4-6 / 7 or more yards to go, which is what
# `DownAndDistanceClass` splits on -- "second and 4 to 6" is a derived split rather than a
# column in the data, so it is written out here rather than read off one.
RUN_SHARE_BUCKETS = [
    ("secondShort", "second and 1 to 3"),
    ("secondMedium", "second and 4 to 6"),
    ("secondLong", "second and 7 or more"),
    ("thirdShort", "third and 1 to 3"),
    ("thirdMedium", "third and 4 to 6"),
    ("thirdLong", "third and 7 or more"),
    ("fourthShort", "fourth and 1 to 3"),
    ("fourthMedium", "fourth and 4 to 6"),
    ("fourthLong", "fourth and 7 or more"),
]

DOWN_NAMES = {2: "second", 3: "third", 4: "fourth"}


def down_distance_bucket(down, togo, goal_to_go):
    """The `DownAndDistanceClass` case this play was in, or `None` for one with no bucket.

    `None` covers goal-to-go, first down, and a row whose down or distance the feed did
    not record -- none of which is in any of the nine rows, numerator or denominator.
    """
    if goal_to_go or down is None or togo is None:
        return None
    name = DOWN_NAMES.get(int(down))
    if name is None:
        return None
    if togo <= 3:
        return name + "Short"
    if togo <= 6:
        return name + "Medium"
    return name + "Long"


def group_counts(text):
    """'1 RB, 1 TE, 3 WR' -> {'backfield': 1, 'tightEnd': 1, 'receiver': 3}."""
    counts = Counter()
    for part in text.split(","):
        pieces = part.strip().split(" ")
        if len(pieces) != 2:
            continue
        try:
            number = int(pieces[0])
        except ValueError:
            continue
        for group, codes in POSITION_GROUPS:
            if pieces[1] in codes:
                counts[group] += number
    return counts


# --- who the ball was thrown to ---------------------------------------------
#
# The play-by-play names the targeted receiver by identifier and carries no position; the
# participation row for the same play carries positions and names no receiver. The join is
# by index: `offense_players` and `offense_positions` are two `;`-separated lists written
# in one order, so the targeted man's position is the entry at his index in the first.
# Checked over both sourced seasons: every target with an identifier joined, so the weekly
# roster release is not needed for this row.
#
# The denominator is **targets, not attempts** — the convention `row:dropsPerTarget`
# already states. An attempt the feed names no receiver on (a throwaway, a spike, a ball
# batted down at the line) has no target and is not in it, which is what makes this the
# footprint of the read order rather than of how often the passer gave up on it.


def target_group(row, part):
    """The position group the targeted receiver played on this play, or `None`.

    `None` means the play has no target this derivation can resolve: no receiver named, no
    participation row, or a row whose two lists disagree in length or do not contain him.
    Such a play is in no share's numerator *and in no denominator either*, so a feed gap
    cannot masquerade as a group nobody threw to.

    A position code in none of `POSITION_GROUPS` comes back `"other"` rather than `None`:
    the feed lists a lineman or a defensive back as the targeted man a handful of times a
    season, and dropping those would quietly shrink the denominator the three shares are
    read against. They are a target; they are simply not one of the three groups.
    """
    receiver = row.get("receiver_player_id")
    if not receiver or part is None:
        return None
    players = part["offense_players"].split(";")
    positions = part["offense_positions"].split(";")
    if len(players) != len(positions):
        return None
    try:
        index = players.index(receiver)
    except ValueError:
        return None
    code = positions[index]
    for group, codes in POSITION_GROUPS:
        if code in codes:
            return group
    return "other"


def load_participation(path):
    lookup = {}
    with open(path, newline="") as handle:
        for row in csv.DictReader(handle):
            lookup[(row["nflverse_game_id"], row["play_id"])] = row
    return lookup


# --- completions that lose yardage ------------------------------------------------------
#
# Its own accumulator, kept apart from the completion counters in `read_season` because it
# asks a different question of the same play. `completionsZeroOrFewer` counts a catch that
# did not gain; this one counts a catch that went backwards, and the two are not the same
# quantity -- a ball caught level with the previous spot is in the first and not in this.
#
# Why that distinction is the interesting one: forward progress makes a runner's or an
# airborne receiver's progress the dead-ball spot, irrespective of his being driven back by
# an opponent (2025 rulebook, 3-12-1; 7-3-3 for the airborne catch). So a completion can
# only lose yardage when the catch itself was made behind the previous spot. The share this
# derives is therefore a statement about how often the sport throws the ball behind the
# line and completes it -- not about receivers being tackled backwards, which the rules do
# not let count.
#
# The yardage is carried signed so that the mean loss is a ratio of component sums like
# every other band here. That is exactly the shape a counting accumulator gets silently
# wrong -- every part is negative, so `Counter` addition never lets the key exist and the
# mean reads a clean, wrong 0 -- which is why `sum_components` exists, and why the
# self-test below folds these components through it rather than only checking the
# classification.


def negative_completion_components(yards):
    """The negative-completion components of one completed pass, as a component dict.

    `yards` is the release's signed `yards_gained` for the play. Exactly zero is not a
    loss: it is a catch level with the previous spot, and it is already counted by
    `completionsZeroOrFewer`. A component is emitted either way, the zero included, so the
    key exists in every game's part rather than only in the games that had one.
    """
    if yards < 0:
        return {"completionsNegative": 1, "completionNegativeYards": float(yards)}
    return {"completionsNegative": 0, "completionNegativeYards": 0.0}


# Returns that lose yardage, the same shape and for the same reason.
#
# A return can end behind the spot the ball was fielded at, and how often it does and how
# far back it goes is the only sourced thing there is to say about it: no article governs
# the spot. Forward progress is about a runner an opponent drives backward, and a returner
# met near where he fielded it was never driven anywhere -- his advance ended where it
# started. So this is a measurement rather than a rule, and it is derived here so that a
# model of the return has a left tail to be read against.
#
# `LOSS_BOUND` is where the sport's own tail effectively ends, and the component below
# counts what falls past it, so the figure that justifies a bound and the bound itself
# cannot drift apart. The yardage is carried signed for the reason the completions above
# are.


LOSS_BOUND = 8


def negative_return_components(kind, yards):
    """The negative-return components of one kick actually run back, as a component dict.

    `kind` is "punt" or "kickoff" and `yards` is the release's `return_yards` for the
    play. Exactly zero is not a loss: the returner was put down on the spot he fielded it
    at. A component is emitted either way so the key exists in every game's part rather
    than only in the games that had one.
    """
    lost = yards < 0
    return {
        f"{kind}ReturnsNegative": 1 if lost else 0,
        f"{kind}ReturnNegativeYards": float(yards) if lost else 0.0,
        f"{kind}ReturnsPastTheBound": 1 if yards < -LOSS_BOUND else 0,
    }


def read_season(directory, season):
    """Fold one season into per-game component sums."""
    participation = {}
    part_path = os.path.join(directory, f"pbp_participation_{season}.csv")
    if season in PARTICIPATION_SEASONS and os.path.exists(part_path):
        participation = load_participation(part_path)

    games = {}  # game_id -> Counter of components
    drives = {}  # (game_id, fixed_drive) -> state
    finals = {}
    wins = Counter()

    path = os.path.join(directory, f"play_by_play_{season}.csv.gz")
    with gzip.open(path, "rt", newline="") as handle:
        for row in csv.DictReader(handle):
            if row["season_type"] != "REG":
                continue
            game = row["game_id"]
            c = games.setdefault(game, Counter())
            play_type = row["play_type"]
            posteam = row["posteam"]
            is_home_offense = posteam == row["home_team"]
            yards = num(row, "yards_gained", 0.0)
            down = num(row, "down")
            two_point = flag(row, "two_point_attempt")

            if game not in finals:
                finals[game] = (num(row, "home_score", 0.0), num(row, "away_score", 0.0), row["home_team"], row["away_team"])
                c["games"] = 1
                home, away = finals[game][0], finals[game][1]
                c["points"] = home + away
                margin = abs(home - away)
                c["within3"] = 1 if margin <= 3 else 0
                c["within7"] = 1 if margin <= 7 else 0
                c["by14"] = 1 if margin >= 14 else 0
                c["tie"] = 1 if margin == 0 else 0
                # The spread of the point differential, as component sums, so it resamples
                # with every other row. Var(D) = E[D**2] - E[D]**2 wants the sum of D and
                # the sum of D squared. The mean is carried as two non-negative halves, the
                # margin when the home side won and the margin when the road side did, and
                # E[D] is their difference; the square is never negative. The halves were
                # written that way to survive an accumulator that dropped signed components,
                # which `sum_components` no longer does -- they stay because the recorded
                # band was derived from them and collapsing them into one signed component
                # would move a row's arithmetic outside a retune, not because they are still
                # needed.
                c["marginHomeWon"] = max(0.0, home - away)
                c["marginAwayWon"] = max(0.0, away - home)
                c["differentialSquared"] = (home - away) ** 2
                c["homeWin"] = 1 if home > away else 0
                c["awayWin"] = 1 if away > home else 0
                c["homeEdge"] = home - away
                if home > away:
                    wins[row["home_team"]] += 1
                elif away > home:
                    wins[row["away_team"]] += 1
                else:
                    wins[row["home_team"]] += 0.5
                    wins[row["away_team"]] += 0.5

            if play_type and (play_type != "no_play" or flag(row, "penalty")):
                c["allPlays"] += 1
            if row["qtr"] == "5" and play_type:
                c["overtimeGame"] = 1
                remaining = num(row, "quarter_seconds_remaining")
                if remaining is not None:
                    c["overtimeSeconds"] = max(c["overtimeSeconds"], 600 - remaining)
            if flag(row, "timeout") and row.get("timeout_team"):
                c["timeouts"] += 1

            # Penalties: accepted ones, by type, and pre-snap offensive fouls by venue.
            if flag(row, "penalty") and row["penalty_type"]:
                c["penalties"] += 1
                c["penalty:" + row["penalty_type"]] += 1
                if row["penalty_type"] in PRE_SNAP_OFFENSE and row["penalty_team"] == posteam:
                    c["preSnapHome" if is_home_offense else "preSnapAway"] += 1
            if posteam and (play_type in SCRIMMAGE or (play_type == "no_play" and flag(row, "penalty"))) and not two_point:
                c["offSnapsHome" if is_home_offense else "offSnapsAway"] += 1

            # Scoring by source.
            if flag(row, "touchdown"):
                c["touchdowns"] += 1
            if row["field_goal_result"] == "made":
                c["fieldGoalsMade"] += 1
            if row["extra_point_result"] == "good":
                c["extraPointsGood"] += 1
            if row["extra_point_attempt"] == "1":
                c["extraPointAttempts"] += 1
            if two_point:
                c["twoPointTries"] += 1
                # The try is a pass *or* a run and the two are different plays, so the
                # split is two counts rather than one share: a season where the run
                # branch is never called reads as a zero here and not as a missing key.
                if play_type == "run":
                    c["twoPointRuns"] += 1
                elif play_type == "pass":
                    c["twoPointPasses"] += 1
                if row["two_point_conv_result"] == "success":
                    c["twoPointGood"] += 1
            if flag(row, "safety"):
                c["safeties"] += 1

            # Kicks.
            if flag(row, "kickoff_attempt") and play_type == "kickoff":
                c["kickoffs"] += 1
                onside = "onside" in row["desc"].lower()
                if onside:
                    c["onsideKicks"] += 1
                    if flag(row, "own_kickoff_recovery"):
                        c["onsideRecovered"] += 1
                elif flag(row, "touchback"):
                    c["kickoffTouchbacks"] += 1
                elif (
                    not flag(row, "kickoff_out_of_bounds")
                    and not flag(row, "kickoff_fair_catch")
                    and (row["kickoff_returner_player_id"] or num(row, "return_yards") is not None)
                ):
                    c["kickoffReturns"] += 1
                    c["kickoffReturnYards"] += num(row, "return_yards", 0.0)
                    for key, value in negative_return_components(
                        "kickoff", num(row, "return_yards", 0.0)
                    ).items():
                        c[key] += value
                if flag(row, "return_touchdown"):
                    c["kickReturnTouchdowns"] += 1
            if flag(row, "punt_attempt") and play_type == "punt":
                c["punts"] += 1
                # Punts struck from inside the opponent's 45, where placement rather than
                # distance is the whole play: `yardline_100` is the distance to the
                # opponent's goal, which is the harness's `Situation.ballOn`.
                punt_from = num(row, "yardline_100")
                if punt_from is not None and punt_from <= 45:
                    c["plusTerritoryPunts"] += 1
                    if flag(row, "touchback"):
                        c["plusTerritoryTouchbacks"] += 1
                distance = num(row, "kick_distance", 0.0)
                returned = num(row, "return_yards", 0.0)
                c["puntNetYards"] += distance - returned - (20 if flag(row, "touchback") else 0)
                if not flag(row, "punt_blocked") and num(row, "kick_distance") is not None:
                    c["puntsKicked"] += 1
                    c["puntGrossYards"] += distance
                if (
                    row["punt_returner_player_id"]
                    and not flag(row, "punt_fair_catch")
                    and not flag(row, "punt_downed")
                    and not flag(row, "touchback")
                    and not flag(row, "punt_blocked")
                ):
                    c["puntReturns"] += 1
                    c["puntReturnYards"] += returned
                    for key, value in negative_return_components("punt", returned).items():
                        c[key] += value
                if flag(row, "return_touchdown"):
                    c["kickReturnTouchdowns"] += 1
            if flag(row, "field_goal_attempt") and play_type == "field_goal":
                distance = num(row, "kick_distance")
                if distance is not None:
                    bucket = "fg<30" if distance < 30 else "fg30" if distance < 40 else "fg40" if distance < 50 else "fg50"
                    c["fgAttempts"] += 1
                    c[bucket + ":att"] += 1
                    if row["field_goal_result"] == "made":
                        c[bucket + ":made"] += 1
            if flag(row, "return_touchdown") and play_type not in ("kickoff", "punt"):
                c["defensiveReturnTouchdowns"] += 1
            if flag(row, "return_touchdown"):
                c["nonOffensiveTouchdowns"] += 1

            # Fourth down decisions, from the plays that decide them.
            if down == 4 and play_type in ("punt", "field_goal", "pass", "run", "qb_kneel", "qb_spike") and not two_point:
                c["fourthDowns"] += 1
                if play_type == "punt":
                    c["fourthPunts"] += 1
                elif play_type == "field_goal":
                    c["fourthKicks"] += 1
                else:
                    c["fourthGoes"] += 1
                    if flag(row, "fourth_down_converted"):
                        c["fourthConverted"] += 1
                    if flag(row, "fourth_down_failed"):
                        c["fourthFailed"] += 1
                if num(row, "ydstogo") == 1:
                    c["fourthAndOne"] += 1
                    if play_type not in ("punt", "field_goal"):
                        c["fourthAndOneGoes"] += 1

            if down == 3 and play_type in ("punt", "field_goal", "pass", "run", "qb_kneel", "qb_spike", "no_play") and not two_point:
                c["thirdDownSnaps"] += 1
                c["thirdDownDistance"] += num(row, "ydstogo", 0.0)
            if flag(row, "third_down_converted"):
                c["thirdConverted"] += 1
            if flag(row, "third_down_failed"):
                c["thirdFailed"] += 1

            # Drives: one state per (game, fixed_drive).
            drive_key = (game, row["fixed_drive"])
            if row["fixed_drive"] and posteam:
                drive = drives.get(drive_key)
                if drive is None:
                    drive = {"game": game, "plays": 0, "result": row["fixed_drive_result"], "start": None, "redZone": False, "lastPunt": False}
                    drives[drive_key] = drive
                if drive["start"] is None and down is not None and play_type != "kickoff":
                    yardline = num(row, "yardline_100")
                    if yardline is not None:
                        drive["start"] = 100 - yardline
                yardline = num(row, "yardline_100")
                if down is not None and yardline is not None and yardline <= 20:
                    drive["redZone"] = True
                if play_type in SCRIMMAGE and not two_point:
                    drive["plays"] += 1

            if play_type not in SCRIMMAGE or two_point:
                continue

            # From here on, a play from scrimmage.
            c["scrimmage"] += 1
            if down == 1:
                c["firstDownSnaps"] += 1
                c["firstDownYards"] += yards
            if flag(row, "first_down_rush") or flag(row, "first_down_pass"):
                c["firstDownsEarned"] += 1
            if flag(row, "first_down"):
                c["firstDownsIncludingPenalty"] += 1
            yardline = num(row, "yardline_100")
            if yardline is not None and yardline >= 90:
                c["snapsInsideOwn10"] += 1
            if flag(row, "fumble"):
                c["fumbles"] += 1
            if flag(row, "fumble_lost"):
                c["fumblesLost"] += 1
            if play_type == "qb_kneel":
                c["kneels"] += 1
            if play_type == "qb_spike":
                c["spikes"] += 1

            scramble = flag(row, "qb_scramble")
            sack = flag(row, "sack")
            attempt = flag(row, "pass_attempt") and not sack
            designed_run = play_type == "run" and not scramble

            # Run share by down-and-distance bucket. The denominator is the calls a
            # coordinator chooses between -- a designed run or a dropback -- so a sack or
            # a scramble counts as the pass it was called as, and a kneel or a spike is
            # in neither: both are clock plays rather than a choice about the sport.
            bucket = down_distance_bucket(down, num(row, "ydstogo"), flag(row, "goal_to_go"))
            if bucket is not None and (designed_run or attempt or sack or scramble):
                c["calls:" + bucket] += 1
                if designed_run:
                    c["runs:" + bucket] += 1

            # Where a play ended laterally. The denominator is the plays that ended with
            # the ball dead in the field of play or out of bounds -- what the harness
            # reads off `PlayEnding.tackled` and `.outOfBounds` -- so an incompletion, a
            # score and a turnover are in neither half. The feed carries no "tackled"
            # flag, so this side of it is written as everything else being absent.
            ended_live = not (
                flag(row, "incomplete_pass")
                or flag(row, "touchdown")
                or flag(row, "interception")
                or flag(row, "fumble_lost")
                or flag(row, "safety")
            )
            if ended_live:
                c["endedDownOrOut"] += 1
                if flag(row, "out_of_bounds"):
                    c["endedOutOfBounds"] += 1
                # Trailing inside two minutes of either half, which is the harness's
                # `SituationClass.isDesperation`. A runner going out of bounds starts the
                # clock on the Referee's ready signal, except that it starts on the snap
                # after the two-minute warning of the first half and inside the last five
                # minutes of the second (2025 rulebook, 4-3-2-a). Both halves of this
                # bucket sit inside those windows, so here the sideline buys a down.
                remaining = num(row, "half_seconds_remaining")
                differential = num(row, "score_differential")
                if (
                    remaining is not None
                    and remaining <= 120
                    and row["qtr"] in ("2", "4")
                    and differential is not None
                    and differential < 0
                ):
                    c["lateEndedDownOrOut"] += 1
                    if flag(row, "out_of_bounds"):
                        c["lateEndedOutOfBounds"] += 1

            if scramble:
                c["scrambles"] += 1
                c["scrambleYards"] += yards
            if designed_run:
                c["carries"] += 1
                c["rushYards"] += yards
                c["stuffed"] += 1 if yards <= 0 else 0
                c["carries2orFewer"] += 1 if yards <= 2 else 0
                c["carries10plus"] += 1 if yards >= 10 else 0
                c["carries20plus"] += 1 if yards >= 20 else 0
            if sack:
                c["sacks"] += 1
                c["sackYards"] += yards
            if attempt:
                c["attempts"] += 1
                if flag(row, "complete_pass"):
                    c["completions"] += 1
                    # Two sums, because two different quantities are wanted and the word
                    # "gross" was used for both. `passYards` is signed: a ball caught three
                    # yards behind the line for a three-yard loss is -3, which is what the
                    # passing-yards, yards-per-attempt and yards-per-completion rows are
                    # built on, and what this release records (379 such completions in 2023
                    # and 337 in 2024). `passYardsPositive` counts that catch as zero, and
                    # exists for the yards-per-play row alone. Whichever a row uses, its
                    # note in `Targets.swift` says which in words.
                    c["passYards"] += yards
                    c["passYardsPositive"] += max(0.0, yards)
                    if yards <= 0:
                        c["completionsZeroOrFewer"] += 1
                    for key, value in negative_completion_components(yards).items():
                        c[key] += value
                    if yards > 0 or flag(row, "pass_touchdown"):
                        c["completionsPositive"] += 1
                if flag(row, "interception"):
                    c["interceptions"] += 1
                # Target share by position group: see `target_group` above.
                group = target_group(row, participation.get((game, row["play_id"])))
                if group is not None:
                    c["targets"] += 1
                    c["targets:" + group] += 1
            if attempt or sack or scramble:
                c["dropbacks"] += 1
                c["dropbackLoss"] += 1 if yards < 0 else 0
                c["dropbackNoGain"] += 1 if yards == 0 else 0
                c["dropback10plus"] += 1 if yards >= 10 else 0
                c["dropback20plus"] += 1 if yards >= 20 else 0
                c["dropback40plus"] += 1 if yards >= 40 else 0
                part = participation.get((game, row["play_id"]))
                if part is not None and part["was_pressure"] in ("TRUE", "FALSE", "1", "0"):
                    c["pressureDropbacks"] += 1
                    if part["was_pressure"] in ("TRUE", "1"):
                        c["pressured"] += 1
                        # The sack is counted only where the pressure flag was readable,
                        # so numerator and denominator come off the same set of plays.
                        # Dividing every sack by the pressures the feed happened to mark
                        # would read the rate high by whatever share of plays it missed.
                        if sack:
                            c["pressuredSacks"] += 1

            part = participation.get((game, row["play_id"]))
            if part is not None and part["offense_personnel"] and part["defense_personnel"]:
                # Who was on the field, by group. Scaled to plays from scrimmage when the
                # per-team-game rate is taken, because a play with no participation row
                # still had twenty-two men on it.
                c["groupSnaps"] += 1
                for side in ("offense_personnel", "defense_personnel"):
                    for group, count in group_counts(part[side]).items():
                        c["snaps:" + group] += count
                backs = personnel_count(part["offense_personnel"], "RB")
                ends = personnel_count(part["offense_personnel"], "TE")
                backs_db = personnel_count(part["defense_personnel"], ("CB", "FS", "SS", "S", "DB"))
                if backs is not None and ends is not None and backs_db is not None:
                    c["personnelSnaps"] += 1
                    if backs == 1 and ends == 1:
                        c["personnel11"] += 1
                    if backs_db == 4:
                        c["packageBase"] += 1
                    elif backs_db == 5:
                        c["packageNickel"] += 1
                    if designed_run and down == 1 and num(row, "ydstogo") == 10:
                        blockers = 5 + ends + max(0, backs - 1)
                        box_by_package = 11 - backs_db
                        advantage = blockers - box_by_package
                        # The denominator for the share rows: every first-and-ten designed
                        # carry this feed could count the two sides of, whatever the count
                        # came out at. Without it a bucket's carries can be compared to
                        # another bucket's but not to how often the sport is in that box at
                        # all, which is the question "is this bucket rare" asks.
                        c["ypcFirstAndTen"] += 1
                        # -1, 0 and +1 only. Further out the source's own sample thins to
                        # where a band would be noise, and the harness prints no bucket
                        # beyond +1 either.
                        if advantage in (-1, 0, 1):
                            key = ADVANTAGE_KEYS[advantage]
                            c["ypcCarries:" + key] += 1
                            c["ypcYards:" + key] += yards
                        box = num(part, "defenders_in_box")
                        if box is not None:
                            advantage_box = blockers - int(box)
                            if advantage_box in (-1, 0, 1):
                                key = ADVANTAGE_KEYS[advantage_box]
                                c["ypcBoxCarries:" + key] += 1
                                c["ypcBoxYards:" + key] += yards

    # Fold drives into their games.
    for drive in drives.values():
        c = games[drive["game"]]
        c["drives"] += 1
        c["drivePlays"] += drive["plays"]
        if drive["plays"] <= 3:
            c["drives3orFewer"] += 1
        elif drive["plays"] <= 7:
            c["drives4to7"] += 1
        else:
            c["drives8plus"] += 1
        if drive["result"] == "Punt":
            c["driveEndPunt"] += 1
            if drive["plays"] <= 3:
                c["threeAndOuts"] += 1
        elif drive["result"] == "Touchdown":
            c["driveEndTouchdown"] += 1
        elif drive["result"] == "Turnover on downs":
            c["driveEndDowns"] += 1
        if drive["start"] is not None:
            c["driveStarts"] += 1
            c["driveStartYards"] += drive["start"]
            if drive["start"] < 50:
                c["driveStartOwnHalf"] += 1
        if drive["redZone"]:
            c["redZoneDrives"] += 1
            if drive["result"] == "Touchdown":
                c["redZoneTouchdowns"] += 1

    win_sigma = statistics.pstdev(list(wins.values())) if wins else 0.0
    return games, win_sigma, between_team_sigma(finals)


def between_team_sigma(finals):
    """How much of the point differential is the clubs and not the afternoon.

    A one-way random-effects split of each club's per-game point differential. Club *i*
    plays *n* games, its differential in game *k* is `d[i][k]`, and the balanced-design
    estimator is

        between variance = variance of the club means - (pooled within-club variance) / n

    which is `(MSB - MSW) / n` written out. The subtraction is the whole point: the spread
    of the club *means* is inflated by a season being short, and the second term is exactly
    that inflation. The square root is the standard deviation of a club's true expected
    point differential per game against an average opponent, which is what a generated
    league's spread of team strength has to reproduce.

    What it assumes, in full, because the number is used to set a generation constant:
    every club plays every other about equally often (a real schedule is divisional-heavy
    and the harness's is a rotation, so both are close but neither is exact); home field is
    a constant across clubs rather than a club trait; and a club's strength does not move
    during the season. Each of those, violated, moves the estimate up rather than down --
    schedule imbalance and in-season drift both read as between-club spread -- so this is an
    upper estimate of a club's spread and not a lower one.
    """
    per_team = {}
    for home, away, home_team, away_team in finals.values():
        per_team.setdefault(home_team, []).append(home - away)
        per_team.setdefault(away_team, []).append(away - home)
    if len(per_team) < 2:
        return float("nan")
    means = {team: statistics.mean(values) for team, values in per_team.items()}
    between = statistics.variance(list(means.values()))
    residual = sum(
        sum((value - means[team]) ** 2 for value in values)
        for team, values in per_team.items()
    ) / sum(len(values) - 1 for values in per_team.values())
    games_each = statistics.mean([len(values) for values in per_team.values()])
    variance = between - residual / games_each
    return math.sqrt(variance) if variance > 0 else 0.0


def div(a, b):
    return a / b if b else float("nan")


def per_team_game(key):
    return lambda c: div(c[key], 2 * c["games"])


def per_game(key):
    return lambda c: div(c[key], c["games"])


def share(numerator, denominator):
    return lambda c: 100 * div(c[numerator], c[denominator])


# (id, label, seasons the band is sourced from, decimals, function of the component sums)
# Seasons: "play" = 2023 and 2024; "2025" = the 2025 rulebook rows; "2024" = the 2024
# rulebook variant kept for `--rulebook 2024`.
PLAY = (2023, 2024)
NEW = (2025,)
OLD = (2024,)

METRICS = [
    ("points", "points per team-game", PLAY, 1, per_team_game("points")),
    ("passingYards", "gross passing yards per team-game", PLAY, 1, per_team_game("passYards")),
    ("rushingYards", "designed-run rushing yards per team-game", PLAY, 1, per_team_game("rushYards")),
    ("yardsPerCarry", "yards per designed carry", PLAY, 1, lambda c: div(c["rushYards"], c["carries"])),
    ("completionPercentage", "completion percentage", PLAY, 1, share("completions", "attempts")),
    ("completionPercentagePositiveOnly", "completions of >0 yards or a TD, per attempt (harness definition)", PLAY, 1, share("completionsPositive", "attempts")),
    ("sackRate", "sacks per dropback %", PLAY, 1, share("sacks", "dropbacks")),
    ("interceptionRate", "interceptions per attempt %", PLAY, 1, share("interceptions", "attempts")),
    ("thirdDownConversion", "third down conversion %", PLAY, 1, lambda c: 100 * div(c["thirdConverted"], c["thirdConverted"] + c["thirdFailed"])),
    ("playsFromScrimmage", "plays from scrimmage per team-game", PLAY, 1, per_team_game("scrimmage")),
    ("penaltiesPerGame", "accepted penalties per game, both teams", PLAY, 1, per_game("penalties")),
    ("thirdDownDistance", "average third down distance", PLAY, 1, lambda c: div(c["thirdDownDistance"], c["thirdDownSnaps"])),
    ("firstDownGain", "yards gained on first down", PLAY, 1, lambda c: div(c["firstDownYards"], c["firstDownSnaps"])),
    ("yardsPerAttempt", "gross yards per pass attempt", PLAY, 1, lambda c: div(c["passYards"], c["attempts"])),
    ("yardsPerPlay", "yards per play (harness definition: pass + designed run + sack yards over all scrimmage plays)", PLAY, 1, lambda c: div(c["passYardsPositive"] + c["rushYards"] + c["sackYards"], c["scrimmage"])),
    ("yardsPerPlayOfficial", "yards per play (all yards over all scrimmage plays)", PLAY, 1, lambda c: div(c["passYards"] + c["rushYards"] + c["sackYards"] + c["scrambleYards"], c["scrimmage"])),
    ("yardsPerCompletion", "gross yards per completion", PLAY, 1, lambda c: div(c["passYards"], c["completions"])),
    ("playsPerGame", "plays of every kind per game", PLAY, 0, per_game("allPlays")),
    ("tiesPerGame", "ties per game", NEW, 3, per_game("tie")),
    ("overtimeRate", "games reaching overtime %", NEW, 1, share("overtimeGame", "games")),
    ("overtimeLength", "seconds played per overtime game", NEW, 0, lambda c: div(c["overtimeSeconds"], c["overtimeGame"])),
    ("pointsFromTouchdowns", "share of points from touchdowns %", PLAY, 1, lambda c: 100 * div(6 * c["touchdowns"], c["points"])),
    ("pointsFromFieldGoals", "share of points from field goals %", PLAY, 1, lambda c: 100 * div(3 * c["fieldGoalsMade"], c["points"])),
    ("drivesPerTeamGame", "drives per team-game", PLAY, 1, per_team_game("drives")),
    ("playsPerDrive", "offensive plays per drive", PLAY, 1, lambda c: div(c["drivePlays"], c["drives"])),
    ("firstDownsPerTeamGame", "first downs by rush or pass per team-game", PLAY, 1, per_team_game("firstDownsEarned")),
    ("firstDownsIncludingPenalty", "first downs including by penalty per team-game", PLAY, 1, per_team_game("firstDownsIncludingPenalty")),
    ("drives3orFewer", "drives of 3 plays or fewer %", PLAY, 1, share("drives3orFewer", "drives")),
    ("drives4to7", "drives of 4 to 7 plays %", PLAY, 1, share("drives4to7", "drives")),
    ("drives8plus", "drives of 8 or more plays %", PLAY, 1, share("drives8plus", "drives")),
    ("threeAndOut", "three and outs per drive %", PLAY, 1, share("threeAndOuts", "drives")),
    ("driveEndPunt", "drives ending in a punt %", PLAY, 1, share("driveEndPunt", "drives")),
    ("driveEndTouchdown", "drives ending in a touchdown %", PLAY, 1, share("driveEndTouchdown", "drives")),
    ("driveEndDowns", "drives ending on downs %", PLAY, 1, share("driveEndDowns", "drives")),
    ("averageStart2025", "average drive start, own yard line (2025 rules)", NEW, 1, lambda c: div(c["driveStartYards"], c["driveStarts"])),
    ("averageStart2024", "average drive start, own yard line (2024 rules)", OLD, 1, lambda c: div(c["driveStartYards"], c["driveStarts"])),
    ("ownHalfStarts2025", "drives starting in own half % (2025 rules)", NEW, 1, share("driveStartOwnHalf", "driveStarts")),
    ("ownHalfStarts2024", "drives starting in own half % (2024 rules)", OLD, 1, share("driveStartOwnHalf", "driveStarts")),
    ("carriesStuffed", "carries for 0 yards or fewer %", PLAY, 1, share("stuffed", "carries")),
    ("carries2orFewer", "carries of 2 yards or fewer %", PLAY, 1, share("carries2orFewer", "carries")),
    ("carries10plus", "carries of 10 or more %", PLAY, 1, share("carries10plus", "carries")),
    ("carries20plus", "carries of 20 or more %", PLAY, 1, share("carries20plus", "carries")),
    ("dropbackLoss", "dropbacks losing yards %", PLAY, 1, share("dropbackLoss", "dropbacks")),
    ("dropbackNoGain", "dropbacks with no gain %", PLAY, 1, share("dropbackNoGain", "dropbacks")),
    ("dropback10plus", "dropbacks gaining 10 or more %", PLAY, 1, share("dropback10plus", "dropbacks")),
    ("dropback20plus", "dropbacks gaining 20 or more %", PLAY, 1, share("dropback20plus", "dropbacks")),
    ("dropback40plus", "dropbacks gaining 40 or more %", PLAY, 1, share("dropback40plus", "dropbacks")),
    ("fieldGoalsPerTeamGame", "field goal attempts per team-game", PLAY, 1, per_team_game("fgAttempts")),
    ("fieldGoalsUnder30", "field goals made, under 30 yards %", PLAY, 1, share("fg<30:made", "fg<30:att")),
    ("fieldGoals30to39", "field goals made, 30-39 yards %", PLAY, 1, share("fg30:made", "fg30:att")),
    ("fieldGoals40to49", "field goals made, 40-49 yards %", PLAY, 1, share("fg40:made", "fg40:att")),
    ("fieldGoals50plus", "field goals made, 50+ yards %", PLAY, 1, share("fg50:made", "fg50:att")),
    ("fieldGoalAttemptsUnder30", "field goal attempts under 30 yards, share of attempts %", PLAY, 1, share("fg<30:att", "fgAttempts")),
    ("fieldGoalAttempts30to39", "field goal attempts 30-39 yards, share %", PLAY, 1, share("fg30:att", "fgAttempts")),
    ("fieldGoalAttempts40to49", "field goal attempts 40-49 yards, share %", PLAY, 1, share("fg40:att", "fgAttempts")),
    ("fieldGoalAttempts50plus", "field goal attempts 50+ yards, share %", PLAY, 1, share("fg50:att", "fgAttempts")),
    ("extraPointsMade", "extra points made %", PLAY, 1, share("extraPointsGood", "extraPointAttempts")),
    ("twoPointTries", "two-point tries per team-game", PLAY, 2, per_team_game("twoPointTries")),
    ("twoPointConversion", "two-point conversion %", PLAY, 1, share("twoPointGood", "twoPointTries")),
    ("gamesWithin3", "games decided by 3 or fewer %", PLAY, 1, share("within3", "games")),
    ("gamesWithin7", "games decided by 7 or fewer %", PLAY, 1, share("within7", "games")),
    ("fumblesLost", "fumbles lost per team-game", PLAY, 2, per_team_game("fumblesLost")),
    ("fumblesKept", "fumbles recovered by the fumbling team per team-game", PLAY, 2, lambda c: div(c["fumbles"] - c["fumblesLost"], 2 * c["games"])),
    ("turnovers", "turnovers per team-game", PLAY, 2, lambda c: div(c["interceptions"] + c["fumblesLost"], 2 * c["games"])),
    ("nonOffensiveTouchdowns2025", "touchdowns not by the offence per team-game (2025 rules)", NEW, 2, per_team_game("nonOffensiveTouchdowns")),
    ("nonOffensiveTouchdowns2024", "touchdowns not by the offence per team-game (2024 rules)", OLD, 2, per_team_game("nonOffensiveTouchdowns")),
    ("defensiveReturnTouchdowns", "interception and fumble return touchdowns per team-game", PLAY, 2, per_team_game("defensiveReturnTouchdowns")),
    ("kickReturnTouchdowns2025", "kickoff and punt return touchdowns per team-game (2025 rules)", NEW, 2, per_team_game("kickReturnTouchdowns")),
    ("kickReturnTouchdowns2024", "kickoff and punt return touchdowns per team-game (2024 rules)", OLD, 2, per_team_game("kickReturnTouchdowns")),
    ("kickoffTouchbacks2025", "kickoff touchbacks, share of kickoffs % (2025 rules)", NEW, 1, share("kickoffTouchbacks", "kickoffs")),
    ("kickoffTouchbacks2024", "kickoff touchbacks, share of kickoffs % (2024 rules)", OLD, 1, share("kickoffTouchbacks", "kickoffs")),
    ("kickoffsReturned2025", "kickoffs returned, share of kickoffs % (2025 rules)", NEW, 1, share("kickoffReturns", "kickoffs")),
    ("kickoffsReturned2024", "kickoffs returned, share of kickoffs % (2024 rules)", OLD, 1, share("kickoffReturns", "kickoffs")),
    ("onsideKicks2025", "onside kicks per game (2025 rules)", NEW, 2, per_game("onsideKicks")),
    ("onsideKicks2024", "onside kicks per game (2024 rules)", OLD, 2, per_game("onsideKicks")),
    ("onsideRecovery2025", "onside kicks recovered % (2025 rules)", NEW, 1, share("onsideRecovered", "onsideKicks")),
    ("onsideRecovery2024", "onside kicks recovered % (2024 rules)", OLD, 1, share("onsideRecovered", "onsideKicks")),
    ("puntsPerTeamGame", "punts per team-game", PLAY, 1, per_team_game("punts")),
    ("netPunt", "net punt yards", PLAY, 1, lambda c: div(c["puntNetYards"], c["punts"])),
    ("grossPunt", "gross punt yards, blocked punts excluded", PLAY, 1, lambda c: div(c["puntGrossYards"], c["puntsKicked"])),
    ("puntsReturned", "punts returned, share of punts %", PLAY, 1, share("puntReturns", "punts")),
    ("puntReturnYards", "yards per punt return", PLAY, 1, lambda c: div(c["puntReturnYards"], c["puntReturns"])),
    ("kickoffReturnYards2025", "yards per kickoff return (2025 rules)", NEW, 1, lambda c: div(c["kickoffReturnYards"], c["kickoffReturns"])),
    ("kickoffReturnYards2024", "yards per kickoff return (2024 rules)", OLD, 1, lambda c: div(c["kickoffReturnYards"], c["kickoffReturns"])),
    ("fourthDownPunted", "fourth downs punted %", PLAY, 1, share("fourthPunts", "fourthDowns")),
    ("fourthDownKicked", "fourth downs kicked %", PLAY, 1, share("fourthKicks", "fourthDowns")),
    ("fourthDownWentForIt", "fourth downs gone for %", PLAY, 1, share("fourthGoes", "fourthDowns")),
    ("fourthDownAttempts", "fourth down attempts per team-game", PLAY, 1, per_team_game("fourthGoes")),
    ("fourthDownConversion", "fourth down conversion %", PLAY, 1, lambda c: 100 * div(c["fourthConverted"], c["fourthConverted"] + c["fourthFailed"])),
    ("fourthAndOneWentForIt", "fourth and one gone for %", PLAY, 1, share("fourthAndOneGoes", "fourthAndOne")),
    ("snapsInsideOwn10", "snaps inside own 10 per team-game", PLAY, 2, per_team_game("snapsInsideOwn10")),
    ("safeties", "safeties per team-game", PLAY, 2, per_team_game("safeties")),
    ("preSnapRoadVsHome", "offensive pre-snap fouls per snap, road over home", PLAY, 2, lambda c: div(div(c["preSnapAway"], c["offSnapsAway"]), div(c["preSnapHome"], c["offSnapsHome"]))),
    ("homeWinRate", "home win rate, decided games % (no target: crowd only until M3)", PLAY, 1, lambda c: 100 * div(c["homeWin"], c["homeWin"] + c["awayWin"])),
    ("homeScoringEdge", "home scoring edge, points (no target: crowd only until M3)", PLAY, 1, per_game("homeEdge")),
    ("redZoneTouchdownRate", "red zone trips ending in a touchdown %", PLAY, 1, share("redZoneTouchdowns", "redZoneDrives")),
    ("pressureRate", "pressure rate per dropback %", PLAY, 1, share("pressured", "pressureDropbacks")),
    ("completionsZeroOrFewer", "completions for zero or fewer yards, share of completions %", PLAY, 1, share("completionsZeroOrFewer", "completions")),
    ("personnel11", "snaps in 11 personnel %", PLAY, 1, share("personnel11", "personnelSnaps")),
    ("packageNickel", "snaps against nickel %", PLAY, 1, share("packageNickel", "personnelSnaps")),
    ("packageBase", "snaps against base %", PLAY, 1, share("packageBase", "personnelSnaps")),
    ("ypcEvenCount", "yards per carry, even count, first and ten (box = 11 - DBs)", PLAY, 1, lambda c: div(c["ypcYards:even"], c["ypcCarries:even"])),
    ("ypcOutnumberedByOne", "yards per carry, outnumbered by one, first and ten (box = 11 - DBs)", PLAY, 1, lambda c: div(c["ypcYards:minusOne"], c["ypcCarries:minusOne"])),
    ("ypcEvenCountBox", "yards per carry, even count by defenders in box", PLAY, 1, lambda c: div(c["ypcBoxYards:even"], c["ypcBoxCarries:even"])),
    ("ypcOutnumberedByOneBox", "yards per carry, outnumbered by one by defenders in box", PLAY, 1, lambda c: div(c["ypcBoxYards:minusOne"], c["ypcBoxCarries:minusOne"])),
    ("scramblesPerGame", "scrambles per game", PLAY, 1, per_game("scrambles")),
    ("kneelsPerGame", "kneels per game", PLAY, 1, per_game("kneels")),
    ("spikesPerGame", "spikes per game", PLAY, 1, per_game("spikes")),
    ("timeoutsPerGame", "timeouts spent per game", PLAY, 1, per_game("timeouts")),
] + [
    ("penalty." + foul, f"{name} per game, both teams", PLAY, 2, per_game("penalty:" + name))
    for name, foul in PENALTY_ROWS
] + [
    # Player-snaps by position group per team-game on plays from scrimmage: the group's
    # men per snap over the plays with a participation row, times the plays from
    # scrimmage a team runs, so a play the participation feed missed still counts its
    # twenty-two.
    (
        "snaps." + group,
        f"{group} player-snaps per team-game, plays from scrimmage",
        PLAY,
        1,
        (lambda g: lambda c: div(c["snaps:" + g], c["groupSnaps"]) * div(c["scrimmage"], 2 * c["games"]))(group),
    )
    for group, _ in POSITION_GROUPS
] + [
    # The two margin rows, appended rather than placed beside the scoreboard rows they
    # belong with. Every row's standard error is bootstrapped from one generator in this
    # list's order, so a row inserted in the middle reshuffles the draws of every row below
    # it and moves bands nobody meant to move. Order here is a stream, not a contents page.
    ("gamesBy14plus", "games decided by 14 or more %", PLAY, 1, share("by14", "games")),
    (
        "marginSigma",
        "standard deviation of the point differential",
        PLAY,
        1,
        lambda c: math.sqrt(
            max(
                0.0,
                div(c["differentialSquared"], c["games"])
                - div(c["marginHomeWon"] - c["marginAwayWon"], c["games"]) ** 2,
            )
        ),
    ),
] + [
    # The count-advantage buckets the two rows above this list do not cover, appended for
    # the same reason they were: the draws below a new row in this stream belong to the
    # rows that were already here, and inserting these beside `ypcEvenCount` would move
    # every band under it by a digit for no reason anybody could name.
    #
    # `plusOne` is where first-and-ten running now happens once nickel is the base answer
    # to eleven personnel: a tight end or a second back against five defensive backs
    # outnumbers the box by one. The share rows say how much of the sport each bucket is,
    # which is the only way to read a bucket's absence from a run as rare rather than as
    # broken.
    ("ypcOutnumberingByOne", "yards per carry, outnumbering by one, first and ten (box = 11 - DBs)", PLAY, 1, lambda c: div(c["ypcYards:plusOne"], c["ypcCarries:plusOne"])),
    ("ypcOutnumberingByOneBox", "yards per carry, outnumbering by one by defenders in box", PLAY, 1, lambda c: div(c["ypcBoxYards:plusOne"], c["ypcBoxCarries:plusOne"])),
    ("ypcShareOutnumberedByOne", "share of first-and-ten designed carries outnumbered by one %", PLAY, 1, share("ypcCarries:minusOne", "ypcFirstAndTen")),
    ("ypcShareEvenCount", "share of first-and-ten designed carries at an even count %", PLAY, 1, share("ypcCarries:even", "ypcFirstAndTen")),
    ("ypcShareOutnumberingByOne", "share of first-and-ten designed carries outnumbering by one %", PLAY, 1, share("ypcCarries:plusOne", "ypcFirstAndTen")),
] + [
    # Completions that lose yardage, appended at the end of the stream for the reason the
    # two blocks above it were: every row's standard error is bootstrapped from one
    # generator in this list's order, so a row inserted anywhere but the end reshuffles the
    # draws of every row below it and moves bands nobody meant to move. Verified rather
    # than assumed for this addition -- the derivation was run before and after it and the
    # 133 rows that were already here printed identically, to the digit.
    #
    # None of the three is a row in `Targets.swift`, and none should be made one without
    # the decision being taken on purpose: a row there is a promise `simharness` prints a
    # verdict for on every run. What these are for is stated in
    # docs/reference/calibration-sources.md — a sourced figure the engine can be read
    # against by hand — and an engine that reads outside them is a finding for the retune,
    # not a reason to invent a target here.
    #
    # The mean loss is negated so the row prints a positive magnitude. The band policy
    # floors a low bound at zero, which would make nonsense of a band around a negative
    # mean; the component underneath stays signed, because that is the arithmetic the
    # accumulator exists to keep honest.
    ("completionsNegative", "completions that lose yardage, share of completions %", PLAY, 1, share("completionsNegative", "completions")),
    ("completionsNegativePerGame", "completions that lose yardage per game, both teams", PLAY, 2, per_game("completionsNegative")),
    ("completionNegativeYards", "yards lost per completion that loses yardage (positive magnitude)", PLAY, 1, lambda c: -div(c["completionNegativeYards"], c["completionsNegative"])),
    # Target share by position group, appended for the reason the two lists above were:
    # every row's standard error is bootstrapped from one generator in this list's order,
    # so a row placed beside the passing rows it reads with would reshuffle the draws of
    # every row below it and move bands nobody meant to move.
    #
    # The three do not sum to 100: the residue is `targets:other` and the groups no
    # offence throws to on purpose — a lineman or a man the feed lists at a defensive
    # position, about three targets in a thousand. The denominator is every target the
    # join resolved, so each share is what it says it is rather than a share of the three.
    ("targetShare.wideReceiver", "targets to wide receivers, share of targets %", PLAY, 1, share("targets:receiver", "targets")),
    ("targetShare.tightEnd", "targets to tight ends, share of targets %", PLAY, 1, share("targets:tightEnd", "targets")),
    ("targetShare.runningBack", "targets to backs, share of targets %", PLAY, 1, share("targets:backfield", "targets")),
] + [
    # The rows the harness had printed without a band. Appended at the end of the stream
    # for the reason every block above was: each row's standard error is bootstrapped from
    # one generator in this list's order, so a row placed beside the rows it reads with
    # would reshuffle the draws of every row below it and move bands nobody meant to move.
    ("sacksPerPressure", "pressured dropbacks ending in a sack %", PLAY, 1, share("pressuredSacks", "pressured")),
    ("redZoneTripsPerTeamGame", "red zone trips per team-game", PLAY, 2, per_team_game("redZoneDrives")),
    ("twoPointTriesRun", "two-point tries carried in, per team-game", PLAY, 3, per_team_game("twoPointRuns")),
    ("twoPointTriesPass", "two-point tries thrown, per team-game", PLAY, 3, per_team_game("twoPointPasses")),
    ("outOfBoundsShare", "plays ending out of bounds, share of plays ending down or out of bounds %", PLAY, 1, share("endedOutOfBounds", "endedDownOrOut")),
    ("outOfBoundsShareTrailingLate", "plays ending out of bounds, trailing inside two minutes, share of plays ending down or out of bounds %", PLAY, 1, share("lateEndedOutOfBounds", "lateEndedDownOrOut")),
    ("puntTouchbacksFromPlusTerritory", "punts from inside the opponent's 45 ending in a touchback, share of those punts %", PLAY, 1, share("plusTerritoryTouchbacks", "plusTerritoryPunts")),
] + [
    # Run share by down-and-distance bucket, the nine buckets `DownAndDistanceClass`
    # splits second, third and fourth down into. Appended last, and in the fixed order of
    # `RUN_SHARE_BUCKETS`, for the same reason.
    (
        "runShare." + bucket,
        f"designed runs on {label}, share of run-or-pass calls %",
        PLAY,
        1,
        share("runs:" + bucket, "calls:" + bucket),
    )
    for bucket, label in RUN_SHARE_BUCKETS
] + [
    # Returns that lose yardage. Appended after every block above, and last of all, for
    # the reason each of them gives: one generator bootstraps every row's standard error
    # in this list's order, so a row inserted beside the kicking rows it reads with would
    # reshuffle the draws of every row below it and move bands nobody meant to move.
    #
    # None of these is a `Targets.swift` row and none is meant to become one without
    # somebody asking: the harness prints no verdict for them. They are the sourced left
    # tail of the return, recorded in the shape of the rows above so that whoever grades
    # one does not have to derive it again. The mean loss is negated so the row prints a
    # positive magnitude, exactly as the completion row above it does, and the component
    # underneath stays signed.
    #
    # Punt and kickoff are kept apart because they are not the same event: a punt returner
    # fields it with the coverage on top of him and a kickoff returner has twenty yards of
    # runway, and the release says so -- the kickoff share is near zero in every season
    # here while the punt share is two to three in a hundred.
    ("puntReturnsNegative", "punt returns that lose yardage, share of punt returns %", PLAY, 2, share("puntReturnsNegative", "puntReturns")),
    ("puntReturnNegativeYards", "yards lost per punt return that loses yardage (positive magnitude)", PLAY, 2, lambda c: -div(c["puntReturnNegativeYards"], c["puntReturnsNegative"])),
    ("puntReturnsPastTheBound", f"punt returns losing more than {LOSS_BOUND} yards, share of punt returns %", PLAY, 3, share("puntReturnsPastTheBound", "puntReturns")),
    ("kickoffReturnsNegative", "kickoff returns that lose yardage, share of kickoff returns %", PLAY, 2, share("kickoffReturnsNegative", "kickoffReturns")),
    ("kickoffReturnsPastTheBound", f"kickoff returns losing more than {LOSS_BOUND} yards, share of kickoff returns %", PLAY, 3, share("kickoffReturnsPastTheBound", "kickoffReturns")),
]


def bootstrap_error(games, metric, rng):
    ids = list(games.keys())
    values = []
    for _ in range(BOOTSTRAP_REPS):
        # `sum_components`, not a Counter fold, for the reason given there. The generator
        # draws exactly `HARNESS_GAMES` times in the order it always did, so the stream
        # this rng hands the rows below it is unchanged.
        total = sum_components(games[rng.choice(ids)] for _ in range(HARNESS_GAMES))
        value = metric(total)
        if not math.isnan(value):
            values.append(value)
    return statistics.pstdev(values) if len(values) > 1 else float("nan")


def round_out(low, high, decimals):
    scale = 10**decimals
    return math.floor(low * scale) / scale, math.ceil(high * scale) / scale


ROSTER_SEASONS = [2023, 2024, 2025]
# A club's opening roster: week 1 of the regular season, the active list plus that week's
# inactives — the fifty-three it carries — and never the practice squad, which is DEV.
ROSTER_STATUS = {"ACT", "INA"}


def week_one_roster(directory, season):
    """Every man on an opening roster in a season, from the weekly roster release."""
    path = os.path.join(directory, f"roster_weekly_{season}.csv")
    with open(path, newline="") as handle:
        return [
            row
            for row in csv.DictReader(handle)
            if row["game_type"] == "REG"
            and row["week"] == "1"
            and row["status"] in ROSTER_STATUS
        ]


def roster_age(row, season):
    """Age on 1 September of the season, the way a week-1 roster page prints it."""
    birth = row.get("birth_date") or ""
    if len(birth) < 10:
        return None
    year, month, day = int(birth[0:4]), int(birth[5:7]), int(birth[8:10])
    return season - year - (1 if (month, day) > (9, 1) else 0)


def rosters(directory):
    """The world's own bands: what a roster is made of, rather than what a game does.

    Nothing here is a row in `Targets.swift` — the harness plays games and never looks at
    a roster's shape — so the band this prints lives in the test that measures it. See
    docs/reference/calibration-sources.md, "Bands the harness cannot measure".
    """
    shares = []
    print("season\tmen\tfirst-season\tshare\tmean age\tage sd")
    for season in ROSTER_SEASONS:
        men = week_one_roster(directory, season)
        rookies = sum(1 for row in men if row["years_exp"] == "0")
        share = rookies / len(men)
        shares.append(share)
        ages = [age for age in (roster_age(row, season) for row in men) if age is not None]
        print(
            f"{season}\t{len(men)}\t{rookies}\t{share:.4f}"
            f"\t{statistics.mean(ages):.2f}\t{statistics.pstdev(ages):.2f}"
        )

    # The band policy, with the 5%-of-the-mean margin: the measurement the test makes is
    # eight generated leagues of 1,696 men, whose standard error is smaller than that, so
    # the 5% governs and the second half of the policy does not bind.
    mean = sum(shares) / len(shares)
    low, high = round_out(min(shares) - 0.05 * mean, max(shares) + 0.05 * mean, 3)
    print(f"first-season share band\t{low:.3f}\t{high:.3f}\tseasons {'+'.join(map(str, ROSTER_SEASONS))}")


# --- the self-test ----------------------------------------------------------
#
# `sum_components` is the whole derivation's arithmetic: every band on file is a ratio of
# the sums it returns. Its failure mode is silent -- a dropped key reads back as 0 and
# nothing raises -- so it gets a test of its own, in the shape `scripts/lint-sim.sh
# --self-test` uses. It needs no data set, so CI can run it.


def self_test():
    """Sum a signed series, the case a counting accumulator gets wrong.

    Marked `shared ground` are the cases a `Counter` fold also gets right; every other
    case here is red under one.
    """
    failures = 0

    def check(name, got, want):
        nonlocal failures
        ok = got == want
        if not ok:
            failures += 1
        print(f"{'ok  ' if ok else 'FAIL'}  {name}")
        if not ok:
            print(f"          expected {want!r}")
            print(f"          got      {got!r}")

    # The case this test exists for: a partial sum that dips below zero on the way up.
    # A counting accumulator drops the key at the dip and restarts, so it reports 8.
    swings = [{"edge": -3.0}, {"edge": 10.0}, {"edge": -2.0}]
    check("a signed series whose partial sum goes negative is carried", sum_components(swings)["edge"], 5.0)

    # Negative in every part -- sack yardage is -- so a counting accumulator never lets the
    # key exist at all and the metric above it reads a clean, wrong 0.
    always = [{"sack": -20.0}, {"sack": -31.0}, {"sack": -14.0}]
    check("a component negative in every part survives", sum_components(always)["sack"], -65.0)

    check("a lone negative part is carried", sum_components([{"d": -4.0}])["d"], -4.0)

    # A total that ends non-positive, reached from above: -3, not a missing key.
    check("a total that ends below zero is carried", sum_components([{"d": 5.0}, {"d": -8.0}])["d"], -3.0)

    check("shared ground: counting is unchanged", dict(sum_components([{"n": 1, "g": 1}, {"n": 2}, {"g": 3}])), {"n": 3, "g": 4})
    check("shared ground: a component no part mentions reads 0", sum_components([])["absent"], 0)
    check("shared ground: a total of exactly zero reads 0", sum_components([{"d": 4.0}, {"d": -4.0}])["d"], 0.0)

    # A per-game part as `read_season` actually builds one: flags that are 0 for this game
    # sitting beside the signed component. The flags must not disturb it.
    games = [
        {"games": 1, "tie": 0, "homeEdge": -7.0, "sackYards": -31.0},
        {"games": 1, "tie": 0, "homeEdge": 3.0, "sackYards": -12.0},
    ]
    folded = sum_components(games)
    check("a game-shaped part: the signed components survive beside zero flags", (folded["homeEdge"], folded["sackYards"], folded["games"], folded["tie"]), (-4.0, -43.0, 2, 0))

    # The control. Everything above is an assertion about `sum_components`; this one is an
    # assertion about the accumulator it must never be written as, so that the cases above
    # are known to be capable of going red rather than merely observed to be green.
    trap = sum((Counter(part) for part in swings), Counter())
    check("control: a Counter fold really does drop the dip, and so would fail the first case", trap["edge"], 8.0)
    dropped = sum((Counter(part) for part in always), Counter())
    check("control: a Counter fold really does lose an all-negative component entirely", "sack" in dropped, False)

    # --- completions that lose yardage --------------------------------------------------
    #
    # The classification first, then the fold, because the accumulator can be wrong in two
    # independent ways: it can put the wrong plays in, and it can lose the signed yardage
    # on the way up.

    check("a completion for a loss is counted", negative_completion_components(-3.0)["completionsNegative"], 1)
    check("a completion for a loss carries its signed yardage", negative_completion_components(-3.0)["completionNegativeYards"], -3.0)
    check("a completion level with the spot is not a loss", negative_completion_components(0.0)["completionsNegative"], 0)
    check("a completion that gained is not a loss", negative_completion_components(11.0)["completionsNegative"], 0)
    check("a completion that gained contributes no yardage", negative_completion_components(11.0)["completionNegativeYards"], 0.0)

    # A game's worth of completed passes folded the way `read_season` folds them: the count
    # and the signed yardage both survive, and the mean loss is their ratio. Under a
    # counting accumulator the yardage key would be gone -- every part that carries one
    # carries a negative -- and the mean would read 0 with nothing raised.
    caught = [negative_completion_components(y) for y in (12.0, -3.0, 0.0, -1.0, 7.0, -6.0)]
    folded = sum_components(caught)
    check(
        "a game of completions folds to the count and the signed yardage",
        (folded["completionsNegative"], folded["completionNegativeYards"]),
        (3, -10.0),
    )
    check(
        "the mean loss is the ratio of those sums",
        folded["completionNegativeYards"] / folded["completionsNegative"],
        -10.0 / 3,
    )

    # The control, in the shape the controls above use: the fold this must never be written
    # as really does lose the yardage, so the two cases above are known to be able to fail.
    trap = sum((Counter(part) for part in caught), Counter())
    check("control: a Counter fold really does lose the signed yardage entirely", "completionNegativeYards" in trap, False)

    # --- returns that lose yardage ------------------------------------------------------
    #
    # The same two failure modes, plus a third this accumulator has and the completions one
    # does not: it keys on `kind`, so punt and kickoff can be crossed and the result still
    # folds to a plausible number.

    check("a return for a loss is counted", negative_return_components("punt", -3.0)["puntReturnsNegative"], 1)
    check("a return for a loss carries its signed yardage", negative_return_components("punt", -3.0)["puntReturnNegativeYards"], -3.0)
    check("a return put down on the catch is not a loss", negative_return_components("punt", 0.0)["puntReturnsNegative"], 0)
    check("a return that gained is not a loss", negative_return_components("punt", 24.0)["puntReturnsNegative"], 0)
    check("a return that gained contributes no yardage", negative_return_components("punt", 24.0)["puntReturnNegativeYards"], 0.0)

    # The bound's own component. `LOSS_BOUND` is the depth the model clamps at, so exactly
    # that depth is inside it and a yard further is not: an off-by-one here would report a
    # tail the source does not have, which is the number the bound is chosen from.
    check("a loss exactly at the bound is not past it", negative_return_components("punt", -float(LOSS_BOUND))["puntReturnsPastTheBound"], 0)
    check("a loss a yard past the bound is past it", negative_return_components("punt", -float(LOSS_BOUND) - 1)["puntReturnsPastTheBound"], 1)
    check("a return that gained is not past the bound", negative_return_components("punt", 24.0)["puntReturnsPastTheBound"], 0)

    # The kind really does key the components, so a punt cannot be folded into the kickoff
    # share. The two are separate rows because the events are different -- the release puts
    # the kickoff share near zero and the punt share at two or three in a hundred -- and
    # crossing them would read as one plausible middle number.
    kicked = negative_return_components("kickoff", -2.0)
    check("a kickoff return's components are the kickoff's", kicked["kickoffReturnsNegative"], 1)
    check("a kickoff return contributes nothing to the punt count", kicked.get("puntReturnsNegative", 0), 0)

    # A game's worth of punt returns folded the way `read_season` folds them.
    run_back = [negative_return_components("punt", y) for y in (14.0, -2.0, 0.0, -1.0, 6.0, -12.0)]
    folded = sum_components(run_back)
    check(
        "a game of punt returns folds to the count, the signed yardage and the tail",
        (folded["puntReturnsNegative"], folded["puntReturnNegativeYards"], folded["puntReturnsPastTheBound"]),
        (3, -15.0, 1),
    )

    # The control, as above: the fold this must never be written as loses the yardage.
    trap = sum((Counter(part) for part in run_back), Counter())
    check("control: a Counter fold really does lose the return yardage entirely", "puntReturnNegativeYards" in trap, False)

    # --- the target-share join ----------------------------------------------
    #
    # `target_group` is the only accumulator here that reads two feeds at once, and its
    # failure mode is silent in the same way: a join that resolves to the wrong index
    # still returns a position, and a share built on it is wrong by a plausible-looking
    # amount rather than raising. So the cases below fix the *alignment* — that the
    # position comes back from the targeted man's own index — and the two ways the play
    # can have no target at all, which must stay out of the denominator rather than
    # landing in a group.

    def part_of(players, positions):
        return {"offense_players": ";".join(players), "offense_positions": ";".join(positions)}

    # The feed writes both lists sorted by position, so the targeted man is rarely first
    # and never at a fixed index. Each of the three below is at a different one, and every
    # one of them is red if the lookup reads index 0, or the last index, or the wrong list.
    eleven = part_of(
        ["id-cb", "id-wr1", "id-wr2", "id-wr3", "id-rb", "id-te", "id-qb"],
        ["CB", "WR", "WR", "WR", "RB", "TE", "QB"],
    )
    check("a targeted wide receiver is read from his own index", target_group({"receiver_player_id": "id-wr3"}, eleven), "receiver")
    check("a targeted tight end is read from his own index", target_group({"receiver_player_id": "id-te"}, eleven), "tightEnd")
    check("a targeted back is read from his own index", target_group({"receiver_player_id": "id-rb"}, eleven), "backfield")
    # A fullback is a back: the harness counts `.runningBack` and `.fullback` in one row,
    # and `POSITION_GROUPS` folds RB, FB and HB into `backfield`, so both sides agree.
    check("a fullback counts as a back, as the harness's row does", target_group({"receiver_player_id": "id-fb"}, part_of(["id-fb"], ["FB"])), "backfield")

    # Not one of the three groups, and not `None`: it is a target, and dropping it would
    # shrink the denominator the three shares are read against.
    check("a target at a position in none of the three groups is still a target", target_group({"receiver_player_id": "id-t"}, part_of(["id-t"], ["T"])), "offensiveLine")
    check("a target at a code in no group at all reads `other`", target_group({"receiver_player_id": "id-x"}, part_of(["id-x"], ["XX"])), "other")

    # No target: an attempt the feed names no receiver on — a throwaway, a spike, a ball
    # batted down. Out of the numerator *and* the denominator.
    check("an attempt with no receiver named has no target", target_group({"receiver_player_id": ""}, eleven), None)
    check("an attempt with no participation row has no target", target_group({"receiver_player_id": "id-te"}, None), None)
    # The join failing must read as "no target", never as a group: a wrong answer here is
    # a share that moves without anything about the sport moving.
    check("a receiver absent from the participation row has no target", target_group({"receiver_player_id": "id-ghost"}, eleven), None)
    check("lists of different lengths have no target", target_group({"receiver_player_id": "id-wr1"}, part_of(["id-wr1", "id-te"], ["WR"])), None)

    # The band is a ratio of the component sums, as every band here is, so the fold is
    # checked on the shape `read_season` builds: a group's targets over all targets,
    # across games, with the residue in the denominator and in no share.
    folded = sum_components(
        [
            {"targets": 5, "targets:receiver": 3, "targets:tightEnd": 1, "targets:backfield": 1},
            {"targets": 5, "targets:receiver": 3, "targets:tightEnd": 1, "targets:other": 1},
        ]
    )
    check(
        "the three shares are ratios of the folded sums, and the residue is in none of them",
        (
            share("targets:receiver", "targets")(folded),
            share("targets:tightEnd", "targets")(folded),
            share("targets:backfield", "targets")(folded),
        ),
        (60.0, 20.0, 10.0),
    )

    if failures:
        print(f"\ncalibration-sources: self-test FAILED — {failures} case(s).")
        sys.exit(1)
    print("\ncalibration-sources: self-test clean — the accumulator carries signed components.")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        return
    if len(sys.argv) == 3 and sys.argv[1] == "--rosters":
        rosters(sys.argv[2])
        return
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    directory = sys.argv[1]
    rng = random.Random(2030)
    seasons = {}
    sigmas = {}
    betweens = {}
    for season in SEASONS:
        games, sigma, between = read_season(directory, season)
        seasons[season] = games
        sigmas[season] = sigma
        betweens[season] = between
        print(
            f"# {season}: {len(games)} regular-season games; win-total sigma {sigma:.2f}; "
            f"between-club point-differential sigma {between:.2f}",
            file=sys.stderr,
        )

    totals = {season: sum_components(seasons[season].values()) for season in SEASONS}

    print("id\t" + "\t".join(str(s) for s in SEASONS) + "\tse400\tlow\thigh\tseasons\tlabel")
    for identifier, label, sourced, decimals, metric in METRICS:
        values = {season: metric(totals[season]) for season in SEASONS}
        errors = [bootstrap_error(seasons[season], metric, rng) for season in sourced]
        error = max(e for e in errors if not math.isnan(e)) if any(not math.isnan(e) for e in errors) else 0.0
        used = [values[s] for s in sourced if not math.isnan(values[s])]
        if used:
            mean = sum(used) / len(used)
            margin = max(0.05 * abs(mean), 2 * error)
            low, high = round_out(min(used) - margin, max(used) + margin, decimals)
            if min(used) == 0 and max(used) == 0:
                # Nothing observed: the rule of three bounds the rate the sample allows.
                games_in_sample = sum(totals[s]["games"] for s in sourced)
                low, high = 0.0, math.ceil(3 / games_in_sample * 10**decimals) / 10**decimals
            low = max(0.0, low)
            if label.endswith("%"):
                high = min(100.0, high)
        else:
            low = high = float("nan")
        cells = "\t".join(f"{values[s]:.{decimals + 1}f}" for s in SEASONS)
        print(f"{identifier}\t{cells}\t{error:.{decimals + 2}f}\t{low:.{decimals}f}\t{high:.{decimals}f}\t{'+'.join(str(s) for s in sourced)}\t{label}")

    sigma_used = [sigmas[s] for s in PLAY]
    mean = sum(sigma_used) / len(sigma_used)
    print(f"winTotalSigma\t" + "\t".join(f"{sigmas[s]:.2f}" for s in SEASONS) + f"\t-\t{min(sigma_used) - 0.05 * mean:.1f}\t{max(sigma_used) + 0.05 * mean:.1f}\t{'+'.join(str(s) for s in PLAY)}\tspread of team win totals (sigma)")

    # Not a row and no band: the harness plays a rotation rather than a season, so nothing
    # prints a verdict for it. It is here because it is what a generated league's spread of
    # team strength is set from -- see docs/reference/calibration-sources.md.
    between_used = [betweens[s] for s in PLAY]
    mean = sum(between_used) / len(between_used)
    print(f"betweenTeamSigma\t" + "\t".join(f"{betweens[s]:.2f}" for s in SEASONS) + f"\t-\t{min(between_used) - 0.05 * mean:.2f}\t{max(between_used) + 0.05 * mean:.2f}\t{'+'.join(str(s) for s in PLAY)}\tbetween-club spread of point differential (sigma, not a row)")


if __name__ == "__main__":
    main()
