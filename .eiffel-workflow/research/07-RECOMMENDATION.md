# RECOMMENDATION: simple_taskman

Date: 2026-10-03

## Executive Summary
Build it, and build a *detective*, not a dashboard. The measurement layer is
proven feasible on this machine as a standard user with no driver, and no Eiffel
library provides it today. The differentiator against TMOG is the part TMOG
leaves to the human: a verdict in words, a measured definition of slow, and
remedies that are reversible and verified.

## Recommendation
**Action:** BUILD
**Confidence:** HIGH for the measurement, recorder, and rule-based verdict
(Phases 1 to 3). MEDIUM for the responsiveness probe and proof-by-intervention
(Phases 3 and 4), which rest on one half-validated assumption.

## Rationale
1. **The gap is real.** ISE's process library returns pid, parent, threads,
   priority, and name. Gobo has nothing. simple_system holds static facts.
2. **The hard-looking part is cheap.** Measured here: 349 processes in one call,
   2.48 ms median, 0.94 MB, with the native layout matching the documented API
   exactly. CPU package power at about 61 W, per-process GPU, and GPU memory all
   read through standard counters without elevation.
3. **The honest limits are known.** No CPU temperature without a driver on this
   machine. No battery, no hybrid cores to test against. The design treats
   absence as a typed fact, so this narrows features without breaking any.
4. **The differentiators survive a prior-art check.** Throttling instead of
   killing exists (Efficiency mode, ProBalance). Measuring felt lag exists
   (Microsoft User Input Delay, absent on this client). What no surveyed tool
   does: a worded verdict with evidence, lag as the axis for diagnosis, verifying
   that a remedy worked, machine contracts, and an open replayable trace.
5. **Eiffel is a natural fit, not a handicap.** The two engineering details
   Plummer is proudest of are a precondition and a class invariant here.
6. **The ecosystem carries the rest.** simple_sql for the recorder, simple_widgets
   for the GUI, simple_chart for the terminal, simple_statistics, simple_toml,
   simple_json, simple_cli.

## Proposed Approach

**Phase order revised 2026-10-03 after Larry chose GUI first (D-013).** The
window is the host from Phase 1 and every later phase adds something visible to
it. The library stays headless and tested without a window throughout.

### Phase 1 (MVP part 1): See it move
- Library: `TM_READING` with availability status; `TM_PROCESS_ID` (pid plus creation time); native process table with startup self-check and documented fallback; counter wrapper for per-core CPU, memory, disk, energy, GPU; snapshot and delta model
- GUI application on simple_widgets: process grid, per-core heatmap, sparklines for CPU, memory, disk, and package power; a capability panel that shows unavailable sensors as unavailable
- Sampler on its own SCOOP processor; window receives immutable snapshots
- The tool shows itself and its own overhead
- Thin CLI: `snapshot`, `capabilities`; stress tool target (CPU, memory, disk)
- Gate: FR-001 to FR-009 pass headless; GUI runs one hour inside NFR-001 and NFR-003

### Phase 2 (MVP part 2): Remember
- SQLite recorder with tiers, cap, batched commits, on its own processor
- GUI timeline with a scrubber: drag back to see the grid and graphs as they were
- JSON export with redaction; replay of a recorded window into the model
- Gate: after the stress tool exits, scrubbing back shows it; size estimate replaced by a measurement

### Phase 3 (MVP part 3): Diagnose
- Rule engine and `TM_VERDICT`; rules for CPU saturation, memory pressure, disk saturation, none, inconclusive
- GUI verdict banner with its evidence, and the cause chain from culprit to resource to symptom
- Responsiveness probe spike, then integration if it tracks load
- Machine contracts from TOML; incidents marked on the timeline with pinned evidence
- Gate: three stress scenarios give the right verdict live **and** when scrubbed to after the fact. This is the MVP, and the point where it stops resembling a TMOG clone.

### Phase 4 (Full): Act and prove
- Restraint ladder with receipts and journaled undo; identity-safe terminate
- "Restart as administrator" for actions on services (D-017)
- Controlled experiment, shown as before, during, and after on the timeline

### Phase 5 (Full): Publish
- Fuller CLI (`watch`, `why`, `what-happened`); documentation site, README, CHANGELOG
- Code signing and installer; `/eiffel.ship`

### Phase 6 (Later, each needs its own short research)
- Wait chain, change ledger, disk growth, case-file PDF, LLM narration, power-budget rule, vendor sensors

## Key Features
1. **Verdict first:** one sentence naming bottleneck and culprit, with its evidence.
2. **Flight recorder as SQLite:** query the past with SQL; replay incidents as tests.
3. **Honest readings:** five kinds of "not a measurement", none of them zero.
4. **Identity-safe actions:** pid plus creation time, verified on an open handle.
5. **Felt-lag signal:** maximum foreground pickup delay per interval.
6. **Machine contracts:** declared healthy bounds; violations become incidents.
7. **Reversible restraints with proof:** throttle, measure, restore, report.
8. **Self-budget:** the monitor is bound by an overhead invariant and backs off.

## Success Criteria
- Three scripted stress scenarios each yield the correct bottleneck class and culprit identity.
- The same verdicts are reproduced from recorded data after the stress tool exits.
- No unavailable or invalid reading is ever rendered as a number (test-enforced).
- 1-hour headless run: own CPU at or under 1% of one logical processor, private bytes at or under 50 MB, database growth inside the cap.
- Startup self-check passes on this build and the fallback path passes the same tests when forced.

## Dependencies
| Library | Purpose | simple_* Preferred |
|---------|---------|-------------------|
| base, time, testing (ISE) | Kernel, timing, test framework | No simple_* equivalent; allowed |
| simple_sql | Recorder | YES |
| simple_json | Export, replay fixtures | YES |
| simple_toml | Machine contracts file | YES |
| simple_datetime | Timestamps and ranges | YES |
| simple_statistics | Baselines, percentiles | YES |
| simple_cli, simple_console | Command-line interface | YES |
| simple_chart | Terminal sparklines for `watch` | YES |
| simple_testing | TEST_SET_BASE | YES |
| simple_widgets | GUI, Phase 5 | YES |
| simple_shell | Hidden window and message pump for the probe, if needed | YES |
| simple_pdf, simple_ai_client | Phase 6 only | YES |

Win32 surface (inline C): ntdll (process table), pdh (counters), kernel32
(process times, memory, IO, process information, jobs), user32 (foreground
window, timed message send), psapi.

## Next Steps
1. Run `/eiffel.spec d:\prod\simple_taskman` to turn this research into a specification.
2. Then `/eiffel.intent` to capture refined intent.
3. Continue with the Eiffel Spec Kit workflow.

## Answered by Larry, 2026-10-03
1. **GUI first or detective first?** GUI first. See D-013 and the revised phases above.
2. **Audience.** Personal tool to prove the idea, headed toward a published Eiffel showcase as another simple_* library and product. See D-016.
3. **Priority against simple_treebiz.** Treebiz is on a sidetrack until the week of 2026-10-05. simple_taskman is the current work.

## Confirmed by Larry, 2026-10-03 ("follow your recommendations")
4. **Elevation.** Standard user by default, with "Restart as administrator" for acting on services (D-017).
5. **Name.** `simple_taskman` (D-018).
6. **Automatic restraint.** None in the first release; user-initiated only (D-019).

## Open Questions
1. **A second test machine.** Is there a laptop with a battery, or an Intel hybrid CPU, available for the features this machine cannot exercise? Matters for publication, not for the spec.
