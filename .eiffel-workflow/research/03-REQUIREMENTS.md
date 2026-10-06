# REQUIREMENTS: simple_taskman

Date: 2026-10-03

Priorities: MUST = Phase 1 to 3 (the MVP, GUI first per D-013). SHOULD = Phase 4 to 5.
COULD = later phases, listed so the design leaves room for them.

## Functional Requirements

### Measurement

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-001 | Take a snapshot of all processes: identity, name, parent, CPU time (user, kernel), working set, private bytes, IO bytes read and written, thread and handle counts | MUST | Test compares the calling process's row with values from the documented per-process APIs; equal within one sample |
| FR-002 | Identify a process by pid **and** creation time; equality and hashing use both | MUST | Test: two identities with the same pid and different creation times are not equal |
| FR-003 | Compute per-process rates (CPU share, IO bytes per second) as deltas between two snapshots matched by identity | MUST | Test with synthetic snapshot pairs, including a recycled pid, yields no rate carried across identities |
| FR-004 | Report per-logical-processor CPU usage and the efficiency class of each core | MUST | On this 16-core machine: 32 logical processors, all class 0; values in 0..100 |
| FR-005 | Report memory state: physical in use, available, commit charge and limit, hard page faults per second | MUST | Values agree with Task Manager within tolerance during a manual check; commit <= limit holds as a postcondition |
| FR-006 | Report disk activity per physical disk (bytes per second, queue length or busy time) and free space per volume | MUST | Stress tool writing a large file raises the reported write rate on the right disk |
| FR-007 | Report CPU package power from the Energy Meter counters when present | MUST | On this machine the reading is within 10% of the counter's own Power value; on a machine without the counters the reading is *unavailable* |
| FR-008 | Every reading carries an availability status: available, unavailable, not supported, access denied, or invalid | MUST | No public query returns a bare number for a sensor; a value query has precondition `is_available` |
| FR-009 | Reject invalid raw values (for example the 1.8e19 wrapped GPU counters seen in the probe) as *invalid*, not as data | MUST | Test feeds a wrapped value; status is invalid |
| FR-010 | Report per-process GPU utilization and GPU memory where the counters exist | SHOULD | Process playing video shows nonzero GPU; aggregation follows "busiest engine", not a sum across engines |
| FR-011 | Report battery state and drain rate where a battery exists | COULD | Unavailable on this desktop; verified on a laptop later |
| FR-012 | Report temperature where a readable source exists | COULD | Unavailable on this machine; must not appear as 0 |

### Recording

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-020 | Continuously record system readings and the significant processes to a local SQLite database | MUST | After a 10-minute run the database holds a row set for every sample tick, with gaps where readings were unavailable |
| FR-021 | Keep a bounded history with tiered resolution (fine recent, coarse old) and a size cap | MUST | Database stops growing at the cap in a soak test; oldest fine-grained rows are downsampled, not silently dropped |
| FR-022 | Query: "what happened between T1 and T2" returns readings, top processes, and any incidents | MUST | CLI command returns the stress scenario after the stress tool has exited |
| FR-023 | Export a time window as JSON suitable for a person or an LLM | SHOULD | Export validates as JSON and round-trips through simple_json |
| FR-024 | Redact option on export: process paths, user names, window titles | SHOULD | Export with redaction contains none of the listed fields |
| FR-025 | Replay: feed a recorded window back through the diagnosis engine | MUST | Recorded scenario produces the same verdict offline as it did live; this is the regression-test mechanism |

### Diagnosis

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-030 | Classify the current bottleneck: CPU saturation, memory pressure, disk saturation, power or thermal limit, single hung application, or none | MUST | Each of three synthetic loads yields the matching class; idle machine yields none |
| FR-031 | Name the responsible process identity or identities for the bottleneck | MUST | Culprit equals the stress tool's identity in each scenario |
| FR-032 | Produce a verdict: one plain sentence, plus a list of the evidence readings that support it | MUST | Verdict object exposes its evidence; test asserts the evidence is non-empty and inside the time window |
| FR-033 | State confidence and say "not enough evidence" rather than guess | MUST | Ambiguous synthetic input yields an explicit inconclusive verdict |
| FR-034 | Measure foreground responsiveness directly and record the maximum per interval | SHOULD | Probe value rises when the foreground application's UI thread is blocked by a test fixture |
| FR-035 | Evaluate declared machine contracts and open an incident on violation, with the surrounding evidence window pinned against expiry | SHOULD | A contract "commit below 90%" violated by the memory stress tool creates one incident with start, end, and culprit |
| FR-036 | Propose contracts from observed baseline (ranges, percentiles) for the user to accept | COULD | After a baseline period the tool lists proposed bounds; none is active until accepted |
| FR-037 | Detect a shared power budget: combined load draws materially less than the sum of separate loads | COULD | Needs GPU power; CPU-side only on this machine |
| FR-038 | Show the wait chain for a hung application | COULD | Deferred |

