# Implementation Tasks: simple_taskman (P1 library)

Date: 2026-10-05. Inputs: src/ (42 classes), approach.md, synopsis.md,
spec/10-ADDENDUM-REVIEW.md. Every `-- Phase 4:` marker in src/ (41 lines) is
covered by exactly one task below.

Rules for every task (Phase 4):
- Contracts are frozen. The only authorized contract edits are in Task 0.
- Gate per task: `ec.sh check`, then `ec.sh test` for the tests target; read
  the output for "Error code:" (the green line lies); paste the real results.
- A task is done when its named tests pass and no previously passing test fails.
- Baseline at the start of Phase 4: 67 passed, 40 failed.
- Per-tick code stays O(n); no MML model in a hot path (review issue 1).

---

## Task 0: Authorized minor contract amendments (review issues 12-16)
**Files:** src/sampling/tm_self_budget.e, src/model/tm_process_activity.e, src/model/tm_metrics.e, src/probe/tm_counter_query.e, src/handoff/tm_frame_codec.e
**Features:** assess, make_decoded, make (catalog), close, decode_capabilities

### Acceptance Criteria
- [ ] 12: `assess` ensures `streaks_reset_on_change: interval_ms /= old interval_ms implies (over_streak = 0 and under_streak = 0)`
- [ ] 13: `make_decoded` ensures `(a_is_new and a_cpu_status = Available) implies cpu_status = Invalid`, and the same for IO
- [ ] 14: `self.cpu_pct` maximum raised to 110_000 (code and name unchanged)
- [ ] 15: `TM_COUNTER_QUERY.close` ensures `handle = default_pointer`
- [ ] 16: separate `last_capabilities_error`; `decode_capabilities` uses it; its postcondition reads it
- [ ] Compiles clean; suite still 67 passed, 40 failed

### Dependencies
None. Done first, so every later task builds on final contracts.

---

## Task 1: Process activity rates
**Files:** src/model/tm_process_activity.e
**Features:** make_from_pair, make_decoded

### Acceptance Criteria
- [ ] Tests pass: one_core_for_two_seconds, counter_running_backward_is_invalid, impossible_rate_is_invalid_not_clamped, missing_group_keeps_the_more_useful_reason
- [ ] Still passing: born_has_no_rates, rate_across_identities_refused, worse_of_order

### Implementation Notes
CPU: both groups available, then `pair_cores` (the exact expression the postcondition uses); `is_possible_cores` gives Available with `stored_cores`, otherwise Invalid. Neither both: `worse_of`. IO the same shape with `is_possible_bps` and `(after - before) / a_seconds`. Memory copied from `a_after` (a gauge). `make_decoded`: accept each group only through the same checks; a newcomer never carries rates (Task 0, issue 13).

### Dependencies
Task 0

---

## Task 2: Series ring buffer
**Files:** src/model/tm_series.e
**Features:** extend

### Acceptance Criteria
- [ ] Tests pass: extend_keeps_value_and_gap, full_series_drops_the_oldest
- [ ] Still passing: new_series_is_empty

### Implementation Notes
Write at `physical (count + 1)` while not full, then increment `count`; when full, overwrite slot `first` and advance `first := (first + 1) \\ capacity`. A missing reading stores status and value 0.0 (invariant keeps gaps value-free).

### Dependencies
None

---

## Task 3: Number formatting
**Files:** src/model/tm_format.e
**Features:** value_text, cores, percent, bytes, bytes_per_second

### Acceptance Criteria
- [ ] Tests pass: watts ("61.2 W"), bytes_are_scaled ("1.2 GB", "512 B"), percent_and_cores ("4.1%", "2.4 cores")
- [ ] Still passing: missing_reading_is_words_for_every_status, status_words_are_not_numbers

### Implementation Notes
One decimal by default; bytes in 1024 steps labelled B, KB, MB, GB, TB, whole bytes without decimals; unit "B/s" goes through `bytes` plus "/s"; "%" has no space; "1 core" singular only for exactly 1.0. Use one rounding helper so every view rounds alike.

### Dependencies
None

---

## Task 4: Heatmap shape
**Files:** src/probe/tm_cpu_topology.e
**Features:** heatmap_columns, heatmap_rows

