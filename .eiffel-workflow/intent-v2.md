# Intent v2: simple_taskman

Date: 2026-10-03
Supersedes `intent.md`. Adds the adversarial self-review (11 questions with
recommended answers), the dependency audit, gaps, and the refinements both
produced. **Every recommended answer can be overridden at approval.**

---

## What

A diagnostic task manager for Windows, written in Eiffel, that answers *why*
the computer is slow, including after the slowdown has ended.

1. **Headless library:** honest measurement of processes, per-core CPU, memory pressure, disk activity, and CPU package power. A reading the machine cannot supply states why; it is never 0.
2. **Recorder:** rolling history in a SQLite file in the owner's profile.
3. **Rule engine:** one plain sentence naming bottleneck and culprit, with evidence, or an honest "inconclusive".
4. **simple_widgets window**, built first: live view (P1), history scrubber (P2), verdict banner and cause chain (P3).

Later: reversible remedies with proof (P4); publication as a simple_* library and product (P5).

## Why

- Task managers report measurements and leave diagnosis to the human, and forget the incident once it ends.
- TMOG added a flight recorder but still leaves the reasoning to whoever reads the graphs.
- Eiffel fits: "missing is not zero" is a precondition, "a pid is not an identity" is a class, "the monitor must not become the problem" is an invariant.
- Larry's goals: a personal tool that proves the idea, then a published Eiffel showcase.

## Users

| User | How they use it |
|------|-----------------|
| Larry | Daily window; scrubs back to incidents; scripts the CLI; extends rules |
| Family tech-support person | Opens a recording after the fact and reads the verdict |
| Eiffel developers | Use the headless library; read it as a DBC and SCOOP example |

---

## Deep Intent Review (Claude self-review)

### Q1. Does the flight recorder record when the window is closed?

**Why it matters.** The family-support story ("it froze this afternoon") only
works if something was recording while nobody was watching. As specified, the
recorder runs inside the GUI's sampling worker. Close the window and the
recording stops. This is the largest gap between the intent and the design.

**Alternatives.**
1. Record only while the window is open (it may be minimized). Simple; honest; misses incidents when it is closed.
2. Add a headless recorder executable (`taskman_recorder`, no window, no console) that the owner can start at logon through a per-user startup entry. The window becomes a *viewer* of the same file. No service, no administrator rights.
3. A Windows service. Records always; needs administrator rights to install; contradicts D-017's spirit and adds a signed-service burden.

**Recommended answer.** Option 1 for the Phase 2 gate, and option 2 as a
**Phase 2 SHOULD**. The library is already headless, so option 2 costs one
small target plus a single-writer rule (Q2). Startup registration is opt-in
from the window, never automatic.

### Q2. Where does the trace live, and what happens with two copies running?

**Why it matters.** Two writers on one SQLite file contend for locks and can
interleave tiers. A recorder (Q1) plus a window would be exactly that case.

**Alternatives.**
1. Each instance writes its own file. No contention; history fragments.
2. One writer per user, enforced by a named mutex. A second instance opens the file read-only and becomes a viewer.
3. Rely on SQLite busy timeouts. Works mechanically; leaves two processes merging tiers.

**Recommended answer.** Option 2. The trace lives at
`%LOCALAPPDATA%\simple_taskman\trace.db`. The writer holds
`Local\simple_taskman.recorder` (a per-session named mutex). Whoever fails to
get the mutex opens the file with `make_read_only` and shows "recording by
another instance". The audit found no single-instance or app-data helper in
the ecosystem; see Gaps.

### Q3. What exactly does the self-budget govern?

**Why it matters.** The spec measures `self.cpu_pct` from the tool's own
process row, which includes **GUI rendering**. simple_widgets repaints the
whole window every 250 ms. If rendering costs 2%, the budget backs off
*sampling*, which cannot reduce *rendering*. The budget would chase a cost it
does not control, slowing sampling to its maximum interval for nothing.

**Alternatives.**
1. Budget on the whole process (as specified). Wrong lever, as above.
2. Budget on the sampler's own cost: the measured tick cost divided by the interval. Backing off then reduces exactly what it measures.
3. Two budgets: sampler (backs off sampling) and render (reported, with a target, no automatic action).

**Recommended answer.** Option 3. NFR-001 (at most 1% of one logical
processor) applies to sampling, enforced by `TM_SELF_BUDGET` on tick cost.
Whole-process CPU is still shown, so the owner sees the true total. A render
target is set from the Phase 1 spike measurement, not guessed now. **This
changes the spec**: `assess` takes the sample cost and interval rather than
`self.cpu_pct`.

