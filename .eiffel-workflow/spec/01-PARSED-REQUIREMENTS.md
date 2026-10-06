# PARSED REQUIREMENTS: simple_taskman

Date: 2026-10-03
Input: `.eiffel-workflow/research/01..07`, `REFERENCES.md`, and
`evidence/hardware-probe-2026-10-03.txt`, all re-read from disk for this step.

## Problem Summary

System monitors report measurements and leave the diagnosis to the human, and
they forget everything when the incident ends. simple_taskman is a *detective*:
it measures honestly, remembers, states a verdict in words with the evidence
behind it, and (later) proves and remedies. It is a personal tool first and a
published simple_* showcase second, with the GUI as the host from Phase 1.

## Scope

### In Scope: MVP (Phases 1 to 3)
- Process table with pid-plus-creation-time identity and per-process rates
- Per-logical-processor CPU, memory pressure, disk activity, volume free space
- CPU package power where the Energy Meter counters exist
- Readings with five-way availability status; no fake zeros anywhere
- Capability report: what this machine can and cannot measure
- Self-measurement of the tool's own overhead, with back-off
- SQLite recorder with tiered retention, time-range query, replay
- Rule-based diagnosis: verdict sentence, culprit identities, evidence, confidence
- GUI on simple_widgets: process grid, per-core heatmap, trend sparklines,
  capability panel (P1); timeline scrubber (P2); verdict banner, cause chain (P3)
- Thin CLI: `snapshot`, `capabilities`
- Stress tool for reproducible CPU, memory, and disk loads
- Headless library facade usable by any Eiffel program

### In Scope: designed for, built later (Phases 3 to 5)
- Foreground responsiveness probe (P3, after its spike)
- Machine contracts from TOML and incidents (P3)
- Per-process GPU (P1 stretch or P3)
- Restraint ladder, identity-safe terminate, journaled undo, experiment (P4)
- Restart as administrator (P4)
- JSON export with redaction (P2), fuller CLI and publication (P5)

### Out of Scope
- Kernel driver; macOS and Linux; malware, handle, DLL inspection; benchmark
  score; fan control; any action on protected system processes; automatic
  restraint (D-019)

### Deferred (leave room, do not design in detail)
- Wait chain, change ledger, disk growth and treemap, case-file PDF, LLM
  narration, power-budget rule, vendor sensor sources, ETW

## Functional Requirements

Source for all rows: `research/03-REQUIREMENTS.md`. Phase column added here.

