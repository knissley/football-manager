# [C35] The coverage reaches the resolver as one bit, so a run blitz covers like cover 3

**Track:** Crude resolver semantics · **Wave:** 4 · **Size:** medium
**Depends on:** **#39** (PR #230), which is rewriting the technique vocabulary on the same
coverage points; start from the `main` it lands on.
**Where it fits:** `CrudeResolver.swift`'s coverage loop and the read threshold, the same
region as #39, #224 and #186, which run one at a time. **On #49's gate, by the owner's
decision of 2026-09-16**: every pass row the retune will set a level against comes out of
this contest, and a retune done against a resolver that cannot tell prevent from cover 3
is a retune done twice. Order in the region: **#39 → this → #224**.
**Tracker:** #1
**Provenance:** §2 and §5 of `docs/audit-pre-snap-exchange.md` (C34, #229).

## Finding

`DefensiveCall.coverage` is a nine-case enum with `deepDefenders` and
`isPressureCoverage` on it (`DefensiveCall.swift:55-100`). The resolver reads one property
of it, `isMan`, in two places: to pick the defender's rating (`CrudeResolver.swift:447`) and
to label the coverage point (`:465`). `deepDefenders` has no reader in `FMSimulation`.

So every zone shell resolves alike and so does every man shell:

- Prevent, four deep, is as hard to throw deep against as cover 3, one deep, and concedes
  nothing underneath. The caller sends it on 70% of trailing two-minute must-pass snaps
  (`PlayCaller.swift:963-966`).
- `Coverage.runBlitz`, documented as *no coverage call, everyone is playing the run*
  (`:72-73`), has `isMan == false` and is resolved as zone coverage with the zone rating.
  The sell-out call, 62% of short-yardage calls (`:977-978`), is free against a throw.
  `gamelog --seed 7 --home 3 --away 11`, play 69: second and goal from the one, 22
  personnel, nickel under a run blitz, quick pass for the touchdown off an ordinary
  coverage contest.
- Cover zero would resolve as man free. Unreachable today (0.0% of snaps), so latent.
- `CallVulnerability`'s `.quickGame`, `.playAction` and `.theRun` (quarters) cannot be
  true while the shells resolve alike, so M5 will have nothing to wire it to.

**The stream says what the field did not play.** A record that names quarters over a
snap resolved as cover 3 is the fabricated causal chain ADR-0012 warns M2 will be built
against. That is why this lands before M2 whatever happens to the crude resolver at M5.

Rows downstream: `completionPercentage`, `yardsPerAttempt`, `yardsPerCompletion`,
`dropback10plus`, `dropback20plus`, `dropback40plus`, `interceptionRate`, and through the
read clearing later, `pressureRate` and `sackRate` (3.5 / 3.6 against 6.1–7.2 today).

## Plan

1. **Re-measure on the `main` you start from**: completion rate, yards per attempt and
   air-yards distribution *by coverage called*, 400 games, both seeds. Write the table on
   this issue. Expected: flat across shells, by construction.
2. **Establish what a shell means, from a source or as modelling.** Whether the
   participation release carries a coverage type per snap is the first question; if it
   does, derive completion and yards per attempt by man/zone and by deep-defender count
   with `scripts/calibration-sources.py`, citing the MANIFEST line, and band them. If it
   does not, name the shell's effect as modelling in `calibration-sources.md`'s *nothing
   sources* section and in `playing-rules.md`, and say so on the issue before writing code.
3. **The resolver reads the shell.** `deepDefenders` sets the deep read's contest and the
   underneath read's concession; `isPressureCoverage` (cover zero, run blitz) means no
   deep help — a deep read against it is a footrace, and a sell-out that meets a throw is
   exposed. Where it lands — the coverage loop's contest, `Reads.threshold`, or a
   per-read modifier from the read's depth against `deepDefenders` — is the implementer's
   to establish and state. It stays a flat draw over values on the call (rules 1 and 5).
4. **The coverage point's technique agrees with the shell**, extending what #39 lands:
   deep zone and flat zone follow from the shell's structure, not from a coin.
5. **A `.football` test first, committed red**, from the derivation in item 2 if the feed
   has it, else `.pin` with the modelling named: a deep pass against prevent completes
   less often than against cover 3; a throw against a run blitz is not an ordinary
   coverage contest. Verify each can fail by collapsing the shell back to `isMan`.
6. Every moved row reported with its mechanism against its measured floor.

## Done when

- [ ] The by-shell table, before and after, on this issue at both seeds.
- [ ] Prevent and cover 3 resolve differently on a deep read; run blitz and cover 3 resolve
      differently on any read; demonstrated, not asserted.
- [ ] The shell's effect is either sourced with a MANIFEST line or named as modelling, and
      the code comment says which.
- [ ] `DefensiveCall.swift:32-34` and `:114-115` say what `disguised` and `.simulated` do
      today (nothing), or the register carries them (01, item 2).
- [ ] Every moved row reported against its measured floor, with the floor named. Nothing
      retuned; residuals to #49 by comment.

## Not in scope

- **Disguise.** `disguised` stays unread; it is ADR-0015's step 4 and M5's geometry.
- **The blitz rate** (#225) and **what a zone blitz buys** (#224). This issue changes what
  a coverage is worth, not how often it is called or how the rush is built.
- **Retuning any constant** to land the pass rows. If the shells differ and the aggregate
  moves off band, that is a level and it is #49's.
- `CallVulnerability` reaching the resolver. M5.

## Not checked when filing

Whether the participation release carries a coverage classification per snap at all; item
2 finds out, and "it does not" is a legitimate outcome that makes item 3 a modelling call.
Whether #39's technique rewrite already reads `deepDefenders` — its PR carried tests only
when the audit read it. How much of `row:sackRate`'s gap is here rather than in #225's
blitz rate.
