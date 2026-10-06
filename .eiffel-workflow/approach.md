# Approach: simple_taskman, Phase 1 library (P1)

Date: 2026-10-05. Sketch of how the 42 P1 classes fit and the order to implement
them in Phase 4. Contracts are frozen after review; this says how to meet them.

## Architecture

```
handoff   TM_SAMPLING_WORKER --deposit--> TM_FRAME_SLOT <--collect-- (TM_APP, later)
          TM_FRAME_FILE_REPLAYER --------^        TM_FRAME_CODEC (text both ways)
facade    SIMPLE_TASKMAN  (chooses native or documented; owns sampler and sources)
sampling  TM_SAMPLER --uses--> TM_FRAME_BUILDER, TM_SELF_BUDGET, TM_CAPABILITIES
probe     TM_NATIVE / TM_DOCUMENTED / TM_SCRIPTED _PROCESS_SOURCE
          TM_WIN / TM_SCRIPTED _SYSTEM_SOURCE --> TM_COUNTER_QUERY, TM_CPU_TOPOLOGY
          TM_SYSTEM_CLOCK, TM_SELF_PROCESS, TM_SELF_CHECK, TM_PATHS
model     TM_READING(S), TM_METRIC(S), TM_PROCESS_ID, TM_PROCESS_SAMPLE,
          TM_SNAPSHOT, TM_PROCESS_ACTIVITY, TM_FRAME, TM_WINDOW, TM_SERIES,
          TM_AGGREGATE, TM_PROCESS_TOTAL, TM_CLOCK, TM_MANUAL_CLOCK, TM_FORMAT
```

Only `probe` has externals; only `handoff` uses `separate`. The
`simple_taskman_measure` target compiles model + probe + sampling alone (Q7).

## Data flow of one tick

1. `TM_SAMPLER.sample` reads `clock.monotonic_ticks` (t0).
2. `process_source.read_all` gives samples (or a stated failure: no samples).
3. `system_source.refresh` gives sealed readings.
4. `TM_SNAPSHOT.make (utc, mono, samples, readings)`.
5. With a previous snapshot: a gap over `Gap_factor` intervals gives
   `builder.discontinuity`, otherwise `builder.build`, which pairs samples by
   identity (survivor: `make_from_pair`; newcomer: `make_born`), lists exits,
   copies readings with `make_from`, adds the three self readings, and seals.
6. `last_tick_cost := clock.monotonic_ticks - t0`.
7. The worker gives the cost to `TM_SELF_BUDGET.assess`, encodes the frame,
   deposits it, sleeps `pause_ms`.

## Implementation order (Phase 4)

Dependencies first; each step ends with its tests turning green.

1. Model computation: `TM_PROCESS_ACTIVITY` rate rules (through `pair_cores`,
   so the exact-equality postconditions hold), `TM_SERIES.extend`,
   `TM_FRAME.top_by`, `TM_FORMAT` numbers, `TM_CPU_TOPOLOGY` heatmap shape.
2. `TM_FRAME_BUILDER.build`, then `TM_SAMPLER.sample` (scripted sources).
3. `TM_WINDOW.aggregate`, `ranked`, `measured_seconds`.
4. `TM_SELF_BUDGET.assess`.
5. `TM_FRAME_CODEC` (frames, then capabilities, then `frame_texts_in`).
6. Probe, live: `TM_CPU_TOPOLOGY.make`, `TM_COUNTER_QUERY` (PDH),
   `TM_WIN_SYSTEM_SOURCE` support probing and refresh, `TM_DOCUMENTED_PROCESS_SOURCE`,
   `TM_NATIVE_PROCESS_SOURCE.read_all`, then its self-check.
7. `TM_FRAME_FILE_REPLAYER.run`.

## Key decisions already made

- A value enters only through `make_measured`; absent readings read "not
  supported"; discontinuities store explicit "unavailable".
- Identity is pid + creation time; rates never cross identities.
- Only text crosses processors; the slot never blocks.
- The budget governs sampling cost, not whole-process CPU (R-1).

## Dependencies

base, testing (ISE); simple_mml, simple_env, simple_logger, simple_testing.
`pdh.lib`. No simple_sql yet (P2).

## Risk areas

- Contract cost: MML set models in per-tick postconditions are cubic with
  contracts on (measured; review ISSUE 1). Must be settled before Phase 4.
- Wall-clock adjustments versus frame ordering (review ISSUE 2).
- Native table offsets in "Reserved" fields: the self-check is the guard.
- PDH rate counters need two collections; first refresh is unavailable.
- Worker failures must reach the slot, or the window sits empty (ISSUE 4).