| ID | Requirement (abridged) | Priority | Phase | Acceptance |
|----|------------------------|----------|-------|------------|
| FR-001 | Snapshot of all processes with identity, name, parent, CPU times, memory, IO, threads, handles | MUST | 1 | Own row equals documented per-process API values |
| FR-002 | Identity = pid and creation time; equality and hash on both | MUST | 1 | Same pid, different creation: not equal |
| FR-003 | Per-process rates as deltas matched by identity | MUST | 1 | Recycled pid carries no rate across identities |
| FR-004 | Per-logical-processor CPU and efficiency class | MUST | 1 | 32 processors, class 0, values 0..100 here |
| FR-005 | Memory: in use, available, commit and limit, hard faults per second | MUST | 1 | commit <= limit postcondition |
| FR-006 | Disk activity per physical disk; free space per volume | MUST | 1 | Stress write raises the right disk |
| FR-007 | CPU package power when counters exist | MUST | 1 | Within 10% of the Power counter; else unavailable |
| FR-008 | Every reading has an availability status | MUST | 1 | Value query has precondition `is_available` |
| FR-009 | Invalid raw values become status invalid | MUST | 1 | Wrapped 1.8e19 value yields invalid |
| FR-010 | Per-process GPU utilization and memory | SHOULD | 1+ | Busiest engine, not sum |
| FR-011 | Battery | COULD | later | Not supported here |
| FR-012 | Temperature | COULD | later | Not supported here; never 0 |
| FR-020 | Record readings and significant processes to SQLite | MUST | 2 | Row set per tick, gaps preserved |
| FR-021 | Bounded, tiered history with size cap | MUST | 2 | Stops growing at cap; downsampled not dropped |
| FR-022 | Query what happened between T1 and T2 | MUST | 2 | Returns the scenario after the stress tool exits |
| FR-023 | JSON export | SHOULD | 2 | Round-trips through simple_json |
| FR-024 | Redaction on export | SHOULD | 2 | Listed fields absent |
| FR-025 | Replay a recorded window through diagnosis | MUST | 2/3 | Same verdict offline as live |
| FR-030 | Classify bottleneck | MUST | 3 | Three loads classified; idle = none |
| FR-031 | Name culprit identities | MUST | 3 | Culprit = stress tool identity |
| FR-032 | Verdict = sentence plus evidence | MUST | 3 | Evidence non-empty and inside window |
| FR-033 | Confidence; inconclusive rather than guess | MUST | 3 | Ambiguous input yields inconclusive |
| FR-034 | Foreground responsiveness, maximum per interval | SHOULD | 3 | Rises when a fixture blocks its UI thread |
| FR-035 | Machine contracts and incidents with pinned evidence | SHOULD | 3 | One incident with start, end, culprit |
| FR-036 | Propose contracts from baseline | COULD | later | None active until accepted |
| FR-037 | Shared power budget detection | COULD | later | Needs GPU power |
| FR-038 | Wait chain | COULD | later | Deferred |
| FR-040 | Graded restraints | SHOULD | 4 | Observable via query API |
| FR-041 | Exact undo with recorded prior state | SHOULD | 4 | Postcondition: state = prior state |
| FR-042 | Actions target an identity and refuse a recycled pid | MUST for any action | 4 | Stale identity refused, nothing changed |
| FR-043 | Protected set refused | MUST for any action | 4 | Precondition; refusal test |
| FR-044 | Controlled experiment | SHOULD | 4 | Three windows and a result |
| FR-045 | Identity-safe terminate | SHOULD | 4 | As FR-042 |
| FR-046 | Restraints released or restorable after a crash | SHOULD | 4 | Journal restore offered on next start |
| FR-050 | Library facade usable without UI | MUST | 1 | Test target links only the library |
| FR-051 | CLI `snapshot`, `capabilities` (P1); more later | MUST | 1 | Captured-output tests |
| FR-052 | GUI delivered incrementally | MUST | 1-3 | Screenshot plus 1-hour run per gate |
| FR-053 | Tool shows itself and its overhead | MUST | 1 | Own CPU share and private bytes shown |
| FR-054 | Stress tool | MUST | 1 | Drives acceptance scenarios |
| FR-055 | "Needs administrator" with relaunch offer | SHOULD | 4 | Message and offer; nothing changed |
| FR-056 | GUI never blocks on sampling, recording, probing | MUST | 1 | Responsive during commit and hung probe target |
| FR-057 | Widgets get copies of row data | MUST | 1 | No invariant violation in 1-hour run |

## Non-Functional Requirements

| ID | Requirement | Category | Measure | Target |
|----|-------------|----------|---------|--------|
| NFR-001 | Sampling overhead | PERFORMANCE | Own CPU over 1 hour at 1 Hz | <= 1.0% of one logical processor |
| NFR-002 | Snapshot cost | PERFORMANCE | Wall time per tick | <= 20 ms at 350 processes |
| NFR-003 | Memory footprint | PERFORMANCE | Private bytes | <= 50 MB headless |
| NFR-004 | Recorder writes | PERFORMANCE | Bytes per hour | <= 20 MB; batched commits |
| NFR-005 | Recorder size | CAPACITY | File size | 250 MB default cap |
| NFR-006 | Self-budget enforcement | RELIABILITY | When NFR-001 exceeded | Interval backs off; event logged |
| NFR-007 | Privilege | SECURITY | Rights for MUST features | Standard user |
| NFR-008 | Privacy | SECURITY | Network use | None |
| NFR-009 | Honesty | CORRECTNESS | Unavailable rendered as number | Zero occurrences |
| NFR-010 | Determinism | TESTABILITY | Diagnosis depends on clock or OS | No; injected |
| NFR-011 | Robustness | RELIABILITY | Native layout mismatch | Detected; fallback |
| NFR-012 | Localization | CORRECTNESS | Counter names | English counter API |
| NFR-013 | Probe intrusiveness | SAFETY | Messages to other apps | Null message only; rate limited |

## Constraints (simple_* First)