### Q4. How is a GUI-first phase verified, when screens are not unit-testable?

**Why it matters.** "The window shows X" is not a deterministic test, and live
data differs on every run, so screenshots cannot be compared.

**Alternatives.**
1. Manual check plus screenshot. Weak evidence; not repeatable.
2. An evidence bundle: screenshot, one-hour session log with frame times, measured overhead, and a library test run.
3. Option 2 plus a **replay mode**: the window driven by scripted sources or a recorded file (`taskman --replay <file>`), so the same input gives the same screen every time.

**Recommended answer.** Option 3. Replay costs little because the facade
already accepts injected sources (`make_with_sources`), and Phase 2 needs
replay anyway. Phase 1 gate evidence: library tests, a replay screenshot, a
live screenshot, the one-hour log, and the overhead numbers.

### Q5. How are the rules tested when live stress runs are not deterministic?

**Why it matters.** On a live machine, other software adds load. A rule test
that fails because Windows Update started is noise; one that passes by luck
proves nothing.

**Alternatives.**
1. Live stress runs as the tests.
2. Rules unit-tested on scripted windows (deterministic); live stress runs as acceptance evidence.
3. Option 2, plus each accepted live run is saved as a recorded fixture that joins the unit tests.

**Recommended answer.** Option 3. Unit tests: scripted windows with known
answers, including edge cases (missing readings, a discontinuity mid-window,
two rules firing). Acceptance: each stress scenario run three times; three of
three must give the right kind and culprit. Each accepted run becomes a
fixture (I-006), so the rule set can never regress on it unnoticed.

### Q6. What machine sizes must it handle?

**Why it matters.** Dave Plummer demonstrated TMOG on a 192-thread
workstation. Beyond 64 logical processors, Windows uses processor groups; PDH
instance names become `group,number`, and the heatmap shape changes. Servers
and developer machines can run thousands of processes. This machine has one
group of 32 and about 350 processes, so larger shapes cannot be tested live.

**Alternatives.**
1. Support only what this machine has.
2. Design for processor groups and up to 1,024 logical processors and 5,000 processes; test them with scripted sources.
3. Design for unlimited sizes.

**Recommended answer.** Option 2. Topology uses the all-groups calls from the
start. The heatmap shape is computed. The Phase 1 spike also drives the grid
with a scripted 5,000-process frame and records the frame time. Live
acceptance stays on this machine and says so.

### Q7. Is the measurement layer its own library?

**Why it matters.** "Another simple_* library" suggests other Eiffel programs
should be able to read processes and counters without taking a recorder, a
rule engine, and a GUI with them. The research found no simple_* library for
process enumeration or performance counters, so that layer is a genuine
ecosystem gap.

**Alternatives.**
1. One library, `simple_taskman`, containing everything but the GUI.
2. Split now into `simple_sysmon` (probe, model, sampling) and `simple_taskman` (recorder, diagnosis, apps).
3. One repository now, with the measurement clusters dependency-free; decide on extraction at publication.

**Recommended answer.** Option 3. The layering in the spec already keeps
`probe`, `model`, and `sampling` free of recorder, diagnosis, and UI. A test
in Phase 1 proves it by compiling a target with only those clusters. Splitting
before a second client exists would freeze an API too early. Recorded as a
gap below so the idea is not lost.

### Q8. Which formats become public commitments?

**Why it matters.** The frame text and the database schema are written to
disk and may be sent to someone else. Once a trace is shared, a format change
can make it unreadable.

**Alternatives.**
1. No compatibility promise until 1.0.
2. Versioned formats, forward-only migrations, and decoders that keep reading every older version.
3. JSON for everything, for readability.

**Recommended answer.** Option 2 from the first recorded file: the frame text
carries `TMF1`, the database a `schema_version` and its metric catalog. JSON
stays the export format only, because the recorder needs compact, exact
values. Each new version adds a decode test over a saved file of the old one.

### Q9. What private information does a trace hold?

**Why it matters.** Process image names already reveal what someone runs.
Command lines and window titles would reveal far more: file names, URLs,
document titles. A trace sent for help could leak them.

**Alternatives.**
1. Record everything available.
2. Record image names only; never command lines or window titles; redact on export.
3. Encrypt the trace.

