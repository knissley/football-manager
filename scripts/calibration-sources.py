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

Input files are the release assets `pbp/play_by_play_<season>.csv.gz` and
`pbp_participation/pbp_participation_<season>.csv` of the nflverse-data project. They are
not checked in (about 20 MB per season compressed).

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
                c["tie"] = 1 if margin == 0 else 0
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
                if flag(row, "return_touchdown"):
                    c["kickReturnTouchdowns"] += 1
            if flag(row, "punt_attempt") and play_type == "punt":
                c["punts"] += 1
                distance = num(row, "kick_distance", 0.0)
                returned = num(row, "return_yards", 0.0)
                c["puntNetYards"] += distance - returned - (20 if flag(row, "touchback") else 0)
                if (
                    row["punt_returner_player_id"]
                    and not flag(row, "punt_fair_catch")
                    and not flag(row, "punt_downed")
                    and not flag(row, "touchback")
                    and not flag(row, "punt_blocked")
                ):
                    c["puntReturns"] += 1
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
    return games, win_sigma


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
    ("puntsReturned", "punts returned, share of punts %", PLAY, 1, share("puntReturns", "punts")),
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
]


def bootstrap_error(games, metric, rng):
    ids = list(games.keys())
    values = []
    for _ in range(BOOTSTRAP_REPS):
        total = Counter()
        for _ in range(HARNESS_GAMES):
            total.update(games[rng.choice(ids)])
        value = metric(total)
        if not math.isnan(value):
            values.append(value)
    return statistics.pstdev(values) if len(values) > 1 else float("nan")


def round_out(low, high, decimals):
    scale = 10**decimals
    return math.floor(low * scale) / scale, math.ceil(high * scale) / scale


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    directory = sys.argv[1]
    rng = random.Random(2030)
    seasons = {}
    sigmas = {}
    for season in SEASONS:
        games, sigma = read_season(directory, season)
        seasons[season] = games
        sigmas[season] = sigma
        print(f"# {season}: {len(games)} regular-season games; win-total sigma {sigma:.2f}", file=sys.stderr)

    totals = {season: sum(seasons[season].values(), Counter()) for season in SEASONS}

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


if __name__ == "__main__":
    main()
