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


def load_participation(path):
    lookup = {}
    with open(path, newline="") as handle:
        for row in csv.DictReader(handle):
            lookup[(row["nflverse_game_id"], row["play_id"])] = row
    return lookup


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
                if flag(row, "return_touchdown"):
                    c["kickReturnTouchdowns"] += 1
            if flag(row, "punt_attempt") and play_type == "punt":
                c["punts"] += 1
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
                    if yards > 0 or flag(row, "pass_touchdown"):
                        c["completionsPositive"] += 1
                if flag(row, "interception"):
                    c["interceptions"] += 1
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
                        if advantage in (-1, 0):
                            key = "even" if advantage == 0 else "minusOne"
                            c["ypcCarries:" + key] += 1
                            c["ypcYards:" + key] += yards
                        box = num(part, "defenders_in_box")
                        if box is not None:
                            advantage_box = blockers - int(box)
                            if advantage_box in (-1, 0):
                                key = "even" if advantage_box == 0 else "minusOne"
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