| ID | Constraint | Type |
|----|------------|------|
| C-001 | SCOOP-compatible (`concurrency=scoop`); never thread | TECHNICAL |
| C-002 | simple_* over ISE and Gobo where available; ISE base, time, testing allowed | ECOSYSTEM |
| C-003 | Void-safe, `void_safety=all` | TECHNICAL |
| C-004 | Win32 via inline C externals; no .c files | TECHNICAL |
| C-005 | No kernel driver | TECHNICAL |
| C-006 | Build via `ec.sh` only; tests assert through TEST_SET_BASE, never `check` | ECOSYSTEM |
| C-007 | No mutable C statics in headers shared across generated translation units | TECHNICAL |
| C-008 | Windows 10 1809+, x64 | PLATFORM |
| C-009 | US English | STYLE |
| C-010 | Clean rebuild against post 2026-09-28 simple_sql / SQLite | ECOSYSTEM |
| C-011 | **Class invariants must be O(1): no MML models, no `across` over data** (oracle rule, Larry 2026-09-11) | TECHNICAL |
| C-012 | Clean rebuild of client EIFGENs after any supplier library change (oracle rule, 2026-09-10) | ECOSYSTEM |
| C-013 | Test target uses both simple_testing (TEST_SET_BASE) and ISE testing; `testing/test_app.e` runner (oracle Testing Standard) | ECOSYSTEM |
| C-014 | Naming: `a_` arguments, `l_` locals, `al_` attachment locals, `ic_` cursors; domain vocabulary in public features | STYLE |

C-011 to C-014 were added in this step from `oracle-cli check` (run 2026-10-03).

## Decisions Already Made

| ID | Decision | Rationale | From |
|----|----------|-----------|------|
| D-001 | Build in Eiffel with inline C | No Eiffel library has it; surface is small | research/04 |
| D-002 | One repo; clusters probe, model, recorder, diagnosis, action, cli, gui; prefix `TM_` | No second client yet | research/04 |
| D-003 | Native process table primary, self-checked; documented fallback | 2.48 ms for 349 processes; offsets verified | research/04 |
| D-004 | PDH counters through the English-name API | Read power and GPU as standard user | research/04 |
| D-005 | No driver; sensors optional behind a deferred source | Temperature absent here | research/04 |
| D-006 | `TM_READING` object at API boundaries; compact column for series | Reasons for absence matter; avoid garbage | research/04 |
| D-007 | Identity = pid plus creation time; actions verify on an open handle | Free with the table; safe | research/04 |
| D-008 | SQLite recorder; WAL, batched, three tiers, pinned incidents | The trace is a database | research/04 |
| D-009 | Core model sequential; SCOOP processors host sampler, recorder, probe | Determinism plus responsiveness | research/04 |
| D-010 | Deterministic rules decide; statistics for baselines; LLM only narrates | Reproducible from a recording | research/04 |
| D-011 | Null-message probe, maximum per interval | Spike worked; MS argues for max | research/04 |
| D-012 | Restraint ladder EcoQoS, priority, CPU cap; no suspend | Documented and reversible | research/04 |
| D-013 | **GUI first** (Larry) | Showcase needs a moving window | research/04 |
| D-014 | Machine contracts in TOML against a name registry | Editable; typo is a load error | research/04 |
| D-015 | Windows only; probes behind deferred interfaces | Differentiation is diagnosis | research/04 |
| D-016 | Personal tool, then published simple_* showcase (Larry) | Sets shipping standards | research/04 |
| D-017 | Standard user; "Restart as administrator" on demand (Larry confirmed) | 150 of 339 refuse throttling | research/04 |
| D-018 | Name `simple_taskman`, facade `SIMPLE_TASKMAN` (Larry confirmed) | | research/04 |
| D-019 | No automatic restraint in first release (Larry confirmed) | Trust first | research/04 |

## Innovations to Implement

| ID | Innovation | Design Impact | Phase |
|----|------------|---------------|-------|
| I-001 | Verdict first | `TM_VERDICT` is the central output; every UI renders it | 3 |
| I-002 | Felt lag as dependent variable | A responsiveness metric beside CPU, memory, disk; rules may consult it | 3 |
| I-003 | Proof by intervention | `TM_EXPERIMENT` with three windows | 4 |
| I-004 | Sentence, not execution | `TM_RESTRAINT` with `apply`, `undo`, prior state, journal | 4 |
| I-005 | The machine has a contract | `TM_CONTRACT`, `TM_INCIDENT`, TOML loader, metric registry | 3 |
| I-006 | Trace is a database and a test fixture | Diagnosis consumes a window, never the live machine; clock and sources injected | 2 |
| I-007 | Honest telemetry by the language | `TM_READING` precondition; `TM_PROCESS_ID` class; validity range per metric | 1 |
| I-008 | Monitor under contract to itself | Own overhead is a metric; budget object backs off | 1 |
| I-009 | Power-budget arithmetic | One later rule; needs second power source | later |

## Risks to Address in Design