### Action

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-040 | Apply a graded restraint to a process: EcoQoS, lower priority class, CPU cap | SHOULD | Each restraint is observable through the corresponding query API after application |
| FR-041 | Every restraint records the prior state and can be undone exactly | SHOULD | Postcondition of undo: state equals recorded prior state |
| FR-042 | An action targets a process identity and fails safely if the pid now belongs to another process | MUST (for any action) | Test with a stale identity: action is refused, nothing is changed |
| FR-043 | Refuse actions on a protected set of system processes | MUST (for any action) | Precondition; test asserts refusal |
| FR-044 | Controlled experiment: restrain the suspect briefly, compare the responsiveness and bottleneck readings before, during, and after, then restore | SHOULD | Experiment record contains three windows and a result of confirmed, not confirmed, or inconclusive |
| FR-045 | Terminate a process, with the same identity safety | SHOULD | As FR-042 |
| FR-046 | Restraints applied by the tool are released when the tool exits, unless the user chose to keep them | SHOULD | Kill the tool during a restraint; next start detects and offers to restore from the journal |

### Interfaces

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-050 | Library facade usable without any UI | MUST | Test target links only the library |
| FR-051 | CLI: `snapshot` and `capabilities` (MUST, Phase 1); `watch`, `why`, `what-happened --from --to`, `export` (SHOULD, Phase 5) | MUST | Each command has a test with captured output |
| FR-052 | GUI on simple_widgets, delivered incrementally: process grid, per-core heatmap, sparklines, capability panel (Phase 1); timeline with scrubber (Phase 2); verdict banner and cause chain (Phase 3) | MUST | Each phase gate includes a recorded screenshot and a 1-hour run inside the overhead budget |
| FR-053 | The tool can show itself in its own process list and reports its own overhead | MUST | `snapshot --self` prints own CPU share and private bytes |
| FR-054 | Stress tool target for reproducible CPU, memory, and disk loads | MUST | Used by the acceptance scenarios above |
| FR-055 | An action refused for lack of rights says "needs administrator" and offers to relaunch the tool elevated; it never fails silently | SHOULD | From a standard session, throttling a service yields the message and the offer; nothing is changed |
| FR-056 | The GUI never blocks on sampling, recording, or probing | MUST | Window stays responsive while the recorder commits and while a probe target is hung |
| FR-057 | Widgets are given copies of row data, never a live shared list | MUST | Process start and exit during display cause no invariant violation in a 1-hour run |

## Non-Functional Requirements

| ID | Requirement | Category | Measure | Target |
|----|-------------|----------|---------|--------|
| NFR-001 | Sampling overhead | PERFORMANCE | Own CPU time over a 1-hour run at 1 Hz, as share of one logical processor | <= 1.0% average |
| NFR-002 | Snapshot cost | PERFORMANCE | Wall time of one full sample tick | <= 20 ms at 350 processes (spike: the process-table call alone is ~2.5 ms) |
| NFR-003 | Memory footprint | PERFORMANCE | Private bytes, headless recorder | <= 50 MB steady state |
| NFR-004 | Recorder disk writes | PERFORMANCE | Bytes written per hour | <= 20 MB per hour; batched commits, never one transaction per sample |
| NFR-005 | Recorder size | CAPACITY | Database file | Default cap 250 MB, configurable |
| NFR-006 | Self-budget enforcement | RELIABILITY | Behavior when NFR-001 is exceeded | Sampling interval backs off automatically and the event is logged |
| NFR-007 | Privilege | SECURITY | Rights needed for MUST features | Standard user; no elevation, no driver |
| NFR-008 | Privacy | SECURITY | Network use | None by default; no telemetry |
| NFR-009 | Honesty | CORRECTNESS | Unavailable or invalid readings rendered as numbers | Zero occurrences; enforced by type and contract |
| NFR-010 | Determinism | TESTABILITY | Diagnosis engine depends on wall clock or live OS | No; clock and probes are injected so tests replay fixed data |
| NFR-011 | Robustness | RELIABILITY | Native layout mismatch on a future Windows build | Detected by startup self-check; falls back to documented APIs; never reads garbage silently |
| NFR-012 | Localization safety | CORRECTNESS | Counter paths on non-English Windows | English counter API used; test on the name lookup |
| NFR-013 | Probe intrusiveness | SAFETY | Messages sent to other applications | Only the null message, with abort-if-hung and a short timeout; rate limited |

## Constraints

| ID | Constraint | Type | Immutable? |
|----|------------|------|------------|
| C-001 | Must be SCOOP-compatible (`concurrency=scoop`) | TECHNICAL | YES |
| C-002 | Must prefer simple_* over ISE and Gobo | ECOSYSTEM | YES |
| C-003 | Void-safe, `void_safety=all` | TECHNICAL | YES |
| C-004 | Win32 through inline C externals; no separate .c files | TECHNICAL | YES |
| C-005 | No kernel driver | TECHNICAL | YES for this project |
| C-006 | Builds only via `ec.sh` (F_code); tests assert through TEST_SET_BASE, not `check` | ECOSYSTEM | YES |
| C-007 | Mutable C statics must not live in a header shared across generated translation units | TECHNICAL | YES (known ecosystem failure) |
| C-008 | Windows 10 1809 or later, x64 | PLATFORM | NO; ARM64 later |
| C-009 | US English in all prose and UI text | STYLE | YES |
| C-010 | simple_sql clients must be clean-rebuilt against the post 2026-09-28 SQLite close fix | ECOSYSTEM | YES |
