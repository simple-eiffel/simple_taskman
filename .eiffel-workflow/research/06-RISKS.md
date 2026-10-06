# RISKS: simple_taskman

Date: 2026-10-03

## Risk Register

| ID | Risk | Likelihood | Impact | Mitigation |
|----|------|------------|--------|------------|
| RISK-001 | Native process-table layout changes in a future Windows build | LOW | HIGH | Startup self-check against documented APIs; automatic fallback path |
| RISK-002 | Responsiveness probe does not track what users feel | MED | HIGH | Phase 3 spike with a UI-blocking fixture before any rule depends on it |
| RISK-003 | A restraint harms the target or the system | MED | HIGH | Documented mechanisms only; protected set; journaled undo; no suspend |
| RISK-004 | Sensor availability varies wildly between machines | HIGH | MED | Typed availability; diagnosis never requires an optional sensor |
| RISK-005 | Monitor overhead exceeds its budget | MED | MED | Measured self-overhead; back-off; slow-cadence expansion of large counter sets |
| RISK-006 | Wrong verdict stated with confidence | MED | HIGH | Evidence attached to every verdict; inconclusive allowed; replay regression suite |
| RISK-007 | Scope creep across ten innovations | HIGH | MED | Phase gates; MVP is Phases 1 to 3 only |
| RISK-008 | Antivirus or SmartScreen treats the tool as hostile | MED | MED | No driver; least-privilege handle rights; code signing before distribution |
| RISK-009 | Features cannot be tested on the dev machine | HIGH | MED | Explicit list of untestable features; replay fixtures from other machines |
| RISK-010 | Inline-C state duplicated across generated translation units | MED | HIGH | No mutable statics in shared headers; state held in Eiffel objects |
| RISK-011 | Trace leaks private information when shared | MED | MED | Redaction on export; no network by default |
| RISK-012 | Recorder becomes a disk load of its own | LOW | MED | WAL, batched commits, size cap, measured in Phase 2 |
| RISK-013 | Counter names localized on non-English Windows | MED | MED | English-name counter API |
| RISK-014 | Standard user cannot act on services and system processes (measured: 150 of 339 refuse throttling) | HIGH | MED | Diagnosis needs no handles; "Restart as administrator" for actions (D-017) |
| RISK-015 | Stale test executable reports a pass after a failed compile | MED | MED | Check "Error code:" and F_code timestamps; known ecosystem gotcha |
| RISK-016 | GUI first shows only graphs for two phases and reads as a TMOG clone | MED | MED | Do not publish before the Phase 3 verdict banner; capability panel and honest gaps visible from Phase 1 |
| RISK-017 | GUI first pulls SCOOP plus Win32 message pumping into Phase 1 | MED | HIGH | Small spike first: sampler processor feeding a simple_widgets window for one hour before building views |

## Technical Risks

### RISK-001: Undocumented structure layout
**Description:** CPU times, creation time, and IO counters sit in fields Microsoft documents only as "Reserved" in `SYSTEM_PROCESS_INFORMATION`. The function page warns it "may be altered or unavailable in future versions of Windows".
**Likelihood:** LOW. The layout is the one System Informer's `phnt` headers and the Rust sysinfo crate rely on, and it matched exactly on build 26200 in the spike.
**Impact:** HIGH. A silent mismatch would produce plausible garbage.
**Indicators:** Startup self-check disagrees with `GetProcessTimes` for the current process.
**Mitigation:** Self-check sets `is_trusted`; every reader requires it. Function resolved with `GetProcAddress`.
**Contingency:** Fallback implementation over Toolhelp plus per-process documented calls, same deferred interface, with access_denied rows for processes it cannot open.

### RISK-002: The lag probe measures the wrong thing
**Description:** A null-message round trip measures when the target's UI thread next pumps messages. It may stay low while the application is slow in ways that do not block that thread (slow rendering, slow background work), and it says nothing for full-screen games that do not pump normally.
**Likelihood:** MEDIUM
**Impact:** HIGH for I-002 and I-003, which build on it.
**Indicators:** Probe stays flat during the synthetic CPU, memory, and disk scenarios while the machine is visibly sluggish.
**Mitigation:** Prove it in Phase 3 before rules depend on it: a fixture application whose UI thread blocks on demand; then the three stress scenarios. Combine with secondary probes (high-resolution scheduler delay, small synchronous disk write latency). Use the Windows User Input Delay counters where present.
**Contingency:** Diagnosis works from resource readings alone, as every other tool does; the experiment feature then compares resource readings instead of lag and says so.

