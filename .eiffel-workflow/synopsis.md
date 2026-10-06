# Synopsis: Phase 2 review of simple_taskman (P1 library)

Date: 2026-10-05. Full findings: evidence/phase2-claude-response.md (21 issues).

## Overall assessment: PASS WITH CONDITIONS

The contracts are sound in shape: O(1) invariants, frame conditions on every
command, one documented CQS exception, honest statuses throughout. Four
problems must be fixed in the contracts before Phase 4 freezes them, because
fixing them later means changing frozen contracts.

## Critical (fix before /eiffel.tasks)

1. **Contract cost (measured).** MML set models in per-tick postconditions
   are cubic with contracts on: 350 elements take 2.8 s to build, 1,000 take
   65 s. The frame builder builds about six, so a contract-on binary would
   take about 17 s per one-second tick on this machine. Fix: O(n) hash-table
   checks in hot-path postconditions; MML models stay for tests and small
   collections; upstream W-11 to simple_mml.
2. **Clock set backward breaks frame order.** The next frame starts before
   the previous one ends; TM_WINDOW and the recorder reject it. Fix: frame
   time continues from the previous frame's end; a disagreement over 2 s
   between wall and monotonic time marks the frame `is_clock_adjusted`.
3. **Wrong-metric values.** TM_READINGS.put does not check the reading
   against the metric it is filed under. Fix: one O(1) precondition.
4. **Silent worker death.** A start-up exception in the worker leaves the
   window empty forever. Fix: rescued start-up that reports through the slot,
   plus a "stopped" flag on the slot.

## Important (fix in the same contract pass)

5. Idle identity (0, 0) doubles as "no self" with injected sources.
6. A supported metric missing from a refresh reads "not supported".
7. `TM_READINGS.reading` accepts the wrong instance form silently.
8. Frame born and exited lists are not tied to its activities.
9. `TM_READINGS.put` model checks cost O(n^2) per call.
10. JACKJACK-specific acceptance tests sit in the unit suite.
11. Decoded activities clamp negative fields instead of refusing them.

## Minor (fix during implementation)

Budget streak reset (12), decoded newcomer status (13), self.cpu_pct range for
1,024 processors (14), double close of the PDH handle (15), shared decode
error field (16), which processes exited (17), the unused logger (18).

## Info

Exact real equalities bind the formula (19); TM_FRAME.make seals its argument
(20); a decoder hook for TMF2 is a P2 item (21).

## Recommended actions before Phase 3

1. Apply issues 1-11 to the contracts; recompile (ec.sh check, then ec.sh test
   from clean); rerun the suite and confirm the same 61 pass.
2. Record W-11 (simple_mml: `&` without re-running no_duplicates; a bulk creator).
3. Then /eiffel.tasks.

## Resolution (2026-10-05)

Approved. Issues 1-11 applied (spec/10-ADDENDUM-REVIEW.md). Clean rebuild,
zero warnings; 67 passed, 40 failed, all 40 on Phase 4 stubs. W-11 recorded
for simple_mml. New spike item: does QueryPerformanceCounter advance during
sleep on this machine.
