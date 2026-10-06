# Phase 2: Claude Review Response
# STATUS: COMPLETE
# Date: 2026-10-05
# Model: Claude Opus 5.5 (adversarial self-review of its own Phase 1 output)

Scope: all 42 classes in src/ and the 14 in testing/. Two findings were
measured rather than argued (ISSUE 1 by benchmark, the Phase 1 ECF defect by
repro). Line numbers are from the files as compiled for phase1-compile.txt.

---

### ISSUE 1: MML set models in per-tick postconditions are cubic with contracts on
- **LOCATION**: TM_FRAME_BUILDER.build `every_current_process`, `born`, `exited_count` (tm_frame_builder.e:38-40); TM_PROCESS_SOURCE.read_all `unique_identities` (tm_process_source.e:23); every caller of `identities_model`, `born_model`, `samples_model`
- **SEVERITY**: HIGH
- **DESCRIPTION**: `MML_SET.&` runs a linear `has`, copies the storage, and calls `make_from_list`, whose precondition `no_duplicates` is an O(n^2) scan (simple_mml/src/mml_set.e:137-151, 277-295). simple_mml's ECF monitors preconditions. Building one model by repeated `&` is therefore O(n^3). Measured in an F_code `-keep` binary: n=100: 62 ms; n=350: 2,797 ms; n=1000: 65,484 ms. `build` constructs about six such models (two snapshots, two idle sets, the result, born), so at this machine's ~350 processes one tick would cost about 17 s in any contract-on binary; at the 5,000-process target (R-4), hours. The F_code test binary, the spike O-2 fat build, and any `-keep` build are all contract-on.
- **SUGGESTION**: (a) Rewrite hot-path frame conditions as O(n) checks over the existing hash tables, for example `Result.activity_count = a_current.count - idle_count (a_current)` and `across a_current.samples as ic all ic.id.is_idle_pseudo_process or Result.has_activity (ic.id) end`. Keep the MML model queries for tests and small collections. (b) Upstream W-11 for simple_mml: `extended` should build its result without re-running `no_duplicates` (it just proved absence), and a public bulk creator from a list known unique. That makes MML builds O(n^2), still too slow for 5,000-element postconditions, so (a) is needed regardless.

### ISSUE 2: A wall clock set backward breaks frame ordering
- **LOCATION**: TM_FRAME_BUILDER.build and .discontinuity `span` (tm_frame_builder.e:25, 35, 58, 63); TM_WINDOW.extend `in_order` (tm_window.e:138)
- **SEVERITY**: HIGH
- **DESCRIPTION**: A frame starts at the previous snapshot's UTC. When UTC goes backward (A-109), `end_ticks_for` keeps that frame ordered by using start + duration, but the next frame starts at the current snapshot's real (backward) UTC, before the previous frame's end. `TM_WINDOW.extend` then fails `in_order`, and the Phase 2 recorder (ordered by end time, DR-006) would reject or interleave it. Forward jumps make a one-second frame span an hour of UTC, so coverage collapses for windows across it.
- **SUGGESTION**: Make frame time continuous. The sampler keeps the previous frame's end; the builder takes `a_start_ticks` (the previous end, or the previous snapshot's UTC for the first frame). End = current UTC when |delta UTC - delta monotonic| <= 2 s, otherwise start + duration, with a new `is_clock_adjusted` flag on the frame and a re-anchor of later frames to wall time. Ensure `Result.start_ticks = a_start_ticks`.

### ISSUE 3: A value can be stored under the wrong metric
- **LOCATION**: TM_READINGS.put (tm_readings.e:105-110)
- **SEVERITY**: HIGH
- **DESCRIPTION**: `TM_READING` does not remember its metric, and `put` does not check the reading against `metrics.metric (a_code)`. A 1,500 W value measured as package power can be stored as `cpu.busy_pct`. That breaks the central promise "an impossible number cannot be stored" (DR-002), and decoded recordings depend on it.
- **SUGGESTION**: Precondition `fits_metric: a_reading.is_available implies metrics.metric (a_code).accepts (a_reading.value)`. O(1).

### ISSUE 4: Worker start-up failures never reach the window
- **LOCATION**: TM_SAMPLING_WORKER.run (tm_sampling_worker.e:88-91); TM_FRAME_SLOT
- **SEVERITY**: HIGH
- **DESCRIPTION**: `create l_taskman.make` and `codec.encode_capabilities` run outside any rescue. An exception there ends `run` on the worker's processor. The GUI never calls the worker again (by design), so it never learns; the slot gets no failure text; the window shows an empty screen forever. Separately, the slot cannot say "the worker stopped normally".
- **SUGGESTION**: Do start-up in a rescued routine that reports through `report_failure`. Add `TM_FRAME_SLOT.put_stopped` / `has_stopped`, set when `run` exits for any reason; postcondition of `run`: the slot was told.

