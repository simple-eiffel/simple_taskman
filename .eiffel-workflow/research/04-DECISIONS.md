# DECISIONS: simple_taskman

Date: 2026-10-03

## Decision Log

### D-001: Build, adopt, or adapt
**Question:** Where does the measurement layer come from?
**Options:**
1. Build in Eiffel with inline C: fits ecosystem rules; full control over honesty and identity; most work.
2. Wrap a foreign metrics library: less Win32 work; adds a foreign toolchain; violates the inline-C and simple_* rules; diagnosis still has to be built.
3. Grow simple_system: reuses a library; turns a stateless facts facade into a stateful sampler.

**Decision:** Option 1.
**Rationale:** Nothing in ISE, Gobo, or simple_* returns per-process resource data (verified by grep). The Win32 surface is small. The spike showed one native call returns the whole table in about 2.5 ms.
**Implications:** New library with a `probe` cluster of inline-C classes.
**Reversible:** YES

### D-002: One repository, several targets
**Question:** One project or a separate sampling library plus an application?
**Options:**
1. Single `simple_taskman` repo: library target, tests target, CLI target, stress target, later GUI target.
2. Separate `simple_sysmon` library plus `simple_taskman` app from day one.

**Decision:** Option 1, with clusters cut so the `probe` cluster has no dependency on recorder, diagnosis, or UI.
**Rationale:** No second client exists yet. Extraction later is mechanical if clusters stay clean.
**Implications:** Clusters: `probe`, `model`, `recorder`, `diagnosis`, `action`, `cli`, `gui`. Class prefix `TM_`. Facade `SIMPLE_TASKMAN`.
**Reversible:** YES

### D-003: Process table source
**Question:** How to read all processes each tick?
**Options:**
1. `NtQuerySystemInformation(SystemProcessInformation)`: one call, no handles, includes protected processes, includes CPU times, IO counters, creation time. Microsoft marks it unstable and documents the needed fields only as "Reserved".
2. Toolhelp snapshot plus `OpenProcess` per process plus `GetProcessTimes`, `GetProcessMemoryInfo`, `GetProcessIoCounters`: fully documented; hundreds of handle opens per tick; access denied on many system processes for a standard user.
3. PDH "Process V2" counters: documented; wildcard expansion over hundreds of instances; string-keyed.

**Decision:** Option 1 as the primary path, guarded by a startup self-check, with option 2 as the automatic fallback.
**Rationale:** Measured here: 349 processes, 0.94 MB, 2.48 ms median, non-admin. Offsets for creation time and CPU times matched the documented API for the calling process exactly. Microsoft's own page asks for run-time dynamic linking so a program "can respond gracefully"; the self-check does that.
**Implications:** A `TM_NATIVE_PROCESS_TABLE` class whose creation procedure verifies its layout against the documented per-process calls for the current process and sets `is_trusted`. All readers have precondition `is_trusted`. Loaded via `GetProcAddress`, not an import.
**Reversible:** YES; the fallback is the same deferred interface.

### D-004: System-wide counters
**Question:** How to read energy, GPU, disk, memory counters?
**Options:**
1. PDH (performance counters API): documented, stable, standard user; string paths; localized names unless the English variant is used.
2. Direct device IOCTLs (EMI) and D3DKMT calls: lower overhead; more code; partly undocumented for GPU.
3. WMI: slow, heavy.

**Decision:** Option 1, always through the English-name counter call. Revisit EMI IOCTLs only if PDH overhead breaks NFR-001.
**Rationale:** The probe read RAPL power, GPU engines, and GPU memory through PDH as a standard user. Units verified by arithmetic: energy in picowatt-hours, time in milliseconds, power in milliwatts.
**Implications:** A `TM_COUNTER_QUERY` wrapper opened once and collected per tick. GPU engine has 1384 instances here, so wildcard expansion happens on a slower cadence than collection. The package instance is used; the `_Total` power instance read 0 and is ignored.
**Reversible:** YES

### D-005: No kernel driver; sensors are optional
**Question:** How far to go for temperature and other hardware sensors?
**Options:**
1. No driver; expose what Windows exposes; mark the rest unavailable.
2. Bundle or depend on PawnIO.
3. Write a driver.