### Acceptance Criteria
- [ ] Test passes: heatmap_shapes (32: 4 x 8; 1,024: 32 rows)
- [ ] Still passing: flat_index_across_groups, hybrid_detected

### Implementation Notes
Columns = smallest c with c * c >= count; rows = ceiling (count / c). Prime counts give one short row, never an empty one.

### Dependencies
None

---

## Task 5: Frame builder
**Files:** src/sampling/tm_frame_builder.e
**Features:** build

### Acceptance Criteria
- [ ] Tests pass: survivor_gets_a_rate, recycled_pid_is_born_not_rated, idle_is_left_out, self_readings_added
- [ ] Still passing: every TM_FRAME test

### Implementation Notes
One pass over `a_current.samples`: skip idle; survivor (in `a_previous` by identity) gets `make_from_pair` over `duration / Ticks_per_second` seconds; newcomer gets `make_born` and joins born. One pass over `a_previous.samples` for exited (not idle, not in current). Readings: `make_from (a_current.readings)`, then the three self readings (I-008): self CPU = self activity cores x 100 when present with CPU available, otherwise unavailable; private bytes likewise; sample cost = `a_previous_cost` in ms through `make_measured`. All O(n).

### Dependencies
Task 1

---

## Task 6: Top activities
**Files:** src/model/tm_frame.e
**Features:** top_by

### Acceptance Criteria
- [ ] Test passes: top_by_cpu_is_descending_and_measured

### Implementation Notes
Keep the best `a_count` measured activities in a small array sorted by `amount_of` (insertion), O(n * a_count). Ties keep any order (the postcondition uses >=).

### Dependencies
Task 5 (its test builds the frame)

---

## Task 7: Sampler and timeline
**Files:** src/sampling/tm_sampler.e
**Features:** sample

### Acceptance Criteria
- [ ] Tests pass: first_sample_makes_no_frame, second_sample_makes_a_frame, gap_makes_a_discontinuity, failed_process_read_keeps_going, cost_is_measured_on_the_clock, clock_set_back_keeps_frames_ordered, clock_set_forward_returns_to_wall_time, scripted_facade_makes_frames
- [ ] Still passing: interval_outside_bounds_refused, clock_change_rule

### Implementation Notes
t0 := clock.monotonic_ticks; `read_all` (a failure gives an empty sample list); `refresh`; snapshot with the clock's UTC and monotonic ticks. With a previous snapshot: d := `clock_change`; start := `last_end_ticks` or, first time, the previous snapshot's UTC; `utc_offset := (utc_offset - d).max (0)`; end := current UTC + offset; `is_gap` decides discontinuity (supported codes from `system_source.supported_codes`) or build (self from `self_id`, previous cost `last_tick_cost`). Move `last_snapshot_cell` to `previous_snapshot_cell`; count; `last_tick_cost := clock.monotonic_ticks - t0` last.

### Dependencies
Task 5

---

## Task 8: Window aggregation and ranking
**Files:** src/model/tm_window.e, testing/test_window.e
**Features:** aggregate, ranked, measured_seconds

### Acceptance Criteria
- [ ] Tests pass: mean_is_weighted_by_duration, discontinuity_adds_span_not_coverage, peak_metric_takes_the_maximum
- [ ] New test passes: ranked_totals_by_identity (a recycled pid is two entries; CPU total in core-seconds)
- [ ] Still passing: unmeasured_metric_has_zero_coverage, extend tests

### Implementation Notes
Aggregate: over frames, a frame counts when its reading is available; mean weighted by `duration`; peak = maximum; coverage = measured duration / span (span in ticks), clamped to 1.0 against rounding; value through `make_measured` with the metric. Ranked: HASH_TABLE by TM_PROCESS_ID accumulating CPU cores x seconds, peak private bytes for memory, bytes for IO; then a partial sort.

### Dependencies
Task 5 (frames with activities for the new test)

---

## Task 9: Self-budget policy
**Files:** src/sampling/tm_self_budget.e
**Features:** assess

### Acceptance Criteria
- [ ] Tests pass: share_is_cost_over_interval, backs_off_after_three_ticks_over, never_exceeds_the_maximum, speeds_up_after_a_quiet_spell
- [ ] Still passing: budget_starts_fast