### RISK-003: Intervention causes harm
**Description:** Throttling the wrong process can stall something the user needs, or a system service. A crash of the tool mid-experiment could leave a process restrained.
**Likelihood:** MEDIUM
**Impact:** HIGH
**Indicators:** User reports of applications staying slow after the tool exits.
**Mitigation:** Only documented, reversible mechanisms (EcoQoS, priority class, job CPU cap). Suspend excluded. Protected set refused by precondition, mirroring Task Manager greying out core processes. Prior state journaled before apply; restore offered on next start. Experiments are short and user-initiated in the first release, never automatic.
**Contingency:** Ship restraints as manual actions only and drop the automatic experiment.

### RISK-004: Sensors differ per machine
**Description:** Verified locally: RAPL power yes; thermal zone no instances; ACPI WMI unsupported; no battery; User Input Delay counters absent; three GPU counter values wrapped to about 1.8e19.
**Likelihood:** HIGH
**Impact:** MEDIUM
**Mitigation:** FR-008 and FR-009. Rules declare which readings they need and report inconclusive when those are missing. A capability report command lists what this machine offers.
**Contingency:** Optional vendor sources later (NVML).

### RISK-005: Overhead
**Description:** GPU engine counters have 1384 instances here; naive wildcard collection every second could be expensive. Per-process string handling in Eiffel could add garbage-collection load.
**Likelihood:** MEDIUM
**Impact:** MEDIUM, and reputational: a slow task manager is self-refuting.
**Indicators:** Own CPU share above NFR-001 in the 1-hour soak.
**Mitigation:** Process table is cheap (2.48 ms median measured). Expand counter instances at a slow cadence, collect at the fast one. Reuse buffers; compact columns for series (D-006). Enforced back-off (NFR-006).
**Contingency:** Lower default rate; GPU per-process on demand only.

### RISK-006: Confident wrong verdicts
**Description:** A rule engine can blame the visible process while the cause is elsewhere (for example a driver, or memory pressure caused by many small processes).
**Likelihood:** MEDIUM
**Impact:** HIGH. Trust is the product.
**Mitigation:** Verdicts cite evidence. Confidence levels. Inconclusive is allowed (FR-033). Every misdiagnosis found in real use becomes a replay fixture and a failing test before the rule is changed.
**Contingency:** Present ranked suspects rather than a single culprit when confidence is low.

### RISK-010: Inline-C statics per translation unit
**Description:** A known failure in this ecosystem: mutable statics in a header get a private copy per generated C file, so state set through one class is invisible through another. It caused a lockup in simple_shell.
**Likelihood:** MEDIUM if handles or query state are parked in C statics.
**Impact:** HIGH
**Mitigation:** Constraint C-007. Handles and buffers are `POINTER` attributes of Eiffel objects. Any unavoidable C global lives behind one class's externals.

## Ecosystem Risks

- **simple_sql and SQLite close during GC.** Fixed 2026-09-28. This project must be built clean against the fixed libraries and must close statements deterministically, since a recorder opens many.
- **Finalized `check` assertions are vacuous.** Tests must assert through TEST_SET_BASE and keep side effects out of assertions.
- **Stale executable after failed compile (RISK-015).** `ec.sh run` can report success from an old binary.
- **simple_widgets shared-list invariant.** Feeding a live, mutating process list to the data grid by reference has crashed an application before. The GUI must hand widgets their own copies (the `set_rows` twins).
- **SCOOP plus Win32 message pumping.** The probe and any hidden window need a processor whose thread actually pumps messages. Needs a design note in the spec phase.
- **Supplier changes need a clean rebuild** of the client's EIFGENs (oracle rule, 2026-09-10).

## Resource Risks

- **RISK-007 scope.** Ten innovations is three products. The gate: nothing from Phase 4 onward starts until the three stress scenarios and the after-the-fact query pass end to end.
- **RISK-009 hardware.** This machine cannot exercise hybrid cores, battery, temperature, or elevated-window probing. Those features ship marked unverified until a recorded trace or a second machine covers them.
- **Competing priorities.** simple_treebiz phase 0 artifacts are the current handoff task. This project should not displace that without Larry deciding so.
- **Windows internals skill.** The native process table and wait-chain APIs are sharp. Mitigated by the self-check pattern and by keeping deferred items deferred.