**Recommended answer.** Option 2. MVP records image name, pid, and creation
time only. Full paths and command lines are not collected at all in Phases 1
to 3. Export (P2) offers redaction of names to stable placeholders. The trace
stays in the user's own profile folder.

### Q10. What in Phase 3 is premature for the MVP gate?

**Why it matters.** Phase 3 lists rules, verdict banner, cause chain, machine
contracts, incidents, and the lag probe. Gating the MVP on all of them delays
the first moment the tool stops looking like a TMOG clone.

**Alternatives.**
1. Gate on everything listed.
2. Gate on the three rules, verdict banner, and evidence view; contracts, incidents, lag probe, and cause chain follow as Phase 3 SHOULD items.
3. Gate on the CPU rule alone.

**Recommended answer.** Option 2. The MVP gate is "three scenarios, right
verdict, live and after the fact". Order after the gate: cause chain (cheap,
visual), machine contracts and incidents, then the lag-probe spike.

### Q11. Where do diagnostics go, given that simple_logger prints to the console by default?

**Why it matters.** The audit found `SIMPLE_LOGGER.make` writes every message
with `print` (`simple_logger.e:522-526`). In the window target, the first
console write makes Windows open a console window. The sampling worker would
do it from its own processor.

**Alternatives.**
1. No library logging.
2. Library logging through an injected logger; the window and recorder targets create theirs with `make_to_file`, one file per processor; the CLI may use the console.
3. Write a separate logging layer for this project.

**Recommended answer.** Option 2. Rule: the window and recorder targets only
ever call `make_to_file`, writing to
`%LOCALAPPDATA%\simple_taskman\logs\<target>-<processor>.log`. One file per
processor, because each message reopens the file and two writers would
interleave. Upstream note W-7 records that the logger keeps an append handle
open that it never writes or closes.

---

## Dependency Audit (simple_* First)

Checked by a read-only survey of D:\prod on 2026-10-03, with file and line
citations, plus the two spec-phase surveys.

| Need | Library | Verdict | Notes from the audit |
|------|---------|---------|----------------------|
| Kernel types, `RAW_FILE`, `MANAGED_POINTER` | base (ISE) | Allowed | |
| EQA integration | testing (ISE) | Allowed | |
| Assertions | simple_testing | Use | `TEST_SET_BASE` |
| Model contracts | simple_mml | Use | Element equality by value |
| Diagnostics | simple_logger | Use with rule | `make_to_file` only in GUI and recorder (Q11) |
| GUI | simple_widgets, simple_shell, simple_cairo | Use | Known limits recorded in spec 03 |
| Time labels | simple_datetime | Use | No sub-second time; formatting only |
| CLI parsing | simple_cli | Use | `parse` neither prints nor exits; safe |
| Per-user folder | simple_env | **Add** | `item ("LOCALAPPDATA")`, as simple_ocr_capture does |
| Recorder | simple_sql | Use | `make_read_only` sets `SQLITE_OPEN_READONLY`; busy timeout through `execute ("PRAGMA busy_timeout = N")`; SQLite 3.31.1 bundled |
| Export | simple_json | Use (P2) | |
| Machine contracts | simple_toml | Use (P3) | |
| Baselines | simple_statistics | Use later | W-5 |
| Stress disk load | simple_file | **Not suitable** | Writes byte by byte; no chunked or append binary write; no flush; 32-bit offsets; no cache bypass |
| Process table, counters, process control, elevation | none | **Gap** | Confirmed: no simple_* wrapper of any of these |
| Single instance | none | **Gap** | No named-mutex helper anywhere |

## Gaps Identified (Potential simple_* Libraries or Upstream Work)

| Gap | Workaround in this project | Proposed home |
|-----|----------------------------|---------------|
| Process table, performance counters, CPU topology, clocks | Our own inline C in `probe` | Possible `simple_sysmon`, extracted at publication (Q7) |
| Process control: priority, EcoQoS, job CPU cap, terminate, elevation | Our own inline C in `action` (P4) | Same, or `simple_process` extension |
| Single-instance named mutex | Small inline-C class `TM_SINGLE_WRITER` | A general `simple_instance`, or a feature in simple_shell |
| Per-user application folder | `SIMPLE_ENV.item ("LOCALAPPDATA")` | A known-folder helper in simple_env |
| Disk load with cache bypass, chunked binary write | Inline C in the stress target (`CreateFileW` with write-through, no buffering) | W-8: chunked binary write and flush in simple_file |
| Sparkline gaps | Freeze tile with status word | W-1 (simple_widgets) |
| SQLite calls not declared blocking | Short batched commits | W-4 (eiffel_sqlite_2025) |
| Logger keeps an unused append handle; no console-off setter | `make_to_file` only | W-7 (simple_logger) |