### Implementation Notes
`last_share_pct := a_tick_cost * 100.0 / a_interval` (the postcondition's exact expression). Over: under_streak := 0, over_streak + 1; at Over_limit double the interval (capped), count the change, reset streaks (Task 0). Under: mirror with Under_limit, halving (floored).

### Dependencies
Task 0

---

## Task 10: Frame codec
**Files:** src/handoff/tm_frame_codec.e
**Features:** encode, decode, is_well_formed

### Acceptance Criteria
- [ ] Tests pass: round_trip_is_exact, unknown_header_is_refused_with_the_line, impossible_value_decodes_as_invalid
- [ ] New test passes: round_trip_with_activities (survivor, newcomer, exited, discontinuity and clock flags)
- [ ] Still passing: activity_lines_counted

### Implementation Notes
Format in the class note (TMF1 with the clock_adjusted field). Reals as 16 hex digits of their IEEE bits (REAL_64 to NATURAL_64 through a MANAGED_POINTER, no C). Text UTF-8 with \t \n \\ escapes. Decode refuses unknown header, wrong field count, unknown metric code, negative identity fields (issue 11), naming "line N"; values go through `make_measured` and `make_decoded`, so damage yields invalid, never impossible.

### Dependencies
Task 1 (make_decoded)

---

## Task 11: Capability codec and replay files
**Files:** src/handoff/tm_frame_codec.e
**Features:** encode_capabilities, decode_capabilities, frame_texts_in

### Acceptance Criteria
- [ ] Test passes: capabilities_round_trip
- [ ] New test passes: frame_texts_split (three encoded frames in one text come back as three, in order)

### Dependencies
Task 10

---

## Task 12: Topology from the machine
**Files:** src/probe/tm_cpu_topology.e
**Features:** make

### Acceptance Criteria
- [ ] New test passes: live_topology_counts_all_groups (count equals GetActiveProcessorCount (ALL_PROCESSOR_GROUPS) read independently)
- [ ] Contributes to: win_processor_count_matches_windows (after Task 14)

### Implementation Notes
Inline C, system headers only: `GetActiveProcessorGroupCount`, `GetActiveProcessorCount (g)`, `GetLogicalProcessorInformationEx (RelationProcessorCore)` for EfficiencyClass per processor mask. Not blocking.

### Dependencies
Task 4

---

## Task 13: PDH counter query
**Files:** src/probe/tm_counter_query.e
**Features:** make, add_english, collect, values, close

### Acceptance Criteria
- [ ] New tests pass: pdh_adds_a_real_counter (`\Processor Information(_Total)\% Processor Time` gives an index), pdh_refuses_a_bad_path (returns 0, status not ok, count unchanged), pdh_two_collections_give_values (second collection: _Total value valid, 0..100), pdh_close_twice_is_safe
- [ ] pdh.lib links (already in the ECF)

### Implementation Notes
`PdhOpenQueryW`, `PdhAddEnglishCounterW`, `PdhCollectQueryData` (C blocking), `PdhGetFormattedCounterArrayW` with PDH_FMT_DOUBLE (and NOCAP100 for utility), two-call size pattern into a MANAGED_POINTER, instance names UTF-16 decoded; `PdhCloseQuery`, then null the handle (Task 0). Counter handles kept in a SPECIAL [POINTER].

### Dependencies
Task 0

---

## Task 14: Windows system source
**Files:** src/probe/tm_win_system_source.e
**Features:** make (decide_support), refresh

### Acceptance Criteria
- [ ] Tests pass: win_processor_count_matches_windows; acceptance win_capabilities_here (package power available; temperature and battery not supported, with reasons)
- [ ] New test passes: second_refresh_reads_cpu_and_memory (cpu.busy_pct available after two refreshes; mem.available_bytes available on the first)
- [ ] refresh postconditions hold (`unsupported_reads_as_declared`, `supported_present`)

### Implementation Notes
Counter catalog in spec 04 ("Counter catalog"). Instances: skip `_Total` and `g,_Total`; per-core instance names map through `topology.flat_index`; disk busy = 100 - idle; package watts from the `_PKG` instance, mW / 1000; first refresh rates unavailable. Memory: GlobalMemoryStatusEx, GetPerformanceInfo (commit pct derived). Volumes: fixed drives, GetDiskFreeSpaceExW (C blocking). GPU is a stretch goal and stays not supported, with that reason. Every value through `make_measured`; a PDH status that is not valid gives Invalid.

### Dependencies
Tasks 12, 13

---

## Task 15: Documented process source
**Files:** src/probe/tm_documented_process_source.e
**Features:** read_all

### Acceptance Criteria
- [ ] Test passes: documented_read_lists_self
- [ ] New test passes: documented_denies_rather_than_zeroes (some protected process, e.g. pid 4 or csrss, reports Access_denied for a group instead of zeros)

### Implementation Notes
`CreateToolhelp32Snapshot` (C blocking), `Process32FirstW/NextW`; per process `OpenProcess (PROCESS_QUERY_LIMITED_INFORMATION)`, `GetProcessTimes`, `GetProcessMemoryInfo` (PrivateUsage), `GetProcessIoCounters`, `GetProcessHandleCount`, `CloseHandle`. Refusal gives deny_* with Access_denied; image name only (R-7).

### Dependencies
None

---

## Task 16: Native process table and self-check
**Files:** src/probe/tm_native_process_source.e
**Features:** read_all, run_self_check

### Acceptance Criteria
- [ ] Acceptance tests pass: native_table_trusted_here, native_read_lists_idle_and_self
- [ ] Tests pass: live_two_samples_make_a_frame_with_self (own row present in a live frame)
- [ ] New test passes: forced_self_check_failure_falls_back (a test hook that corrupts one offset gives an untrusted source with the field named, and the facade picks documented)

### Implementation Notes
Layout constants already in the class. Read loop: c_query with the buffer; on STATUS_INFO_LENGTH_MISMATCH grow to the returned size plus 25% and retry, at most three times; walk NextEntryOffset; read fields from the MANAGED_POINTER at the offsets; image name from (length, buffer pointer) as UTF-16. Self-check per spec 07 "Self-check": documented reads A, native read, documented reads B; brackets and slacks; `fail_field` names the first failure.

### Dependencies
Tasks 5, 7, 14, 15 (the live frame test needs the whole chain)

---

## Task 17: Replay worker
**Files:** src/handoff/tm_frame_file_replayer.e, testing/test_slot.e
**Features:** run

### Acceptance Criteria
- [ ] New test passes: replay_feeds_the_slot (a three-frame file in the scratch folder, replayer on its own processor at a 50 ms interval; the slot ends with deposited = 3 and has_stopped)
- [ ] New test passes: replay_of_a_missing_file_reports_failure (has_failure and has_stopped)

### Implementation Notes
Read the file with RAW_FILE (base); `frame_texts_in`; deposit one per interval with a blocking sleep; stop on `should_stop`; report failure and `put_stopped` on every exit, with the worker's slot rules (one short call per lock).

### Dependencies
Task 11

---

## Task 18: Library diagnostics (review issue 18)
**Files:** src/simple_taskman.e
**Features:** set_logger, sample, close

### Acceptance Criteria
- [ ] New test passes: logger_records_decisions (a SIMPLE_LOGGER made with `make_to_file` in the scratch folder receives the source kind and fallback reason at set_logger, a failed process read, and a discontinuity)
- [ ] The library never prints (no `print`, no `io.` in src/)

### Implementation Notes
Log only when a logger is attached; one line per decision (oracle rule "Log every decision in unattended runs"). Budget changes are logged by the application's worker, which owns its processor's logger (R-3).

### Dependencies
Task 7

---

## Task 19: Phase 4 gate
**Files:** none new

### Acceptance Criteria
- [ ] `grep -rn "Phase 4" src/` finds nothing
- [ ] Clean `ec.sh test` for simple_taskman_tests: System Recompiled, zero warnings, Eiffel and C
- [ ] `ec.sh check` for simple_taskman_measure: clean (Q7)
- [ ] F_code run on JACKJACK: every test passes, acceptance included
- [ ] Evidence written to evidence/phase4-implement.txt with the pasted output

### Dependencies
Tasks 0-18

---

## Outside Phase 4 (application work, tracked here so it is not lost)

- Spike O-2: TM_APP with the worker, slot, and a simple_widgets window for one hour; scripted 5,000-process frame time; check whether QueryPerformanceCounter advances during sleep (spec 10).
- Upstream W-1 (simple_widgets sparkline gaps) before the P1 gate; W-11 (simple_mml).
- Targets taskman, taskman_cli, taskman_stress added to the ECF with their root classes.