**Decision:** Option 1.
**Rationale:** On this machine the thermal zone set has no instance and ACPI WMI is unsupported, so option 1 means no CPU temperature here. That is acceptable because the diagnosis does not need temperature to name a bottleneck, and FR-008 makes the absence visible instead of hidden. LibreHardwareMonitor's own no-driver profile drops CPU and motherboard sensors too.
**Implications:** Sensor sources sit behind a deferred `TM_SENSOR_SOURCE`. Vendor paths (NVML for NVIDIA temperature and power) can be added later as optional sources without touching consumers.
**Reversible:** YES

### D-006: Representation of a reading
**Question:** How to make "unavailable is not zero" impossible to violate?
**Options:**
1. `detachable REAL_64_REF`: void means missing; no reason recorded; boxing per sample.
2. A small `TM_READING` object: status enumeration plus value; `value` has precondition `is_available`.
3. Sentinel values such as NaN or -1: exactly the lie we are avoiding.

**Decision:** Option 2 at API boundaries. Bulk time series use a compact column: one `SPECIAL [REAL_64]` plus a parallel status array, wrapped by a class with the same precondition on item access.
**Rationale:** Reasons matter to the user (not supported versus access denied versus invalid). Option 1 loses them. Per-sample objects at 1 Hz across hundreds of series would create avoidable garbage.
**Implications:** Statuses: available, unavailable, not_supported, access_denied, invalid. Invariant: status is available implies value is finite. Aggregations over a window return a reading whose status reflects coverage.
**Reversible:** NO in practice; this shapes every signature.

### D-007: Process identity
**Question:** What identifies a process across samples and for actions?
**Options:**
1. Pid only.
2. Pid plus creation time (from the process table).
3. Windows `SequenceNumber` from `SystemBasicProcessInformation`.

**Decision:** Option 2 everywhere. Option 3 noted as a future cross-check; it exists only from build 26100.4770.
**Rationale:** Creation time comes free with the table and works on every supported build. For actions, the tool opens a handle, then reads the creation time *through that handle*; a held handle cannot be reassigned, so the check and the act refer to the same process.
**Implications:** `TM_PROCESS_ID` is immutable, hashable on both fields. Every action routine takes an identity and has a "still the same process" check that is evaluated on the opened handle, not on the pid.
**Reversible:** NO

### D-008: Recorder storage
**Question:** Where does history live?
**Options:**
1. SQLite through simple_sql: queryable, one file, portable, tooling everywhere.
2. Custom binary ring file through simple_mmap: smallest and fastest; opaque; a format to maintain.
3. JSON lines: simple; large; slow to query.

**Decision:** Option 1. JSON is an export format only.
**Rationale:** "The trace is a database" is itself a feature: anyone can ask it questions in SQL, and tests can load a recorded incident as a fixture.
**Implications:** WAL mode. Commits batched every few seconds. Three resolution tiers: 1 s for the last hour, 10 s for the last day, 60 s for 30 days. System readings always stored; process rows stored only for processes above a significance threshold in any resource, plus all processes named in an incident. Incident windows are pinned against downsampling. Rough size, **estimated not measured**: about 55,000 system rows and under a million process rows at steady state, inside the 250 MB cap. Phase 2 must measure it.
**Reversible:** YES, behind a deferred `TM_TRACE_STORE`.

### D-009: Concurrency model
**Question:** How do sampling, recording, and UI coexist?
**Options:**
1. Everything on one thread with a timer: simplest; a slow query or a slow disk stalls the UI.
2. SCOOP: sampler and recorder on separate processors; consumers receive immutable snapshots.

**Decision:** Core model classes are plain sequential objects with no SCOOP dependence. The CLI runs a single-threaded loop. The GUI application hosts the sampler and recorder on separate processors and receives snapshots.
**Rationale:** Keeps the diagnosis engine deterministic and testable (NFR-010), and keeps "the task manager must not become the problem" true for the GUI.
**Implications:** Snapshots are immutable after creation. Inline-C state lives in Eiffel objects or in one-class externals, never in mutable header statics (C-007).
**Reversible:** YES

### D-010: Diagnosis engine
**Question:** Rules, statistics, or a language model?
**Options:**
1. Deterministic rules over windows of readings, each rule a class with contracts, each verdict carrying its evidence.
2. Statistical anomaly detection only.
3. Hand the trace to an LLM.

