# AI play calling

**Status: partly built, sections marked.** A baseline caller runs both sides of the ball
today: it keys off `SituationClass`, picks personnel and packages, decides fourth downs
on a chart, spends timeouts, spikes and kneels. It is deliberately the *floor*, and it is
the same caller for all thirty-two teams. **The coordinator half is not built** — no
opponent model, no tendencies, no adaptation, no gameplan constraints, no coordinator
ratings, and no benchmark. Those sections are labelled `Designed, not built`.

Both sides of the ball. Every heading below that says "coordinator" applies to the
offensive and defensive coordinator alike unless it says otherwise; where the two
genuinely differ, the [defensive section](#the-defensive-coordinator) says how.

The highest-risk system in the project. Because play calling is toggleable at will, the
AI calls most of the snaps in your own career and *every* snap in the other fifteen
games each week. Its quality sets the ceiling on league statistics, quick-sim
credibility, and whether the news feed is reporting on a league that plays good
football.

If delegating feels like losing, the feature dies and the player calls all 1,100 plays
of a season by hand.

## Your coordinator calls the plays

Delegation is a **staff decision**, not an anonymous engine. Your offensive coordinator
makes the calls; your gameplan sets the boundaries he works inside.

```
PlayCaller
├── Gameplan             your weekly constraints — the guardrails
├── CoordinatorProfile   his tendencies and quality — how he decides inside them
├── OpponentModel        what he believes about the other team
└── GameContext          down, distance, score, clock, field position, personnel
      ↓
   PlayCall              play + personnel + tempo
```

*Designed, not built:* of those five, only the call exists — as `OffensiveCall` and
`DefensiveCall`, which carry tempo and the defensive package; the offence's personnel
group is on `Situation`, not on the call. `Gameplan`, `CoordinatorProfile`,
`OpponentModel` and `GameContext` are none of them types; the sections below say what
each is waiting on. What runs today is a baseline caller that reads the situation and
nothing else.

This turns the project's biggest technical risk into a mechanic. A great coordinator
makes simming ahead safe; a bad one is a reason to take the wheel yourself — and a
reason to go hire someone better in the offseason.

### What the offence sends out

**Built.** `PlayCaller.personnel(for:situation:classified:random:)` answers it, and the
answer lands on `Situation` rather than on the call because personnel is public
information: the offence substitutes first, and the defence answers what it sees.

The mix the baseline caller runs is the sport's, and two sourced participation rows set it
between them ([calibration-sources.md](reference/calibration-sources.md), S2, 2023-24).
`row:personnel11` puts eleven personnel — one back, one tight end, three receivers — on
62.3-71.9% of snaps, so that is the grouping a team lines up in. What is *not* eleven
personnel is mostly a second tight end rather than a fourth receiver: `row:snaps.tightEnd`
is 77.1-87.2 tight end player-snaps per team-game against `row:snaps.quarterback`'s
58.9-66.8, which is one a snap by construction, so the sport has more than one tight end on
the average snap. Four and five receivers are what a team sends out when the clock is the
opponent — two minutes and a score down — and not what it sends out on first and ten.

The repository sources no share for twelve personnel itself. What it sources is the tight
end count, so the ordinary-down mix is set from that and from the eleven-personnel band,
and a share for twelve is a consequence of the two rather than an input.

### Gameplan is constraints, not commands

**Designed, not built.** There is no `Gameplan` type; see [gameplan.md](gameplan.md).

Designed in full in [gameplan.md](gameplan.md). You never hand him a script. You set the
room he operates in:

- Run/pass lean as a **range**, not a number, varying by down and field position
- Fourth-down aggression, as a shift in the win-probability threshold
- Tempo preference
- Personnel and formation preferences
- Explicit rules — *never throw deep inside our own 10*, *attack their No. 2 corner*
- Things to avoid entirely this week

A good coordinator uses the room well. A bad one wastes it, or drifts to its edges.
"Overriding his tendencies" means tightening the guardrails until he has no choice.

### What makes a coordinator good

**Designed, not built.** Coordinator identity is two hardcoded `PersonnelID`s, the same
pair for every team in the league, so every team calls plays identically.

The critical rule, and the one that keeps the engine honest:

> **AI quality is decision quality. It never modifies outcomes.**

A bad coordinator does not roll worse dice. He makes *worse choices with the same
information* — runs on 3rd-and-8, abandons a working run game, kicks a field goal on
4th-and-1 from the 35. The play he calls then resolves through exactly the same physics
as anyone else's. This is the same principle as
[coach skills affecting information and staff but never the field](design-decisions.md).

```
CoordinatorProfile
  playCallingQuality    how close his choice sits to the WP-optimal one, given his info
  tendencyBias          personality: run-heavy, aggressive, conservative, gimmicky
  adaptability          how fast he updates his read of the opponent mid-game
  situational           strengths and weaknesses by phase — red zone, two-minute, short yardage
```

Personality here is a whimsy surface. A coordinator famous for going for it on fourth
down, one who abandons the run at the first sign of trouble, one who is brilliant in
the red zone and helpless in a two-minute drill — all of it is observable, commentable,
and something the news feed can needle him about.

## Situational football

Football is situational before it is anything else. Third and two is a different sport
from third and eleven, and both change again when you are down four with ninety seconds
left. Every system here reasons about that — both callers, gameplan rules, tendency
tables, analysis, and the news — so **the classification lives in one place**:
`FMCore.SituationClass`.

```
SituationClass
  downAndDistance   firstDown · 2nd/3rd/4th short-medium-long · goalToGo
  field             ownDeep → goalLine
  score             trailing/leading by one, two or three scores, or tied
  time              opening · middle · twoMinuteFirstHalf · thirdQuarter ·
                    fourthQuarter · clockBurn · twoMinuteGame · overtime
```

Short is one to three, medium four to six, long seven or more — the same three widths on
second, third and fourth down. Seven is where the ground stops being a realistic answer
to the distance, which is why `isPassingDown` is **third or fourth and seven or more and
nothing else**: second and eight has a whole extra play behind it, and third and four is
a down the sport runs on constantly.

Plus the reads that are composed from all four and used everywhere: `isMustPass`,
`isClockBurn`, `isDesperation`, `isFourthDownTerritory`, `isHighLeverageForDefense`.

Two properties matter more than the buckets themselves:

**It decides nothing.** It is a description. A gameplan rule, an AI policy and a
post-game report all key off it, which is what stops a tendency report from quietly
contradicting a play-by-play because two systems drew the line at six yards and seven.

**And a caller consumes it as a lean, never as a law.** `isMustPass` says the menu
shrank, not that it is down to one item. The baseline caller therefore leans one way in
*every* down-and-distance bucket and commits in none of them: it throws the great
majority of third and longs and still runs some, and inside two minutes needing points it
throws nearly everything and still runs the occasional draw. Not every bucket gets its
lean from the same place — short yardage and goal to go are answered before the table of
run shares is reached, by a branch that runs a little over two thirds of the time and
throws into the end zone the rest, so their entries in that table are unreachable and
kept only to keep the switch exhaustive. A caller whose share in some
bucket is exactly zero is a caller a tendency table can read off a single snap, and a
defence that has seen the table can stop defending the run for free. The same rule
applies to the other reads: `isDesperation` is true inside two minutes of *either* half,
and the fourth-down chart deliberately treats the two halves differently rather than
acting on the description alike. The run shares themselves are modelling conventions; the
sourced rows in `Tools/simharness` are what grade the balance, and a retune is what moves
them.

### Victory formation, and the arithmetic behind it

The one place where a caller's decision is a piece of clock arithmetic rather than a
lean, so it is written down here rather than left in the code. A knee ends the down in
bounds, so the game clock keeps running and the next snap has to come inside the forty
seconds of the play clock (2025 rulebook, 4-6-1) — every one of which an offence in
victory formation spends. A charged timeout stops the clock until the next snap instead
(4-3-2), so each timeout the defence still holds erases one of those intervals; it has
three a half (4-5-1 Item 1). And nothing extends a period that expires between downs:
4-8-1 extends one only while the ball is in play, and 4-8-2 only for a foul in the down
that expired it.

So, from this down: one knee per down remaining **and one on fourth**, an interval before
each of those snaps after the first, and one more before the snap the offence is already
standing over if the clock is running into it. Take away one interval per defensive
timeout, longest first. If the clock left is no more than that, the lead is safe. The
fourth down's interval counts because the fourth down is a knee too — see below — and a
sequence that stopped a down short would hand the ball to a punter with half a play clock
still on the game clock.

The intervals are not all the same length. The one in front of the snap already on the
board runs against **the play clock actually in force** — twenty-five from the whistle
after a stoppage (4-6-2), forty from the end of a play (4-6-1) — and the two differ by
nine seconds. Every interval after it is a forty, because a knee is an ordinary play that
ends and none of it is one of the stoppages 4-6-2 lists. Counting the first at the
second's length is how a caller kneels on a twenty-five, gets nine seconds less than it
counted on, and has to play the next down after all.

The count never rounds anything up. Counting high hands the other side the ball; counting
low costs one ordinary snap.

Counted this way the decision is **monotone**, which is what makes a knee stick: the clock
the next snap faces is exactly what this knee leaves, and the count falls by exactly as
much, so a lead that can be knelt out on first down can still be knelt out on second. A
count that shrinks faster than the clock kneels twice and then runs an ordinary play,
which is how a won game gets fumbled away. There is no memory in the caller and none is
needed — the arithmetic is what carries the decision forward.

A knee on fourth down is a turnover on downs, so the caller does not take one — except
when the period cannot survive the play clock in front of it. **That exception is a
modelling substitution and not a rule, and it is worth being exact about which.** What
4-6-1 and 4-8-1 give the offence there is the right to let the forty seconds go, take the
delay of game, and end the period with no snap at all; a knee is a snap, so the articles
do not produce one. This engine has no outcome meaning *let the play clock expire*, so
the caller kneels that down instead, and the record carries a down that was never played
— about a fifth of a knee a game. The substitution is what lets the count above include
the fourth down's interval, and it is what an unforeseen stoppage lands on: an injury
timeout between downs takes an interval away that nothing could have planned for, and the
fourth-down knee is where the sequence still ends rather than turning into a punt.

**Nobody spends a timeout into a victory formation**, and the two benches have different
reasons. The offence is about to stand on the ball and has nothing to buy with one. The
defence's case is already inside the count above: it assumes every timeout the defence
holds and still finds the clock exhaustible, so the ball is not coming back and a timeout
spent there only shortens a defeat. Declining also keeps the count honest, because the
count is remade at every down of the sequence and is monotone only while its terms hold
still — a timeout spent inside a sequence the offence has already committed to erases an
interval the count was spending, and leaves the offence a live play short of the whistle
it planned for.

That guard covers every timeout a bench *calls*. It does not cover the two things that
can still take an interval away from a committed sequence, and neither is a caller's to
decline. One is a timeout charged by rule: an injury inside the two minutes charges the
injured team one (4-5-4-a), and it lands wherever the injury does. The other is a
defensive foul, which can move the ball five yards into field goal range mid-sequence and
turn a half that was worth ending into a half worth three points — which is the sport, not
a defect, and the offence is right to stop kneeling and kick. Both are measurable: the
harness prints **knees followed by a live play**, whose target is zero, and it is not
always zero. The residual is
[#101](https://github.com/knissley/football-manager/issues/101)'s to settle, because the
fix is in what the count assumes rather than in what a coach asks for.

None of it applies above the two-minute warning. The warning is a stoppage the defence
is handed for nothing (4-4), so it is a fourth timeout — and a knee taken into it has its
interval truncated at 2:00, which is how a team kneels at 2:01 and then finds it has to
play the down after all. Victory formation starts inside two minutes of a half.

Both halves are worth ending, but not on the same terms, and neither is worth ending from
behind: a snap is the only thing that can still change the scoreboard. Ending the game
then needs a lead, because level the snap can still win it. Ending the half needs a lead
*and* the ball too far out to do anything with, or your own goal line right behind you —
the half is not the game and the points still count, so a team in field goal range plays
for them however comfortable the lead is.

**There is one per snap, not one per sideline.** Like `Situation`, it reads from the
offence's point of view — `isMustPass` means *the team with the ball* has to throw,
whichever bench is asking. The defence reads the same value and draws the opposite
conclusion. A two-minute drill is `isDesperation` to the offence and `isClockBurn` to
the defence: one moment, one description, two jobs. Mirroring a copy with the
differential flipped would be two vocabularies again, and is explicitly wrong.

Situation buckets are also the index the caller uses to shortlist plays, so this is on
the [cost](#cost) path as well as the correctness one.

### Fourth down, and whose range it is

A fourth down is three questions: can this kicker reach, is the kick worth taking against
what a punt buys, and is the down worth keeping. The first two belong to the kicker and are
answered in `PlaceKick`; the third is the caller's chart and is answered in `goesForIt`.

**Range is the kicker's.** It used to be two constants on `BaselineCaller` —
`routineFieldGoal` at 51 and `maximumFieldGoal` at 55 — whose own comment said the baseline
"has no kicker to consult". Both are gone. A club's range is now the man the lineup will
put in the specialist slot: how far his leg reaches, less the four yards between a kick he
would take with a game left to play and one he will try as a half runs out. The old pair is
still in there, in the only form that survives the change — an average leg's reach *is* 55
and his routine range *is* 51, so the league's median kicker kicks from exactly where he
kicked from before, and the change is a spread around him rather than a move of him.

**The caller and the physics are one model.** They used to be two, and that was the real
defect: the make draw read `kickAccuracy` and never `kickPower`, so a leg was worth the
same from twenty yards as from fifty-five, while the caller read neither. A club with a
punter filling in took the same fifty-two yarder as a club with a leg, and the model then
told it the kick was better than a coin flip. `PlaceKick` is now the single curve and both
sides read it — the caller to decide whether to send the unit out, the resolver to draw the
ball — so the conditions arrive in both at once: a wind in his face makes a fifty-two yarder
play longer than fifty-two and shortens the range by exactly that much.

**`goesForIt` did not change, and inherits the aggression.** It already asked whether a
fourth down was worth keeping when a kick was not on offer, so shortening one club's range
turns the fourth-and-short and fourth-and-medium between the opponent's 35 and 45 from a
kick into a play — for the club whose kicker cannot get there, which is what a club with a
poor kicker does. A club with a leg kicks them, as it should.

**What the range does not yet do is bind on the odds.** `PlaceKick.routineOdds` says a
routine attempt needs about even money, and as the curve stands that almost never decides
anything: the fall past the mid-forties leaves an average leg better than even out to
sixty-four yards, which is well past where any leg is sent out for a kick, so reach decides
nearly every attempt. That is the make curve's *level* at long range reading high rather
than the caller reading it wrong, and the level is a retune's to move.

## The defensive coordinator

Structurally identical to the offensive one — same profile shape, same gameplan
mechanism, same opponent model, same benchmark — and **equally toggleable**. You can
call the defense yourself, snap by snap, exactly as you can the offense, including
taking the wheel only for a goal-line stand and handing it back.

### A defensive call is data, not a label

`FMCore.DefensiveCall` is composed, not chosen from a flat list of names, for the same
reason schemes are: the engine reasons about components, and named calls are a
convenience layer generated over the composition.

```
DefensiveCall
  coverage         cover 0/1/2/3, two-man, quarters, match quarters, prevent, run blitz
  rush             three-man · four-man · five/six-man blitz · zone blitz · simulated
  frontAlignment   even · over · under · slanted · bear
  package          base · nickel · dime · quarter · goal line · prevent
  runFit           balanced · aggressive · two-gap · spill · sell out
  disguised        hold the shell until the snap
```

A play designer that produces a call the engine already understands beats an engine
that needs a new case per call.

#### Nickel is the base defence

The package is not a flavour of the call, it is who is on the field, and it follows the
grouping the offence declared. Three receivers get a nickel back, four or five get a dime,
and a grouping with a second back gets the four-back front the sport still calls base —
which is the substitution now, not the default. `row:packageNickel` puts five defensive
backs on 61.6-69.2% of snaps and `row:packageBase` four on 20.2-25.0%
([calibration-sources.md](reference/calibration-sources.md), S2, 2023-24): the two bands do
not overlap, and nickel's floor is above half of every snap played.

A second tight end is the one grouping answered two ways: three snaps in ten of it draw the
fifth defensive back and the rest draw the front. One back is one fewer man to account for
in the running game and one more the defence would rather cover with a defensive back than
with a linebacker, so it is a grouping a defence can answer either way and does.

Three in ten is derived, not sourced, and
[calibration-sources.md](reference/calibration-sources.md#who-is-on-the-field) records the
gap. Base's own band cannot hold if the four-back front answers every heavier grouping:
`row:personnel11` puts eleven personnel on 62.3-71.9% of snaps, so a grouping that is not
eleven personnel is on 28.1-37.7% of them, and the smallest that share can be is larger
than base's largest. At the midpoints of the two bands, 32.9 snaps in a hundred are a
heavier grouping against 22.6 in a four-back front, which leaves 31.3% of the heavier snaps
to a fifth defensive back. Applying it to a two-tight-end grouping alone realises less than
that, because the two-back groupings keep the front.

The mismatch is the point of substituting at all, and it survives where it is a bet rather
than a habit. In short yardage a defence commits to the run against three receivers and
wears the extra receiver when it is wrong; on a down where the offence has to throw, the
sixth defensive back is on offer. What it no longer does is answer eleven personnel from a
four-back front on an ordinary down, which it used to do about a quarter of the time and
which left four defensive backs on a third of every snap played.

One cost of that is worth writing down rather than discovering, and the correction to what
this section used to say about it is worth more. Reserving the four-back front to the
heavier groupings means a first-and-ten carry from eleven personnel never meets a seven-man
box, so `row:ypcOutnumberedByOne` has no carries to measure and prints `n/a` instead of a
number. This section then said that answering a two-tight-end grouping from nickel some of
the time would get the row back. **It does not, and the arithmetic says so.** The row counts
carries where the box has one more man in it than the offence has blockers, and the harness
counts blockers as the five linemen plus every tight end plus every back after the first. A
two-tight-end grouping blocks seven against nickel's six-man box, so it is not outnumbered
by one — it outnumbers by one. The pairings that reach minus one are eleven personnel
against a four-back front, which is the rule the paragraph above removed on ordinary downs,
and four or five receivers against a nickel back, which the package rule answers with a
dime instead. The engine produces neither on first and ten, so the row is structurally
ungradable rather than off band, and getting it back is a change to one of those two rules
rather than to this one.

### Every call gives something up

**Designed, not built.** `CallVulnerability` exists in `FMCore` and nothing in
`FMSimulation` reads it — the resolver never asks what a call concedes. It wants the
spatial engine before a soft spot can honestly be soft.

`CallVulnerability` has **no `none` case**, and that is the design. Cover 3 concedes the
seams. A zone blitz concedes the hot throw. Man concedes crossers. Prevent concedes the
run and everything underneath — *on purpose*, which is why the analysis layer needs to
know: an eight-yard completion on second and fifteen is the defence winning, and a
box score that calls it a good play for the offence is lying.

This is what makes calling a defense a decision rather than a preference, and it is
what gives the interrogation layer something true to say about why a play worked.

### The two-minute drill from the other chair

**Designed, not built.** `isTwoMinuteSound` exists on the call in `FMCore` and no caller
consults it; there is no `situational` coordinator rating to reach for the wrong call
under pressure either.

The scenario the shared vocabulary exists to serve: the opponent is driving to tie, and
you are picking calls against a clock that is working for you. `isTwoMinuteSound` —
enough deep help that the sideline throw is the only cheap one, and a rush that does not
vacate the middle — is a property of the call, and a coordinator with a weak
`situational` rating in that phase will reach for the wrong one under pressure.

Watching that unfold, with the reasoning legible, is the same product as watching your
own drive. Defense is not the half you skip.

### What a bench buys with a timeout

**Built, and it is the baseline caller's.** A timeout is not a play, so it is asked of
both benches before every snap, and three things make one worth spending.

**Stopping the clock on defence.** One score down inside the last five minutes, the
offence in front is spending the whole forty seconds of 4-6-1 between snaps and a timeout
takes one of those away outright, because the game clock then waits for the snap (4-3-2).
Three of them is two minutes of game clock, and they are worth nothing at the whistle: the
allotment is three a half and nothing carries out of one (4-5-1 Item 1). A defence that
waits for the game to be visibly finite arrives at two minutes with three timeouts and a
deficit it has run out of possessions to close. Two scores down the ball has to come back
twice, each timeout buys proportionally less, and they are held for the last three and a
third minutes instead.

**Saving time with the ball.** Inside the last minute of either half, with points still
to get, the offence stops the clock rather than keep a timeout it cannot carry past the
whistle. Points still to get is the mirror of the knee: wherever ending the half is worth
more than a snap the clock is the offence's friend and stopping it is the last thing it
wants. The timeouts go before the spike, because a timeout costs a timeout and a spike
costs a down.

**Saving the play clock.** Which clock the offence faces is the book's — forty seconds
from the end of the previous play (4-6-1), or twenty-five from the Referee's whistle after
an administrative stoppage such as a change of possession, an enforcement, a charged
timeout or the two-minute warning (4-6-2) — and missing it leaves the ball dead for a
delay of game, which is five yards (4-6-4). Five yards decides third and short and fourth
and short and nothing else: on first and ten it is a down replayed with two behind it, and
on first and goal it is a worse goal-line call rather than a lost one. So the offence
spends one when the down is third or fourth and short, when the clock has actually beaten
it, and when the timeout is cheap, which it is outright with the game clock already
stopped and only in a one-score game with it running.

**The bench is asked with the answer in hand, and that is what makes it a decision.**
Whether the offence gets a given snap away inside the clock in force is settled before
either bench is asked — the resolver draws it from the clock, the tempo and the crowd, and
`PlayContext.playClockExpired` carries the verdict — so the question a coach is really put
is *the ball is not going to be snapped in time: five yards, or a timeout?* Spending one
because the clock merely looks tight buys a down that was never in danger, which is what
this rule did when it was first written: the delay-of-game row did not move at all when it
was switched on, 0.84 a game with it and 0.84 without at seed 7 over 400 games. With the
flag on the table the rule is worth measuring instead of arguing about, and what it turns
out to be worth is small — it reaches about one snap in two hundred, because a play clock
is rarely lost on exactly third and short.

**And a timeout leaves the offence set, which is why it now helps.** A charged timeout is
a stoppage the benches asked for and the offence stands through it with the ball, so the
call is in and the grouping is on by the time the twenty-five seconds of 4-6-3-a start;
what is left of them is lining up. Modelled as the interval a hurry-up offence works in —
the book fixes the clock's length and says nothing about how ready anyone is — and it is
the difference between a timeout that helps and one that hurts. Measured over 400 games at
each of two seeds, with everything else held: with the offence counted as set, a delay of
game follows a charged timeout on 0.21 snaps in a hundred at seed 7 and 0.37 at seed 11,
against 0.44 and 0.42 on every other snap; without it, 0.52 and 0.68 — *more* likely than
an ordinary snap, so that stopping the clock to avoid the five yards made the next five
yards likelier. A change of possession leaves the same twenty-five seconds and is
deliberately not treated this way: the side coming on has prepared nothing, which is why
the short clock after one is the tightest interval in the game.

**Icing the kicker is not modelled.** Calling a timeout to freeze a kicker before a field
goal is a real thing a bench does, and no caller here does it: the kick is resolved from
the kicker, the distance, the weather and the snap, and there is no term in it that a wait
could move. Calling for the freeze without modelling the freeze would spend a timeout for
nothing and put it in the timeouts row under a name that was not doing the work.

## The opponent model

**Designed, not built.** The baseline caller has no memory of the game it is in, let
alone of an opponent. Nothing builds a tendency table, and no `PlayRecord` history is
read back into a call.

Each coordinator carries his own belief about the other team, built from what he could
actually have observed.

```
OpponentModel
  tendencies[situationBucket] → distribution over play families
  confidence[situationBucket] → grows with observation count
  personnelTells               what you run from 11 vs 21 vs heavy
  recencyWeighting             this drive ≫ this game > this season > last season
```

It is built from `PlayRecord` history — **another query over the event stream**
([ADR-0007](adr/0007-event-stream-contract.md)), so it costs almost nothing new. The
same tendency data serves three consumers: the AI's decisions, your self-scouting, and
the interrogation layer.

This is the same architecture as player evaluation
([decisions 36–37](design-decisions.md)): every team holds its own noisy model of
everyone else, derived from observable history rather than read from a global truth.
One idea, used twice.

### Adaptation is continuous but rate-limited

In-game observations update the model drive by drive. Run four screens and the defense
starts sitting on screens.

"Within limits" is the coordinator's `adaptability` rating capping how fast his beliefs
move, plus a floor on prior weight so he cannot overreact to a single play. A highly
adaptable coordinator punishes you for repeating yourself within a half; a rigid one
takes until next week.

This creates the loop that makes gameplanning worth doing: establish a tendency, notice
they've keyed on it, break it. That's football, it's measurable, and the interrogation
layer can say plainly *they were sitting on your screen game and you called four more.*

## What each side knows pre-snap

**Designed, not built.** The information rule is the commitment; the machinery is not
here. No tendency model exists to make a prediction from — see
[the opponent model](#the-opponent-model) — and neither caller reads formation, personnel
or motion off the other. What *is* true today is the half that costs nothing: neither
side is shown the other's call.

The defense reads **formation, personnel, and motion** — everything physically
observable — plus **its tendency model's prediction** for this situation from this look.

It never sees the play. The defensive call is a bet, and it can be wrong.

Symmetrically, the offence reads the defensive **shell, personnel and alignment** — and
`disguised` is precisely the dial that degrades that read at a cost. The offence never
sees the coverage rotation before the snap either.

This is deliberate and non-negotiable: if the AI could see your call, every causal
explanation the game offered would be a lie, and explanation is the entire product.

It also makes formation and personnel diversity mechanically valuable. Run everything
from 11 personnel in shotgun and your tendency model is razor sharp — the defense will
eat you, and the interrogation layer will tell you exactly why.

## Replay: snapshot the model

**Designed, not built.** `GameSetup` carries the game, the two teams, the players, the
stadium, the weather, the rules, the seed and whether it is postseason — and no model
snapshot, because there is no model to snapshot. This section is the constraint the
replay format has to satisfy once one exists, and it is recorded now precisely because
retrofitting it would mean reworking the replay format after things depend on it.

A subtle trap. The opponent model derives from prior games, so replaying game *N*
would need the model as it stood then — which derives from games 1…*N*−1, which would
have to be replayed first. Replaying one game would cascade through a whole season.

**The opponent model snapshot is therefore part of `GameSetup`**, and so part of
`initialState` in the replay tuple. It's a small tendency table. Every game replays
independently, and the cascade never exists.

Worth building this way from the start; discovering it later means reworking the replay
format after things depend on it.

## Benchmarking

**Designed, not built.** There is no oracle, no benchmark harness and no measured caller
quality. The baseline caller is the floor a real caller will be measured against, and
nothing measures it yet.

"Is the AI good enough?" has to be a measurement, not a vibe. Three tests, all run
headless in `Tools/simharness`:

**Against an oracle.** Build a win-probability-optimal reference caller that searches
exhaustively. Far too slow for gameplay — but it never plays, it only benchmarks. The
EPA gap between a coordinator and the oracle is an absolute measure of quality, and the
spread of that gap across the league is what makes hiring matter.

**Against a baseline.** A naive caller (fixed run/pass split by down) is the floor.
Any coordinator who can't beat it comfortably is broken, not merely bad.

**Against a human.** The acceptance criterion for the whole feature:

> A good coordinator should finish within **~1 point per game** of a skilled human
> calling every snap.

Some gap is correct — the player's skill should matter, or taking control is pointless.
But beyond about a point a game, delegating becomes a tax and toggle-at-will collapses
into calling everything by hand. A *bad* coordinator should be visibly worse than that,
by three or four points; that spread is what gives coordinator hiring teeth.

## Cost

The caller runs once per play against a [1.5ms budget](match-engine.md#performance-budget)
that is dominated by the tick loop, so it needs to be in the tens of microseconds:

- Situation buckets are precomputed; plays are pre-indexed by bucket.
- Candidate evaluation considers a shortlist, not the whole playbook.
- **Opponent model updates are incremental** — running counts, never a recompute over
  history.

## Build order

1. ✅ `SituationClass` — the shared situational vocabulary, before either caller exists.
2. ✅ `DefensiveCall` — the call as composed data, matching what a playbook entry will be.
3. A baseline caller on **both** sides (fixed distributions by situation bucket) — enough
   for M1's crude engine to produce plausible games.
4. Gameplan constraints and the coordinator profile, offense and defense together.
5. The opponent model from `PlayRecord` history, with recency weighting.
6. In-game adaptation, rate-limited.
7. The oracle and the benchmark harness.
8. Tuning until the human gap lands.

Both sides advance together at every step. Building the offensive caller first and
retrofitting defense produces a defense that exists to lose to it.
