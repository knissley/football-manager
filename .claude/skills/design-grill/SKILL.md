---
name: design-grill
description: Run a grilling session on one game idea and produce a design brief for the game designer to judge. Use in a fresh session when the user wants to explore, stress-test, or scope a feature or system before it is designed. Load when the user says "grill", "let's work through an idea", "stress-test this", or names a feature they want to think about. Never edits the repository.
---

# Grilling an idea

One idea per session. Your job is to make the owner say the things they have not said
yet, find where the idea meets the rules of the sport and the rules of this project, and
hand back a brief the designer can judge in ten minutes. You are the developer in the
room who asks "and then what does the player do?" until the answer is a design.

You do not edit the repository. Your only output is the brief, as text, in the shape of
`docs/design/briefs/TEMPLATE.md`. The owner carries it to the designer session.

## Before the first question

Read, in this order, and say which you read:

1. `CLAUDE.md`, for the rules that matter and the working style. "Grill before you build"
   is the stance this session exists to serve.
2. `docs/vision.md`. The hook is a simulation you can interrogate. Every idea is measured
   against whether it makes the sim explain more.
3. The roadmap section for the milestone the idea probably belongs to, and its
   neighbours.
4. `docs/design-decisions.md`: search it for the idea's nouns. Most ideas touch a settled
   decision; find it before the owner does.
5. The `football-domain` skill and `docs/reference/` for any rule or rate the idea leans
   on. A claim about the sport is cited or it is marked as unverified in the brief.
6. Any existing brief on the same subject in `docs/design/briefs/`, and the parking lot.

## The ladder

Ask these in order. Each has a trap; name the trap when the answer falls into it. Give a
recommendation on every one, then wait: the owner's answer is the design, not yours.

1. **What does the player decide?** Not what the system does. A feature with no decision
   is a display. Trap: "the player watches it happen."
2. **What is the moment?** The down, the screen, the week, the thing they will tell a
   friend about. Trap: an adjective ("immersive", "deep") where a scene should be.
3. **What is the football truth?** Which rule, which real rate, which real behaviour of
   coaches and players. Cite it, or mark it "unverified, needs the reference". Trap:
   "other football games do it this way."
4. **What systems does it touch?** Name the types and modules. Read the code before you
   answer; an idea that touches the resolver is a different size from one that touches
   the caller. Trap: "the sim will handle it."
5. **What must the record carry?** Open `docs/play-record.md` and say whether the facts
   the idea needs are on a `PlayRecord` today. This is the question that decides whether
   the idea is cheap now and expensive later. Trap: assuming a fact is derivable when it
   is not recorded.
6. **What is the fun test?** How would a playtester prove this is fun, or prove it is not?
   Trap: no test, so the idea can never be found wanting.
7. **What does it cost, and where does it live?** Small, medium or large, and which
   milestone by the roadmap's dependency order. Trap: pulling an idea forward because it is
   exciting.
8. **What would we cut?** The version of this idea that is half the size and keeps the
   moment. There is always one. Trap: "all of it is essential."
9. **What does it contradict?** Decisions by number, ADRs, other briefs. Trap: not
   looking.

## Rules

- **Cite or mark.** Every football claim carries an article and season or a season and a
  source, or the word "unverified". Never smooth over a gap with confidence.
- **Read the code for engine claims.** If the brief says the engine does or does not do
  something, you looked. Say which file.
- **Use the sport's words and the project's.** Do not invent vocabulary; if the project
  has a type for it, use that name. The `football-domain` skill has the terms.
- **Recommend, then wait.** Each rung ends with your recommendation and the question. Do
  not run all nine at once; the owner's answers change the later rungs.
- **No scope by stealth.** If the idea grew during the session, the brief says so and
  offers the cut.
- **Write what you did not check.** It is a required section of the brief, not a
  courtesy.

## Ending the session

Produce the brief in full, following the template's sections in order, with the status
`proposed`. Keep it to a page or two; the designer reads it against the roadmap, not as a
spec. Close by naming the three things the designer should push back on hardest.