**Decision:** Option 1 decides. Statistics (simple_statistics) supply baselines and thresholds. An LLM may later *narrate* a verdict from its evidence; it never decides one.
**Rationale:** A verdict must be reproducible from a recorded window (FR-025) and must be explainable line by line. A local model on the Ollama instance is available later for wording.
**Implications:** `TM_RULE` deferred class: `applies (window)`, `verdict (window)`. `TM_VERDICT` has bottleneck class, culprits, sentence, evidence list, confidence. Inconclusive is a first-class result.
**Reversible:** YES

### D-011: Responsiveness probe
**Question:** How to measure felt slowness?
**Options:**
1. Windows "User Input Delay" counters: exactly the right metric; **absent on this machine**.
2. Null-message round trip to the foreground window with abort-if-hung and a short timeout: standard user, no setup; measures that application's UI thread pickup time.
3. Self-only probes (own timer overshoot, own disk write latency): safe; indirect.

**Decision:** Option 2 as the primary signal, sampled several times per second with the **maximum** per interval recorded. Option 3 as secondary signals. Option 1 used opportunistically when the counters exist.
**Rationale:** Spike: 120 of 120 sends succeeded across 12 windows as a standard user, idle worst case 1.1 ms. Microsoft's own page argues for the maximum, not the mean. Sleep-based overshoot proved too coarse here (3.8 to 6.5 ms at idle from timer granularity), so the scheduler probe needs a high-resolution timer.
**Implications:** Probe runs on its own processor because a hung target blocks up to the timeout. Elevated targets may refuse the message; that result is recorded as access_denied, not as zero lag. Still to prove in Phase 3: the value rises under real load.
**Reversible:** YES

### D-012: Restraint mechanisms
**Question:** Which interventions, in what order?
**Options:**
1. EcoQoS via `SetProcessInformation(ProcessPowerThrottling)`: documented, reversible, needs set-information access.
2. Priority class change: documented, reversible, what ProBalance and Efficiency mode use.
3. Job object CPU hard cap: documented; precise percentage; assigning an already-running process needs validation.
4. Suspend and resume through the native API: strongest effect; undocumented; can deadlock other software if the target holds a lock.

**Decision:** Ladder of 1, then 2, then 3. Option 4 excluded.
**Rationale:** Start with the mechanisms Microsoft itself ships in Task Manager. Keep the dangerous one out.
**Implications:** Each rung is a class implementing `apply` and `undo` with the prior state captured in the object and journaled to disk (FR-046). Protected-process refusal is a precondition.
**Reversible:** YES

### D-013: Interface order
**Question:** GUI first or CLI first?
**Options:**
1. CLI and library first; GUI in Phase 5.
2. GUI first for visual impact.

**Research recommendation (superseded):** Option 1, on the grounds that measurement and diagnosis carry the risk.

**Decision (Larry, 2026-10-03): Option 2, GUI first.**
**Rationale:** The product is headed for publication as an Eiffel showcase (D-016). A window that moves is the proof people look at, and simple_widgets already has the grid, heatmap, sparkline, timeline, and Sankey widgets.
**Implications:**
- The GUI application is the host from Phase 1. Each later capability (recorder, verdict, restraints) lands as something visible in that window.
- What does **not** change: the library target stays headless and UI-free; the model and diagnosis classes are tested without a window; the stress tool still exists for repeatable scenarios. GUI first changes the order of delivery, not the layering.
- The SCOOP split of D-009 is needed from day one instead of Phase 5: sampler on its own processor, immutable snapshots to the window.
- Widgets receive their own copies of row data, never a live list (known simple_widgets crash).
- The CLI shrinks to a thin `snapshot` and `capabilities` command for tests and scripting, and grows later.
- New risk: a GUI that shows only graphs for two phases looks like a TMOG clone until the verdict banner arrives. See RISK-016.
**Reversible:** YES

### D-016: Audience and destination
**Question:** Who is this for?
**Decision (Larry, 2026-10-03):** A personal tool first, to prove the idea, headed toward publication as an Eiffel showcase: another simple_* library and product.
**Implications:**
- Normal simple_* shipping standards apply at the end: README, CHANGELOG, docs site, phase compliance, `/eiffel.ship`.
- The headless library must be usable by other Eiffel programs on its own, which reinforces D-002's clean `probe` cluster.
- Code signing, installer, and trace redaction are needed before publication, not before personal use.
- Honest-telemetry and identity contracts (D-006, D-007) are part of the showcase message, so they must be visible in the public API, not buried.
**Reversible:** YES

### D-017: Elevation (administrator rights)
**Question:** Should the tool run as a normal user, always as administrator, or offer both?
**Background, measured on this machine 2026-10-03 from a non-administrator session:**