## Refinements to the Spec from This Review

Applied to the spec once this intent is approved, before `/eiffel.contracts`:

1. **R-1 (Q3):** `TM_SELF_BUDGET.assess` takes the sampler's tick cost and interval, not `self.cpu_pct`. Whole-process CPU stays a displayed reading.
2. **R-2 (Q4):** GUI target accepts `--replay <file>` and scripted sources; the window code never assumes live sources.
3. **R-3 (Q2, Q11):** add `TM_PATHS` (per-user folders from `LOCALAPPDATA`) and `TM_SINGLE_WRITER` (named mutex) to the library; add simple_env.
4. **R-4 (Q6):** topology and PDH instance parsing handle processor groups; the Phase 1 spike includes a scripted 5,000-process frame.
5. **R-5 (Q1):** `taskman_recorder` target added as Phase 2 SHOULD.
6. **R-6 (Q10):** Phase 3 gate narrowed to rules, banner, and evidence view.
7. **R-7 (Q9):** no command lines or full paths collected in Phases 1 to 3.
8. **R-8 (stress):** disk mode uses inline C with write-through; simple_file stays out of the stress target.

---

## Acceptance Criteria (revised)

### Phase 1: See it move
- [ ] Library tests pass in the F_code test binary: readings, identity, rates, discontinuities, codec round trip, formatting, scripted sampler, budget.
- [ ] A target containing only the `probe`, `model`, and `sampling` clusters compiles (Q7).
- [ ] The native table passes its self-check here; forced to fail, the documented fallback passes the same tests.
- [ ] The window, live and in replay mode, shows the grid, heatmap, four trend tiles, capability panel, and its own overhead, and stays responsive for one hour live.
- [ ] Capability panel on this machine: temperature and battery not supported; CPU package power available.
- [ ] No reading that is not available is shown or printed as a number.
- [ ] Sampling cost at or under 1% of one logical processor over one hour; whole-process CPU and render frame times recorded.
- [ ] Scripted 5,000-process frame: grid frame time recorded.
- [ ] CLI `snapshot` and `capabilities` work; stress tool produces CPU, memory, and uncached disk load and prints its identity.

### Phase 2: Remember
- [ ] One writer per user; a second instance opens read-only and says so.
- [ ] After the stress tool exits, the scrubber shows its load and its process.
- [ ] Replay of a recorded window reproduces the recorded frames.
- [ ] Soak run: database at or under 250 MB and writes at or under 20 MB per hour, measured.
- [ ] (SHOULD) `taskman_recorder` records with no window open; the window views its file.

### Phase 3: Diagnose (MVP gate)
- [ ] Rule unit tests pass on scripted windows, including missing readings, a mid-window discontinuity, and two rules firing.
- [ ] CPU, memory, and disk scenarios: three of three runs each give the right kind and culprit, live and when scrubbed back.
- [ ] Idle gives "no bottleneck"; missing readings give "inconclusive" with the reason.
- [ ] Every found verdict shows at least one evidence item from inside its window.
- [ ] Each accepted scenario run is saved as a test fixture.

## Out of Scope

- Kernel drivers, and therefore CPU temperature on this machine
- A Windows service
- macOS and Linux
- Malware detection; handle, DLL, and stack inspection
- Benchmark suite and score
- Fan control, overclocking, RGB
- Actions on protected system processes
- Restraint without the owner asking
- Collecting command lines, full paths, or window titles (Phases 1 to 3)
- Deferred with room left: wait chains, change ledger, disk growth treemap, case-file PDF, LLM narration, power-budget rule, vendor sensors, ETW

## Dependencies (final)

base, testing (ISE); simple_testing, simple_mml, simple_logger, simple_env,
simple_widgets, simple_shell, simple_cairo, simple_datetime, simple_cli
(Phase 1); simple_sql, simple_json (Phase 2); simple_toml (Phase 3);
simple_statistics (later). System import library `pdh.lib`.

## MML Decision

**Decision:** YES-Required
**Rationale:** Eleven model queries carry the frame conditions in the spec's
postconditions. MML never appears in an invariant, which must stay O(1).
