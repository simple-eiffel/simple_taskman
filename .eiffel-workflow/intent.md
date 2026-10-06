# Intent: simple_taskman

Date: 2026-10-03
Pre-populated from `spec/01-PARSED-REQUIREMENTS.md`, `spec/03-CHALLENGED-ASSUMPTIONS.md`,
and `spec/07-SPECIFICATION.md`, all completed earlier today. Nothing here is new
scope; it is the spec restated as intent.

## What

A diagnostic task manager for Windows, written in Eiffel, that answers *why*
the computer is slow, including after the slowdown has ended.

It has four parts:

1. **A headless library** that measures the machine honestly: every process
   with CPU, memory, and disk activity; per-core CPU; memory pressure; disk
   activity; CPU package power where the hardware exposes it. A reading the
   machine cannot supply says why ("not supported", "access denied"), never 0.
2. **A recorder** that keeps a rolling history in a SQLite file, so the owner
   can look back at what happened at 2 PM.
3. **A rule engine** that turns a window of history into one plain sentence
   naming the bottleneck and the responsible process, with the evidence behind
   it, or says honestly that the evidence is not enough.
4. **A simple_widgets window** that shows all of this, built first and grown
   phase by phase: live view (Phase 1), history scrubber (Phase 2), verdict
   banner and cause chain (Phase 3).

Later phases add reversible remedies with proof that they helped (Phase 4)
and publication as a simple_* library and product (Phase 5).

## Why

- Existing task managers report measurements and leave diagnosis to the human.
  They forget everything the moment the incident ends.
- TMOG (Dave Plummer, 2026) added a flight recorder but still leaves the
  reasoning to the person reading the graphs. No surveyed tool states a
  verdict in words, measures whether a remedy worked, or lets the owner
  declare what "healthy" means.
- Eiffel fits the problem unusually well: "a missing reading is not zero" is a
  precondition, "a pid is not an identity" is a class, and "the monitor must
  not become the problem" is an invariant on its own overhead.
- Larry's goals: a personal tool that proves the idea, then an Eiffel showcase
  published as another simple_* library and product.

## Users

| User | How they use it |
|------|-----------------|
| Larry (owner, developer) | Runs the window daily; scrubs back to incidents; scripts the CLI; extends rules |
| Family tech-support person | Opens the recording after the fact and reads the verdict |
| Eiffel developers | Use the headless library from their own programs; read it as a DBC and SCOOP example |

## Acceptance Criteria

### Phase 1: See it move
- [ ] Library tests pass in the F_code test binary: readings, identity, rates, discontinuities, codec round trip, formatting, scripted sampler.
- [ ] The native process table passes its self-check on this machine; when forced to fail, the documented fallback passes the same tests.
- [ ] The window shows the process grid, per-core heatmap, four trend tiles, the capability panel, and its own overhead, and stays responsive for one hour.
- [ ] On this machine the capability panel shows temperature and battery as not supported, and CPU package power as available.
- [ ] No reading that is not available is ever shown or printed as a number.
- [ ] The CLI prints `snapshot` and `capabilities`; the stress tool runs CPU, memory, and disk loads and prints its own identity.
- [ ] Measured sampling overhead is at or under 1% of one logical processor over one hour.

### Phase 2: Remember
- [ ] After the stress tool exits, dragging the scrubber back shows its load and its process.
- [ ] A recorded window, replayed, produces the same frames as were recorded.
- [ ] Database size and write rate are measured over a soak run and stay inside 250 MB and 20 MB per hour.

### Phase 3: Diagnose (the MVP gate)
- [ ] CPU, memory, and disk stress scenarios each produce the right verdict kind and name the stress tool as culprit, live and when scrubbed back after the fact.
- [ ] An idle machine produces "no bottleneck"; a window with missing readings produces "inconclusive" with the reason.
- [ ] Every verdict that names a bottleneck shows at least one evidence item from inside its window.

## Out of Scope

- Kernel drivers, and therefore CPU temperature on this machine
- macOS and Linux
- Malware detection, handle and DLL inspection, kernel stack traces
- Benchmark suite and composite score
- Fan control, overclocking, RGB
- Any action on protected system processes
- Restraining a process without the owner asking (no automatic restraint)
- Wait chains, change ledger, disk growth treemap, case-file PDF, LLM narration, power-budget rule, vendor sensor sources, ETW (deferred, room left in the design)

## Dependencies (simple_* First Policy)

| Need | Library | Justification |
|------|---------|---------------|
| Kernel types | base (ISE) | No simple_* equivalent; allowed |
| Test framework integration | testing (ISE) | Allowed; paired with simple_testing |
| Test assertions | simple_testing | `TEST_SET_BASE` |
| Model-based contracts | simple_mml | MML postconditions |
| Library diagnostics | simple_logger | Optional, injected |
| GUI | simple_widgets, simple_shell, simple_cairo | The ecosystem's Win32 drawn toolkit |
| Time labels | simple_datetime | Formatting only; sampling time is our own 100 ns clock |
| CLI parsing | simple_cli | CLI and stress targets |
| Stress tool disk mode | simple_file | Write, read, delete a large file |
| Recorder | simple_sql | SQLite, WAL |
| Export | simple_json | Phase 2 |
| Machine contracts | simple_toml | Phase 3 |
| Baselines | simple_statistics | Later |
| Win32 process table, performance counters, clocks | none: our own inline C | No simple_* or ISE library covers it (verified by grep during research) |

## MML Decision

**Decision:** YES-Required
**Rationale:** The spec's postconditions use 11 model queries for frame
conditions (readings map, frame identities, window sequence, verdict evidence,
and others). MML stays out of invariants, which must be O(1).