| What the tool wants to do | Processes it may do it to | Refused |
|---|---|---|
| See every process with CPU, memory, IO (native table, no handle needed) | 349 of 349 | 0 |
| Open a process to read details such as full path | 200 of 339 | 139 |
| Open a process to throttle it (priority, EcoQoS) | 189 of 339 | 150 |
| Open a process to end it | 199 of 339 | 140 |

The refused set is services and system processes: 82 `svchost` instances, the search indexer, Defender, the print spooler, and also Larry's own PostgreSQL and web server services. Those are common culprits.

**Options:**
1. Standard user only: safest, simplest; can *diagnose* everything but can *act* on only about 56% of processes.
2. Always administrator: full reach; a UAC prompt at every launch; a bug in an elevated process-control tool has more ways to do damage; unfriendly as a showcase.
3. Standard user by default, with a "Restart as administrator" command that relaunches the tool elevated through one UAC prompt when the user wants to act on a service.

**Decision (confirmed by Larry 2026-10-03, "follow your recommendations"):** Option 3. It is a superset of option 1 and nothing in Phases 1 to 3 depends on it.
**Rationale:** All measurement and diagnosis works without elevation, which the probe proved. Elevation only widens which processes can be restrained or ended. Asking for it at the moment it is needed is the least surprising behavior.
**Implications:**
- An action refused for lack of rights reports "needs administrator" and offers the relaunch; it never fails silently.
- Readings that need a handle (full path, command line) are access_denied for the refused set when not elevated, per D-006.
- No background service, no scheduled elevated task, no driver.
- The protected set of D-012 still applies when elevated. Elevation widens reach to services; it does not unlock core OS processes.
**Reversible:** YES

### D-018: Name
**Question:** Product and library name?
**Decision (confirmed by Larry 2026-10-03, "follow your recommendations"):** `simple_taskman`. Class prefix `TM_`, facade `SIMPLE_TASKMAN`.
**Reversible:** YES until the ECF and class prefix exist.

### D-014: Machine contracts format
**Question:** How does a user declare "healthy"?
**Options:**
1. Eiffel classes compiled in: strongest typing; users cannot edit.
2. A TOML file of named bounds over readings and windows, read by simple_toml.
3. A custom expression language.

**Decision:** Option 2, with a fixed vocabulary of reading names and the operators below, above, within, for-at-least duration.
**Rationale:** Editable, diffable, and small. The built-in rules of D-010 remain Eiffel classes.
**Implications:** A contract references reading names from one registry so a typo is a load-time error, not a silent never-fires rule.
**Reversible:** YES

### D-015: Platform
**Question:** Windows only?
**Decision:** Windows only. Probe classes sit behind deferred interfaces so a Linux `/proc` implementation is possible later, but nothing is built or promised.
**Rationale:** TMOG already owns cross-platform. Our differentiation is diagnosis, and simple_widgets is Win32.
**Reversible:** YES

### D-019: No automatic restraint in the first release
**Question:** Should the tool ever restrain a process without being asked, as ProBalance does?
**Decision (confirmed by Larry 2026-10-03, "follow your recommendations"):** No. Restraints and experiments are user-initiated only.
**Rationale:** Trust first. A tool that silently changes other programs must earn that, and the verdict engine has no track record yet (RISK-003, RISK-006).
**Implications:** Machine contracts raise incidents and may *suggest* a restraint; they never apply one.
**Reversible:** YES

### D-020: Recorder runs on the sampling worker's processor
**Question:** Where does the SQLite writer run? (Raised in spec step 3, A-118.)
**Options:**
1. Its own processor, fed by a second slot: isolates commit time from sampling; a second handoff; still stalls the GUI through collector synchronization because SQLite externals are not declared blocking.
2. On the sampling worker's processor: one writer, no second handoff; a slow commit delays one tick.
3. On the GUI processor: simplest; every commit lands directly on the GUI.

**Decision:** Option 2, with batched commits every 5 s.
**Rationale:** Option 1 does not remove the real hazard (A-118), and option 3 makes it worse. The monotonic clock keeps rates right when a tick runs long.
**Implications:** Supersedes the "recorder on its own processor" note in D-009 and the Phase 2 bullet. The slot pattern can still split them later if the Phase 2 measurement demands it. Upstream item W-4 is the real fix.
**Reversible:** YES
