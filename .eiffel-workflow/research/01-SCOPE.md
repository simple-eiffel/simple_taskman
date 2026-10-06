# SCOPE: simple_taskman

Date: 2026-10-03

## Step 0 input

The skill asks the user for the idea. Larry had already stated it in the session
that launched this research, so it is recorded here rather than re-asked.

- **IDEA:** A diagnostic task manager in Eiffel that answers *why* a computer is
  slow, including after the fact, in the spirit of Dave Plummer's TMOG.
- **CONTEXT:** Larry's question after the Dave's Garage video
  (`YouTube/Why Your Computer Is Slow ...md`): "Can we build one of these using
  Eiffel? What can we do that is creative in this space? Be innovative."
- **INITIAL THOUGHTS:** Do not clone TMOG. Use what Eiffel is distinctively good
  at: contracts, void safety, SCOOP. Candidate ideas were machine contracts, a
  felt-lag probe, proof by experiment, reversible remedies, verdict-first UI.
- **CONSTRAINTS:** simple_* ecosystem rules (SCOOP, void safe, inline C, simple_*
  over ISE). No kernel driver. Windows 11 development machine.

## Problem Statement

In one sentence: The problem is that system monitors report *measurements* and
leave the *diagnosis* to the human, and they forget everything the moment the
incident ends.

What's wrong today: A slow machine shows a CPU percentage, a memory number, and
a list of processes. The user must guess which resource is the bottleneck, guess
which process caused it, and then guess a remedy, which is usually "kill the top
one". If the slowdown already ended, there is nothing to look at.

Who experiences this: Anyone who owns a PC, and especially the "designated
computer person" who gets the call after the evidence is gone.

Impact of not solving: Wrong process killed, real cause untouched, problem
recurs, hardware gets blamed and replaced.

## Target Users

| User Type | Needs | Pain Level |
|-----------|-------|------------|
| Power user / developer (Larry) | See the cause, keep history, script it, trust the numbers | HIGH |
| Family tech-support person | Evidence from a machine they were not watching, in a form they can read later | HIGH |
| Non-technical owner | One plain sentence and a safe button | MED |
| Eiffel community | A showcase that DBC, void safety, and SCOOP produce better instrumentation | MED |

## Success Criteria

| Level | Criterion | Measure |
|-------|-----------|---------|
| MVP | Names the bottleneck resource correctly for synthetic CPU, memory, and disk loads | 3 of 3 scripted scenarios produce the right verdict line |
| MVP | Names the responsible process for each scenario | Verdict's culprit equals the stress tool's process identity |
| MVP | Answers "what happened at time T" after the load has ended | Query against the recorder returns the same verdict from stored data |
| MVP | Never reports a missing reading as zero | Unit tests over unavailable sensors; no code path converts unavailable to 0 |
| MVP | Monitor overhead stays inside its own budget | Self-measured CPU share and private bytes under the NFR targets for a 1-hour run |
| Full | Confirms a culprit by controlled throttling | Lag metric recovers during throttle and returns after release, recorded as an experiment |
| Full | Offers reversible remedies with a receipt | Every applied remedy can be undone and the prior state is restored exactly |
| Full | Machine contracts raise incidents | A declared invariant violation creates an incident with attached evidence window |
| MVP | GUI on simple_widgets is the host from Phase 1 | Process grid, heatmap, sparklines (Phase 1); timeline scrubber (Phase 2); verdict banner and cause chain (Phase 3) |

## Scope Boundaries

### In Scope (MUST)
- Process table sampling with stable process identity (pid plus creation time)
- System CPU (per logical processor), memory pressure, disk activity, disk free space
- CPU package power where the Energy Meter counters exist
- Readings that carry availability status, never a fake zero
- Rolling recorder in SQLite with a time-range query
- Rule-based diagnosis that outputs a verdict plus the evidence it used
- Headless library, thin CLI, and a GUI application on simple_widgets as the primary host (GUI first, decided 2026-10-03)

### In Scope (SHOULD)
- Per-process GPU utilization and GPU memory
- Foreground responsiveness probe (the "felt lag" signal)
- Machine contracts file and incident log
- Graded, reversible remedies (EcoQoS, priority, CPU cap) and the throttle experiment
- Trace export to JSON for an LLM or another person

