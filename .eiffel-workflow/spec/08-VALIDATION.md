# DESIGN VALIDATION: simple_taskman

Date: 2026-10-03

What this validation is: a document review of steps 1 to 7 against the
research and the ecosystem survey. What it is not: a compile. No Eiffel in
this spec has been compiled; the compiler gate runs when classes are written
(`/eiffel.contracts` onward).

## OOSC2 Compliance

| Principle | Status | Evidence |
|-----------|--------|----------|
| Single Responsibility | ✓ | Each class in the 04 inventory has a one-line responsibility. Wording of readings lives only in `TM_FORMAT`, wording of verdicts only in `TM_SENTENCE_WRITER`, thresholds only in `TM_RULE_THRESHOLDS`, metric names only in `TM_METRICS`, the reading key format only in `TM_READINGS.key`. |
| Open/Closed | ✓ | New sources, rules, stores, restraints, and clocks are new descendants of `TM_PROCESS_SOURCE`, `TM_SYSTEM_SOURCE`, `TM_RULE`, `TM_TRACE_STORE`, `TM_RESTRAINT`, `TM_CLOCK`. New metrics append a code. |
| Liskov Substitution | ✓ | Justification table in 04. Every effective source and store keeps the parent's postconditions; differences (untrusted, read-only, denied) are expressed by parent queries. |
| Interface Segregation | ✓ | Clients of the library see the facade and value classes; the GUI sees the slot and codec; diagnosis sees only `TM_WINDOW`. |
| Dependency Inversion | ✓ | The sampler and facade depend on the deferred sources and clock; `make_with_sources` injects them. Diagnosis depends on no source at all. |

## Eiffel Excellence

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Command-Query Separation | ✓ with two stated exceptions | CQS table in 06. Exceptions: `TM_COUNTER_QUERY.add_english` returns an index; P4 restraints return an outcome receipt. Both are named and justified. |
| Uniform Access | ✓ | `count`, `has_frame`, `nominal_interval_ms`, and status queries are queries whether stored or computed; clients cannot tell. |
| Design by Contract | ✓ | 05 gives preconditions, postconditions with frame conditions, and O(1) invariants for every P1 class and the P2/P3 interfaces. Domain rules DR-001 to DR-020 each map to a contract or schema check. |
| Genericity | ✓ (deliberately unused) | No generic class introduced; `TM_SERIES` is concrete on purpose (D-006). |
| Inheritance | ✓ | IS-A only. Constant holders are reached by `{CLASS}.Constant`, not inherited. `TM_SHARED_METRICS` is the one mixin, used for the per-processor `once` registry. |
| Information Hiding | ✓ | Natives, offsets, buffers, and query handles are `{NONE}`. `TM_READING.stored_value` is exported only to `TM_READING`. |

## Practical Quality

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Void-safe | ✓ | Absence is a status, not Void. Facade creation sets every attribute before any unqualified call. Detachable only for a truly optional value (slot attribute before attach, frame lookup by time, logger). |
| SCOOP-compatible | ✓ | Three handoff classes and three roots use `separate`. Slot routines never block. Worker locks the slot only inside one-call routines. Every blocking external is declared `"C blocking inline"` (C-015). Pattern proven in simple_chat. |
| simple_* first | ✓ | Dependencies table in 07. ISE: base and testing only. No ISE process library (the Toolhelp wrapper is not on the allowed list); our own inline C instead. |
| MML postconditions | ✓ | 11 model queries (05). None used in an invariant. |
| O(1) invariants | ✓ | Every invariant in 05 and 07 compares scalars or counts. |
| No header statics | ✓ | No `Clib` header; system headers only (04, Win32 surface). |
| No console output in library or GUI | ✓ | Library never prints; GUI logs through `log_line`; only CLI and stress targets print. |
| Testable without Windows | ✓ | Scripted sources and manual clock drive every model, sampling, and diagnosis test. |
| Testable on this machine | Partial | Hybrid cores, battery, and temperature can only be tested as "not supported" here (RISK-009). |

## Requirements Traceability

### Functional

