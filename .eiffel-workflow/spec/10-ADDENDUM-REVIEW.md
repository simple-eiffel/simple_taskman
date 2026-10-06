# ADDENDUM: Phase 2 review changes

Date: 2026-10-05. Source: evidence/phase2-claude-response.md, approved by Larry
with these choices: O(n) hash checks for contract cost; continuous timeline
plus flag for clock changes; fix issues 1-11 before /eiffel.tasks.

## Contract changes applied

| Issue | Class | Change |
|-------|-------|--------|
| 1 | TM_FRAME_BUILDER | Frame conditions rewritten O(n) through hash lookups: `every_current_process` (count plus membership), `born_are_the_new_ones`, `exited_exactly`, `system_readings_kept` (TM_READINGS.includes). `idle_identities` removed; `idle_count`, `new_count`, `exited_count` added. |
| 1 | TM_PROCESS_SOURCE | `unique_identities` via `has_unique_identities` (hash table); `has_sample` added. `samples_model` kept for small tests only. |
| 1 | TM_WINDOW | `extend` frame condition O(n) (`earlier_kept`); `aggregate`, `ranked` `pure` as count and last frame. MML form kept in a test. |
| 1 | TM_SERIES | `history_kept`, `oldest_dropped` O(n) via `statuses_list`. |
| 2 | TM_SAMPLER | Continuous timeline: `utc_offset` (>= 0), `last_end_ticks`, `previous_snapshot`, `clock_change`, `Clock_tolerance` (2 s). Postconditions `continuous`, `first_from_wall`, `offset_rule`, `end_rule`, `adjusted_iff_changed`, `gap_rule`; invariant `timeline_on_wall_plus_offset`. |
| 2 | TM_FRAME_BUILDER | `build` and `discontinuity` take the span (`a_start_ticks`, `a_end_ticks`, `a_clock_adjusted`) from the sampler; `end_ticks_for` removed. |
| 2 | TM_FRAME | `is_clock_adjusted`; every creation procedure takes it. TMF1 header gains a `clock_adjusted` field after `discontinuity`. |
| 3 | TM_READINGS.put | Precondition `fits_metric`. |
| 4 | TM_SAMPLING_WORKER, TM_FRAME_SLOT, TM_FRAME_FILE_REPLAYER | Rescued start-up (`started_taskman`), rescued close; slot `put_stopped` / `has_stopped`; `run` ensures `slot_told: stop_reported`. |
| 5 | TM_SAMPLER, SIMPLE_TASKMAN, TM_FRAME_BUILDER | Self identity is `detachable` (Void = unknown); setting the idle identity as self is refused; facade `set_self_id`. |
| 6 | TM_SYSTEM_SOURCE.refresh | Postcondition `supported_present`. |
| 7 | TM_READINGS.reading | Precondition `instance_rule`. |
| 8 | TM_FRAME | `born_are_new_activities`, `exited_not_active`; a discontinuity holds no born or exited identities. |
| 9 | TM_READINGS.put | `others_unchanged` O(n) via `agrees_except`; count rule. MML form kept in a test. |
| 10 | tests | JACKJACK facts moved to TEST_ACCEPTANCE, run only when COMPUTERNAME is JACKJACK. |
| 11 | TM_PROCESS_ACTIVITY.make_decoded | Requires non-negative identity fields; no clamping. |

## MML decision, restated

Still YES: every collection has a model query. Models appear in tests and in
contracts over small collections (readings `seal` and `make_from`,
capabilities). They do not appear in postconditions over process lists or
per-tick paths, where an MML_SET build is cubic with contracts on (measured:
350 elements, 2.8 s; 1,000 elements, 65 s).

## Upstream item added

| ID | Library | Item |
|----|---------|------|
| W-11 | simple_mml | `MML_SET.extended` re-runs `no_duplicates` (O(n^2)) through `make_from_list` after proving absence; build results through an unchecked internal creator, and add a public bulk creator from a list known unique. Makes model builds O(n^2) instead of O(n^3). |

## New risk to verify in spike O-2

Whether `QueryPerformanceCounter` advances while the machine sleeps on this
Windows build. If it does not, a sleep shows up as a forward clock change
(flagged frame) rather than a monotonic gap (discontinuity), and A-110 must
detect sleep from the wall-clock difference instead. Test: sleep the laptop
for a minute during the spike and read both counters.

## Left for the task list (minor)

Issues 12-18: budget streak reset, decoded newcomer CPU status, self.cpu_pct
range for 1,024 processors, double close of the PDH handle, separate decode
error fields, the unused logger. Issue 17 was folded into ISSUE 1's rewrite.