### Out of Scope
- Kernel driver or bundled third-party driver: signing, security, and support burden; contradicts "no driver" constraint
- macOS and Linux hosts: TMOG's cross-platform reach is not the goal; Windows first
- Malware detection, handle/DLL inspection, kernel stack traces: System Informer and Process Explorer territory
- Benchmark suite and composite score: large separate product; TMOG already does it
- Fan control, overclocking, RGB: hardware-vendor territory
- Killing or throttling protected system processes: unsafe

### Deferred to Future
- Wait-chain view for hung applications: valuable, self-contained, not needed for MVP
- "What changed since it was healthy" ledger (startup items, services, drivers, updates): needs its own research
- Disk-space treemap and disk growth diff: fast version needs elevation (MFT) and its own research
- Case-file PDF and LLM narration: presentation layer on top of the verdict engine
- Temperature via vendor paths (NVML, PawnIO): only after the no-driver core is proven
- ETW kernel session for per-file disk attribution: needs admin

## Constraints

| Type | Constraint |
|------|------------|
| Technical | SCOOP-compatible, void-safe, contracts everywhere |
| Technical | Win32 access through inline C externals, no separate .c files |
| Technical | Must run as a standard user; elevation only unlocks extras |
| Technical | No kernel driver |
| Ecosystem | simple_* libraries preferred over ISE and Gobo |
| Ecosystem | F_code builds only through `ec.sh`; tests use TEST_SET_BASE assert, not `check` |
| Resource | One developer plus Claude; phased delivery, GUI first, library always testable headless |
| Hardware | Dev machine has no battery, no hybrid cores, no thermal zone instance |

## Assumptions to Validate

| ID | Assumption | Risk if False | Status |
|----|------------|---------------|--------|
| A-1 | CPU power is readable without a driver | Power story is dead | **VALIDATED on this machine** (RAPL Energy Meter counters, 61 W package, non-admin) |
| A-2 | Per-process GPU use is readable without a driver | No GPU attribution | **VALIDATED** (GPU Engine counters, 1384 instances) |
| A-3 | CPU temperature is readable without a driver | No thermal story | **FALSIFIED on this machine** (no thermal zone instance; ACPI WMI "Not supported") |
| A-4 | One system call can return CPU time, memory, IO, and creation time for all processes without opening handles | Per-process sampling becomes slow and incomplete | **VALIDATED by spike** for creation time and CPU times: native values equal the documented API for the calling process on build 26200. IO and memory offsets still to self-check in Phase 1 (see RISK-001) |
| A-5 | Timing a null message round trip to the foreground window measures felt lag | Lag probe is meaningless | **HALF VALIDATED by spike**: mechanism works, 120 of 120 sends across 12 windows, idle worst case 1.1 ms. Not yet shown to rise under load (see RISK-002) |
| A-6 | A standard user can send that null message to elevated windows | Probe blind to elevated apps | UNVALIDATED; UIPI may block it |
| A-7 | A running process can be placed under a CPU cap after the fact | "Throttle experiment" needs another mechanism | UNVALIDATED; EcoQoS and priority class are documented fallbacks |
| A-8 | Windows built-in "User Input Delay" counters exist on client Windows | We could reuse them | **FALSIFIED on this machine** (counter sets absent despite the docs' 1809+ note) |
| A-9 | 1 Hz sampling of ~350 processes fits the overhead budget | Must sample slower or sample fewer | **PARTLY VALIDATED by spike**: the process-table call costs 2.48 ms median for 349 processes (about 0.25% of one core at 1 Hz). Counter collection and Eiffel-side parsing still unmeasured |
| A-10 | A Sleep-based timer overshoot is a usable scheduler-latency probe | Secondary lag signal is noise | **FALSIFIED by spike**: idle overshoot 3.8 to 6.5 ms from timer granularity; a high-resolution timer is required |

## Research Questions

- What does TMOG actually ship, and what does it leave to the human?
- Which existing tools already throttle instead of kill, and do any of them verify the effect?
- Which Windows APIs give the needed data to a standard user with no driver?
- Does anything in ISE, Gobo, or simple_* already enumerate processes with resource data?
- Which of the proposed innovations are genuinely new, and which are prior art with a new coat of paint?
- What can this specific machine verify, and what must be tested elsewhere?