### ISSUE 5: Injected sources use the idle identity as "self"
- **LOCATION**: SIMPLE_TASKMAN.make_with_sources (simple_taskman.e:72); TM_SAMPLER.make (tm_sampler.e:30); TM_FRAME_BUILDER `self_unavailable_when_absent` (tm_frame_builder.e:46)
- **SEVERITY**: MEDIUM
- **DESCRIPTION**: "No self" is written as `TM_PROCESS_ID (0, 0)`, which is the idle pseudo-process. A scripted round that includes idle makes `a_current.has (a_self)` true, so the postcondition stops constraining, and an implementation reading the self sample would report idle time (e.g. 3,100%, inside the metric's range) as the tool's own CPU.
- **SUGGESTION**: Make the self identity `detachable` ("unknown") in the sampler and facade, or add `a_self.is_idle_pseudo_process implies` the three self readings are unavailable.

### ISSUE 6: A supported metric can silently read "not supported"
- **LOCATION**: TM_SYSTEM_SOURCE.refresh (tm_system_source.e:26)
- **SEVERITY**: MEDIUM
- **DESCRIPTION**: The postcondition constrains only unsupported metrics. A supported, non-instanced metric left out of `last_readings` reads "not supported" through the absent-entry default, which is false.
- **SUGGESTION**: Add `supported_present: across metrics.codes as ic all (support_of (ic) = Available and not metrics.metric (ic).is_instanced) implies last_readings.has (ic, "") end`.

### ISSUE 7: Reading a metric with the wrong instance form is not flagged
- **LOCATION**: TM_READINGS.reading, .has (tm_readings.e:55, 70)
- **SEVERITY**: MEDIUM
- **DESCRIPTION**: `reading (Cpu_core_busy_pct, "")` silently answers "not supported". That is a caller error, and it surfaces as a wrong word on screen.
- **SUGGESTION**: Add `instance_rule` to `reading`. `has` may stay lenient.

### ISSUE 8: Frame does not tie born and exited to its activities
- **LOCATION**: TM_FRAME.make, .make_decoded (tm_frame.e:48, 131)
- **SEVERITY**: MEDIUM
- **DESCRIPTION**: A born identity need not be an activity; an exited identity may also be an activity; a decoded discontinuity may carry born identities.
- **SUGGESTION**: O(n) postconditions `born_are_activities: across born_list as ic all has_activity (ic) end`, `exited_not_active: across exited_list as ic all not has_activity (ic.id) end`, and `is_discontinuity implies born_list.is_empty`.

### ISSUE 9: Readings models in `put` cost O(n^2) per call
- **LOCATION**: TM_READINGS.put `others_unchanged`, .seal `unchanged` (tm_readings.e:127)
- **SEVERITY**: MEDIUM
- **DESCRIPTION**: Each `put` builds the map model twice; `MML_MAP.updated` is linear, so each build is O(n^2). About 100 puts per frame is about 2 million element comparisons per frame in contract-on builds: tens of milliseconds against a 1% budget.
- **SUGGESTION**: Same approach as ISSUE 1: O(1) frame conditions in `put` (count rule plus the stored reading), the full map frame condition kept in a test.

### ISSUE 10: Machine-specific acceptance tests are mixed with unit tests
- **LOCATION**: TEST_SOURCES (native trusted, package power, temperature, 32 processors), LIB_TESTS live tests
- **SEVERITY**: MEDIUM
- **DESCRIPTION**: These encode facts about JACKJACK. On any other machine (a contributor, CI, publication) they fail for reasons that are not defects.
- **SUGGESTION**: Move them to `TEST_ACCEPTANCE`, run by a separate runner switch or only when COMPUTERNAME is JACKJACK. Keep machine-neutral live tests (self listed, idle listed, clock monotonic) in the unit suite.

### ISSUE 11: Decoded activities clamp negative identity fields
- **LOCATION**: TM_PROCESS_ACTIVITY.make_decoded (tm_process_activity.e:101-103)
- **SEVERITY**: MEDIUM
- **DESCRIPTION**: `.max (0)` silently repairs a damaged recording, the opposite of "invalid, never clamped".
- **SUGGESTION**: Require non-negative parent, session, threads, handles; the codec rejects such a line as malformed and names it.

### ISSUE 12: Budget streak reset after an interval change is unspecified
- **LOCATION**: TM_SELF_BUDGET.assess (tm_self_budget.e:75)
- **SEVERITY**: LOW
- **DESCRIPTION**: Both "double every tick once over" and "double every third tick" satisfy the contract.
- **SUGGESTION**: `streaks_reset_on_change: interval_ms /= old interval_ms implies (over_streak = 0 and under_streak = 0)`.

### ISSUE 13: Decoded newcomer with CPU marked available: result unspecified
- **LOCATION**: TM_PROCESS_ACTIVITY.make_decoded `cpu_refused` (tm_process_activity.e:115)
- **SEVERITY**: LOW
- **SUGGESTION**: `(a_is_new and a_cpu_status = Available) implies cpu_status = Invalid`; same for IO.

### ISSUE 14: self.cpu_pct range is below the largest supported machine
- **LOCATION**: TM_METRICS (tm_metrics.e:44)
- **SEVERITY**: LOW
- **DESCRIPTION**: Maximum 100,000; 1,024 processors x 100 x 1.05 = 107,520 (R-4).
- **SUGGESTION**: Raise to 110,000. Codes and names are unchanged, so no format impact.

### ISSUE 15: Closing twice must not close a PDH handle twice
- **LOCATION**: TM_COUNTER_QUERY.close, SIMPLE_TASKMAN.close
- **SEVERITY**: LOW
- **SUGGESTION**: Phase 4 nulls `handle` after `PdhCloseQuery`; ensure `handle = default_pointer` after close.

### ISSUE 16: Frame and capability decoding share one error field
- **LOCATION**: TM_FRAME_CODEC.decode, .decode_capabilities
- **SEVERITY**: LOW
- **SUGGESTION**: Separate `last_error` and `last_capabilities_error`.

### ISSUE 17: Builder says how many exited, not which
- **LOCATION**: TM_FRAME_BUILDER.build `exited_count` (tm_frame_builder.e:40)
- **SEVERITY**: LOW
- **SUGGESTION**: O(n): `across Result.exited as ic all a_previous.has (ic.id) and not a_current.has (ic.id) end`.

### ISSUE 18: A logger is accepted and never used
- **LOCATION**: SIMPLE_TASKMAN.set_logger
- **SEVERITY**: LOW
- **SUGGESTION**: In Phase 4, log the decisions an unattended run needs (oracle rule "Log every decision"): fallback reason, budget changes, failed reads, discontinuities.

### ISSUE 19: Exact real equality in postconditions binds the formula
- **LOCATION**: make_from_pair `cpu_rate_when_valid`, `io_rate_when_valid`; TM_SELF_BUDGET `share_recorded`
- **SEVERITY**: INFO
- **DESCRIPTION**: These hold only if the body computes with the same expression (`pair_cores`, `a_tick_cost * 100.0 / a_interval`). Intended; noted for Phase 4.

### ISSUE 20: TM_FRAME.make seals its argument
- **LOCATION**: tm_frame.e:43, 126
- **SEVERITY**: INFO
- **DESCRIPTION**: A side effect on an argument, stated by `sealed`. The builder passes a fresh copy, so no caller is surprised. Keep it documented.

### ISSUE 21: No hook yet for decoding older formats
- **LOCATION**: TM_FRAME_CODEC
- **SEVERITY**: INFO
- **DESCRIPTION**: Intent Q8 promises decoders that keep reading older versions. Only TMF1 exists, so nothing is needed until TMF2; record it for P2.

---

## Checklist results

- Weak preconditions: none `True`; ISSUES 3, 7, 11 tighten.
- Postconditions that constrain nothing: stubs satisfy some (aggregate, top_by on empty), which the tests catch; no contract is vacuous by design.
- Invariants: all O(1) (oracle rule); none use MML or `across`.
- Frame conditions: present on every command in the completeness table; ISSUES 1 and 9 change their form, not their presence.
- MML: every collection has a model query; models are pure. ISSUE 1: models must leave the per-tick postconditions.
- State machines: sample set-once groups, sealed readings, slot flags, budget streaks (ISSUE 12) consistent.
- Duplicates: snapshot and frame replace silently by identity (documented); the readings key is unique by construction.
- Creation-time recovery: native falls back with the reason kept; worker start-up does not (ISSUE 4).
- CQS: one documented exception (`add_english`).
- Void safety: compiles void-safe; detachable cells behind `has_*` queries.
- Edge cases: empty frames and windows covered by tests; idle and recycled pids covered; concurrency through the slot only; exception path of the worker loop covered by `safe_tick`, start-up not (ISSUE 4).