| Requirement | Addressed By | Status |
|-------------|--------------|--------|
| FR-001 snapshot | `TM_PROCESS_SOURCE.read_all`, `TM_PROCESS_SAMPLE`, native self-check | ✓ |
| FR-002 identity | `TM_PROCESS_ID.is_equal`, `hash_code` | ✓ |
| FR-003 rates by identity | `TM_PROCESS_ACTIVITY.make_from_pair` precondition; builder `no_rate_across_identities` | ✓ |
| FR-004 per-core CPU, efficiency class | PDH per-core counter; `TM_CPU_TOPOLOGY`; heatmap labels | ✓ |
| FR-005 memory | Metrics 5 to 10; commit derived; DR-007 | ✓ |
| FR-006 disk, volumes | Metrics 11 to 14 | ✓ |
| FR-007 package power | Metric 4, Energy Meter `_PKG` instance, mW conversion | ✓ |
| FR-008 status on every reading | `TM_READING`; `value` precondition | ✓ |
| FR-009 invalid raw values | `make_measured` against range; PDH status; negative deltas invalid | ✓ |
| FR-010 GPU | Metrics 15, 16; slow query; stretch | ✓ (stretch) |
| FR-011 battery | Metrics 18, 19 reserved; not supported here | Deferred, room left |
| FR-012 temperature | Metric 17; not supported here | ✓ (absence path) |
| FR-020 record | `TM_SQLITE_TRACE_STORE`, schema v1 | ✓ (P2) |
| FR-021 bounded tiers | `TM_RETENTION_POLICY`, `TM_FRAME_MERGER`, pinned frames, cap | ✓ (P2) |
| FR-022 what happened | `TM_TRACE_STORE.window`; scrub view | ✓ (P2) |
| FR-023 JSON export | `TM_TRACE_EXPORTER` | ✓ (P2, SHOULD) |
| FR-024 redaction | `TM_TRACE_EXPORTER` option | ✓ (P2, SHOULD) |
| FR-025 replay | Diagnosis consumes `TM_WINDOW`; memory store; codec | ✓ |
| FR-030 classify | Three rules plus none and inconclusive | ✓ (P3); power and hung-app kinds reserved |
| FR-031 culprit (modified: may be a group) | `TM_CULPRIT` | ✓ (P3) |
| FR-032 sentence plus evidence | `TM_VERDICT`, `TM_SENTENCE_WRITER`; invariant `found_has_evidence` | ✓ (P3) |
| FR-033 inconclusive | `make_inconclusive`; diagnostician postcondition | ✓ (P3) |
| FR-034 felt lag | Metric 20; `TM_LAG_PROBE` after spike | Designed for; spike pending |
| FR-035 contracts and incidents | `TM_CONTRACT`, `TM_WATCHMAN`, `TM_INCIDENT`, pinned frames | ✓ (P3, SHOULD) |
| FR-036, FR-037, FR-038 | Room left; W-5 for FR-036 | Deferred |
| FR-040 to FR-046 actions | P4 inventory; restraint contracts in 05 | Inventory level |
| FR-050 headless facade | `SIMPLE_TASKMAN`; test target links only the library | ✓ |
| FR-051 CLI | `taskman_cli`; command classes testable without argv | ✓ |
| FR-052 GUI (modified: slider scrubber) | `TM_APP` and views, phase by phase | ✓ |
| FR-053 self shown | Self readings in `build`; badge on own row; status bar | ✓ |
| FR-054 stress tool | `taskman_stress` | ✓ |
| FR-055 needs administrator | `TM_ACTION_OUTCOME`, `TM_ELEVATION` | Inventory level (P4) |
| FR-056 GUI never blocks | Slot never blocks; lock scope; blocking externals | ✓ |
| FR-057 copies to widgets | `activities` fresh each call; `set_rows` twins; `TM_PROCESS_ROW` | ✓ |
| FR-NEW-001 monotonic durations | `TM_CLOCK.monotonic_ticks`; frame `duration` | ✓ |
| FR-NEW-002 discontinuity | `make_discontinuity`; `Gap_factor`; nominal follows budget | ✓ |
| FR-NEW-003 idle excluded | `is_idle_pseudo_process`; activity precondition | ✓ |
| FR-NEW-004 group culprit | `TM_CULPRIT` | ✓ (P3) |
| FR-NEW-005 service names | Not designed | Open (spike) |
| FR-NEW-006 lossless codec | Hex bits for reals; decode through `make_measured` | ✓ |
| FR-NEW-007 selection by identity | `TM_PROCESS_VIEW` | ✓ |
| FR-NEW-008 no console in library | Layering rule | ✓ |
| FR-NEW-009 reader beside writer | `make_reader`; WAL | ✓ (P2) |
| FR-NEW-010 versioned trace with catalog | `meta` table | ✓ (P2) |
| FR-NEW-011 blocking externals | Win32 surface table, C-015 | ✓ |
| FR-NEW-012 omitted processes stated | `is_complete`, `omitted_processes`, schema column, grid footer | ✓ |

### Non-functional

| Requirement | Design decision | Status |
|-------------|-----------------|--------|
| NFR-001 overhead | Self readings; `TM_SELF_BUDGET` | Designed; measured at P1 gate |
| NFR-002 tick cost | One native call; one PDH collect; GPU on slow query; `Sample_cost_ms` metric | Designed; measured at P1 gate |
| NFR-003 memory | Applies to library and CLI (A-116); GUI target set after measuring | Designed; measured at P1 gate |
| NFR-004 writes | Batched commits, significant processes only | Estimated 11 MB/h; measured at P2 gate |
| NFR-005 size cap | Tiers, cap, incremental vacuum | Estimated 167 MB; measured at P2 gate |
| NFR-006 back-off | `TM_SELF_BUDGET.assess` contracts | ✓ |
| NFR-007 standard user | No elevation in P1 to P3 | ✓ |
| NFR-008 no network | No network code anywhere | ✓ |
| NFR-009 honesty | `value` precondition; `reading_text` postcondition; schema `CHECK`s | ✓ |
| NFR-010 determinism | Injected sources and clock; diagnosis takes a window | ✓ |
| NFR-011 layout robustness | Self-check with bracketing; fallback source | ✓ |
| NFR-012 localization | `PdhAddEnglishCounterW` only | ✓ |
| NFR-013 probe intrusiveness | Null message, abort-if-hung, rate limit | Designed (P3) |