| ID | Risk | Mitigation Strategy in the design |
|----|------|-----------------------------------|
| RISK-001 | Native layout changes | `is_trusted` set by self-check; readers require it; fallback class behind the same deferred interface |
| RISK-002 | Lag probe measures the wrong thing | Probe behind a deferred class; diagnosis never *requires* it |
| RISK-003 | Restraint harm | Protected set as precondition; receipts; journal; user-initiated only |
| RISK-004 | Sensors vary | Status on every reading; rules declare required metrics and answer inconclusive |
| RISK-005 | Overhead | Self metrics; budget object; slow-cadence instance expansion |
| RISK-006 | Confident wrong verdict | Evidence mandatory by invariant; inconclusive is a kind; replay tests |
| RISK-009 | Untestable hardware | Fake sources and recorded fixtures drive tests |
| RISK-010 | Inline-C statics per translation unit | All native state in Eiffel attributes; no header statics |
| RISK-012 | Recorder disk load | Recorder on its own processor; batched commits |
| RISK-013 | Localized counters | One wrapper class adds counters only through the English call |
| RISK-014 | Standard user cannot act on services | Outcome object carries `needs_administrator` |
| RISK-016 | Looks like a clone until Phase 3 | Capability panel and honest gaps visible from Phase 1 |
| RISK-017 | SCOOP plus Win32 pump in Phase 1 | Sampler class is processor-agnostic; cross-processor handoff isolated in two classes; see `03-CHALLENGED-ASSUMPTIONS.md` |

## Use Cases

### UC-001: See what the machine is doing now (Phase 1)
**Actor:** Owner
**Precondition:** GUI running as a standard user.
**Main Flow:**
1. Sampler takes a snapshot each second and derives a frame from the previous one.
2. Window shows the process grid, per-core heatmap, and trend lines.
3. A sensor this machine lacks appears as "not supported", never as 0.
4. The tool's own row and overhead are visible.
**Postcondition:** Display reflects a frame no older than two sampling intervals.

### UC-002: Ask the library for a snapshot (Phase 1)
**Actor:** Any Eiffel program, or the CLI
**Precondition:** None beyond creating the facade.
**Main Flow:**
1. Create `SIMPLE_TASKMAN`.
2. Call `sample` twice, an interval apart.
3. Read `last_frame`: per-process rates and system readings.
**Postcondition:** No window, no database, no background processor was created.

### UC-003: What can this machine measure? (Phase 1)
**Actor:** Owner or CLI
**Main Flow:**
1. Request the capability report.
2. Each registered metric is listed with status and, when absent, the reason.
**Postcondition:** Temperature on this machine reads not supported.

### UC-004: What happened at 2 PM? (Phase 2)
**Actor:** Owner, after the incident
**Precondition:** Recorder was running at the time.
**Main Flow:**
1. Drag the timeline back to the period.
2. Grid and graphs redraw from recorded frames.
3. (Phase 3) Banner shows the verdict computed from that recorded window.
**Postcondition:** The same verdict as would have been shown live (FR-025).

### UC-005: Why is it slow right now? (Phase 3)
**Actor:** Owner
**Main Flow:**
1. Diagnostician evaluates each rule over the recent window.
2. Banner shows one sentence naming bottleneck and culprit.
3. Owner expands the banner to see the evidence readings and the cause chain.
**Alternate:** Required readings missing or rules disagree without a known precedence: banner says inconclusive and why.
**Postcondition:** Every stated verdict other than "none" has at least one evidence item.

### UC-006: A machine contract is violated (Phase 3)
**Actor:** The tool
**Precondition:** Contracts file loaded; every metric name resolved.
**Main Flow:**
1. A contract's bound is exceeded for its required duration.
2. An incident opens with start time, culprit from the diagnostician, and a pinned evidence window.
3. The incident closes when the bound holds again.
**Postcondition:** Incident is visible on the timeline and survives retention downsampling.

### UC-007: Restrain a culprit and undo (Phase 4)
**Actor:** Owner
**Main Flow:**
1. Choose a restraint for the culprit identity.
2. Tool opens the process, verifies identity on the handle, checks the protected set, records prior state to the journal, applies.
3. Owner undoes; prior state is restored exactly.
**Alternate:** Access denied: outcome says "needs administrator" and offers relaunch (FR-055).
**Alternate:** Pid now belongs to another process: refused, nothing changed.

### UC-008: Prove the culprit (Phase 4)
**Actor:** Owner
**Main Flow:** Restrain briefly; record before, during, after; restore; report confirmed, not confirmed, or inconclusive.

### UC-009: Regression-test a real incident (Phase 2/3)
**Actor:** Developer
**Main Flow:**
1. Export or copy the recorded window.
2. A test loads it into a memory store and runs the diagnostician.
3. The test asserts the expected verdict kind and culprit.
**Postcondition:** The rule set cannot regress on that incident unnoticed.