## Risk Mitigations Implemented

| Risk | Mitigation in Design |
|------|---------------------|
| RISK-001 layout change | `TM_NATIVE_PROCESS_SOURCE` self-check; `read_all` requires `is_trusted`; facade falls back and states why |
| RISK-002 lag probe | Probe behind its own class; metric optional; no rule requires it |
| RISK-003 restraint harm | Preconditions for verified identity and protected set; exact undo postcondition; user-initiated only (D-019) |
| RISK-004 sensors vary | Support decided once per metric; capability view; rules declare required metrics |
| RISK-005 overhead | Self readings; budget back-off; slow GPU query |
| RISK-006 wrong verdict | Evidence invariant; inconclusive kind; precedence postcondition; replay tests |
| RISK-007 scope | Phase tags on every class; P4 at inventory depth only |
| RISK-008 antivirus | No driver; least-privilege access rights; signing in P5 |
| RISK-009 untestable hardware | Scripted sources; recorded fixtures from other machines later |
| RISK-010 C statics | No custom header; native state in Eiffel attributes |
| RISK-011 privacy | Redaction on export; no network |
| RISK-012 recorder load | Batched commits; significant processes only; W-4 |
| RISK-013 localization | English counter API |
| RISK-014 rights | Outcome kind `needs_administrator` (P4) |
| RISK-015 stale executable | Gate reads "Error code:" and F_code timestamps, not just "All tests passed" |
| RISK-016 clone look | Capability panel and honest gaps visible in P1 |
| RISK-017 SCOOP in P1 | simple_chat's proven slot pattern; lock scope rule; P1 spike first |

## Open Issues

| ID | Issue | Resolve in |
|----|-------|-----------|
| O-1 | No Eiffel compiled yet. Some skeletons omit bodies. Exact syntax (inspect over qualified constants, `make_from_separate` on separate creation arguments) is unverified until `ec.sh check`. | `/eiffel.contracts` |
| O-2 | P1 spike: worker plus slot feeding a simple_widgets window for one hour, measuring GUI frame time and copy cost of a full frame text (A-117). | Before building views |
| O-3 | W-1 sparkline gaps. Until it lands, trend tiles freeze with a status word. | simple_widgets |
| O-4 | W-4 SQLite blocking declarations. Until then, commit interval is the lever. | eiffel_sqlite_2025, before P2 gate |
| O-5 | Native self-check slack values (4 MB, 16 handles) are judgment calls. | First real run |
| O-6 | `Gap_factor = 5` and `Cpu_tolerance = 1.05` are judgment calls. | P1 tests and soak |
| O-7 | Rule thresholds (85%, 90%, 200 faults/s, 80%) are starting points, not measurements. | P3 acceptance scenarios |
| O-8 | FR-NEW-005 service names for service-host culprits needs a rights spike. | P3 |
| O-9 | GUI memory target (A-116). | P1 gate measurement |
| O-11 | Intent refinements R-1 to R-8 applied 2026-10-04; details in `09-ADDENDUM-INTENT.md`. | Done |
| O-10 | BUILD_STANDARDS.md section 3 names the test target `lib_tests` and folder `test/`; current practice (and this spec) uses `<lib>_tests` and `testing/`. The standard is stale. | Reference doc update, separate from this project |

None of these blocks the next phase; each has a named place where it closes.

## Ready for Implementation

- [x] All requirements traced (42 functional, 12 new, 13 non-functional)
- [x] All risks mitigated or given a named mitigation point
- [x] OOSC2 principles satisfied
- [x] Phase 1 design complete to contract depth; P2 and P3 to interface depth; P4 to inventory depth, by intent
- [ ] Compiled: not yet, by design of this phase

**VERDICT:** READY for `/eiffel.intent`. Phase 1 classes are ready for
`/eiffel.contracts`. The first build step should be spike O-2.

## Class Tally

Counted by script from the inventory tables in `04-CLASS-DESIGN.md`, after
the intent refinements were applied (2026-10-04).

| Group | Classes |
|-------|---------|
| Library, Phases 1 to 3 | 65 |
| Library, Phase 4 (inventory only) | 11 |
| Application targets (GUI, CLI, stress, recorder), excluding test classes | 15 |
