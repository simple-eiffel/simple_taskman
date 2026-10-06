# INNOVATIONS: simple_taskman

Date: 2026-10-03

Each item states honestly what prior art exists. "Novelty" is relative to the
tools surveyed in 02-LANDSCAPE.md, not a claim about every tool ever written.

## What Makes This Different

### I-001: The verdict comes first
**Problem Solved:** Monitors show graphs and leave the reasoning to the reader.
**Approach:** A rule engine classifies the bottleneck, names the culprit identity, and emits one sentence with the readings that justify it. Graphs become the supporting exhibits.
**Novelty:** None of TMOG, Task Manager, Process Lasso, or System Informer documents an automated plain-language verdict. TMOG's site lists no AI or diagnosis feature; its own video says the human follows the evidence.
**Prior art:** Not searched for specifically. Verdict-like features in other tools may exist outside the tools surveyed; treat this novelty claim as "not found", not "does not exist".
**Design Impact:** `TM_VERDICT` is the central output type; every UI is a rendering of it. Inconclusive is a legal verdict.

### I-002: Felt lag as the dependent variable
**Problem Solved:** "Slow" is the symptom, yet nobody measures it; they measure resources and hope they correlate.
**Approach:** A probe times a null message to the foreground window and keeps the per-interval maximum. Every resource reading is then judged by whether it explains that signal.
**Novelty:** Microsoft built this exact metric (User Input Delay) for Remote Desktop hosts and wrote the argument for it. It is absent on this client machine and no surveyed task manager shows it. Using it as the axis that all other readings are correlated against is the new part.
**Prior art:** Microsoft User Input Delay counters; the 5-second "not responding" test behind `IsHungAppWindow`.
**Design Impact:** A `responsiveness` reading exists beside CPU, memory, disk. Rules can require "lag elevated" before declaring a problem, which suppresses false alarms on a busy but responsive machine.
**Evidence so far:** Mechanism works (120 of 120 sends, 12 windows, standard user). Not yet shown to rise under load.

### I-003: Proof by intervention
**Problem Solved:** Correlation names suspects; it does not convict.
**Approach:** Restrain the suspect for a few seconds, record lag and bottleneck readings before, during, and after, restore, and report confirmed, not confirmed, or inconclusive.
**Novelty:** Efficiency mode and ProBalance both restrain. Neither documents measuring whether the restraint fixed the symptom. Microsoft's own blog measured the benefit only in a lab.
**Prior art:** The restraint mechanisms themselves; A/B testing as a general idea.
**Design Impact:** `TM_EXPERIMENT` object with three windows and a result, stored in the trace. Requires I-002 to have something to measure.

### I-004: Sentence, not execution
**Problem Solved:** "End task" is the only remedy most users know.
**Approach:** A ladder of reversible restraints (EcoQoS, priority, CPU cap) offered before terminate. Each applied restraint yields a receipt holding the prior state, and undo is contractually exact.
**Novelty:** Low for the mechanisms; this is Efficiency mode and ProBalance. The receipt, journaled undo across a crash, and the postcondition "state after undo equals state before apply" are the additions.
**Prior art:** Task Manager Efficiency mode, Process Lasso.
**Design Impact:** `TM_RESTRAINT` deferred class with `apply`, `undo`, `prior_state`; a journal file.

### I-005: The machine has a contract
**Problem Solved:** "Slow" is a comparison with no stated baseline.
**Approach:** The owner declares or accepts invariants for the machine, such as commit below 90%, idle package power below a bound, lag maximum below a bound. A violation is an incident: timestamped, with culprit and a pinned evidence window. This is Design by Contract applied to the computer as the object.
**Novelty:** Alert thresholds are old in server monitoring. For a desktop task manager, and framed as invariants whose violation captures a replayable evidence window like an exception trace, no surveyed tool does it.
**Prior art:** Threshold alarms in server monitoring (general knowledge, not researched here); Daikon-style likely-invariant inference for the "propose contracts from baseline" part (search hit).
**Design Impact:** `TM_CONTRACT`, `TM_INCIDENT`; contracts loaded from TOML against a registry of reading names.

### I-006: The trace is a database and a test fixture
**Problem Solved:** Proprietary traces can only be opened by the tool that wrote them.
**Approach:** History is a SQLite file. A recorded incident can be queried with SQL, exported as JSON, and replayed through the diagnosis engine offline.
**Novelty:** TMOG's `.tmogtrace` is its own format. Replay-as-regression-test means every real incident Larry captures becomes a permanent test of the rules.
**Prior art:** Windows SRUM is an ESE database flushed hourly (search hit). ETW traces opened in Windows Performance Analyzer are a further likely precedent; that was not researched in this pass.
**Design Impact:** Diagnosis takes a window, never the live machine. Probes and clock are injected.

### I-007: Honest telemetry enforced by the language
**Problem Solved:** Plotting zero for a missing sensor; acting on a recycled pid. Plummer calls these the unglamorous details that separate instruments from dashboards.
**Approach:** A reading cannot yield a value unless `is_available`; the precondition makes misuse a contract violation in tests. A process identity is a class, and actions verify it on an open handle.
**Novelty:** TMOG does both by discipline. Here the compiler and contracts enforce them, and five distinct reasons for absence are preserved.
**Prior art:** TMOG (gaps, pid plus creation identity); Windows `SequenceNumber`.
**Design Impact:** D-006 and D-007. The local probe already produced a live example: three GPU counter values of about 1.8e19 that must be classed invalid.

### I-008: A monitor under contract to itself
**Problem Solved:** The task manager becoming the problem.
**Approach:** The tool measures its own CPU share and memory every tick and holds an overhead bound. When it is exceeded the sampler backs off and logs the fact.
**Novelty:** TMOG can display itself. An enforced self-budget with automatic back-off is not described by any surveyed tool.
**Design Impact:** NFR-006; `own_overhead` is a reading like any other.

### I-009: Power-budget arithmetic
**Problem Solved:** Plummer's Ryzen story: CPU and GPU each fine alone, slow together, because of a shared power limit he found by luck.
**Approach:** Learn the peak draw of each domain separately; flag when the combined draw is materially below the sum while both are loaded.
**Novelty:** A named, automated check for something a human spotted by staring.
**Prior art:** None found in the survey.
**Design Impact:** One rule. **Limited on this machine:** CPU package power is readable; GPU power is not without a vendor path. Ships only when a second power source exists.

### I-010: Deferred ideas, recorded so the design leaves room
- **Wait chain in plain words.** The documented wait-chain API covers ALPC, COM, critical sections, mutexes, and SendMessage. Resource Monitor already exposes it in a right-click menu, so the novelty is integration into the verdict, not the capability.
- **Change ledger.** Diff of startup items, services, drivers, and updates between "healthy" and "now".
- **Disk growth.** Diff between scans to answer "what grew", which a treemap alone cannot.
- **Case file.** One-page PDF per incident for the family-support scenario.

## Differentiation from Existing Solutions

| Aspect | Existing | Our Approach | Benefit |
|--------|----------|--------------|---------|
| Output | Graphs and a sortable list | A sentence with cited evidence | Usable by people who cannot read the graphs |
| Definition of slow | Implicit | Measured lag plus declared contracts | Fewer false alarms; a real baseline |
| Culprit | Top of the CPU column | Rule-based, resource-specific, optionally confirmed by experiment | Right process blamed |
| Remedy | Kill, or manual Efficiency mode | Reversible ladder with receipt and measured effect | Safer, and the user learns whether it worked |
| Missing data | Often zero | Typed status with reason | No lies in the graph |
| History | None, or proprietary trace | SQLite, SQL-queryable, replayable | Shareable and testable |
| Monitor overhead | Shown at best | Bounded by invariant with back-off | Tool cannot become the cause |
| Sensors | Driver required for full set | No driver; absence shown honestly | Installs anywhere; no SmartScreen or driver-blocklist fight over a kernel component |

## What is deliberately not innovative
Sampling itself, process lists, per-core graphs, treemaps, themes. These are
table stakes that TMOG and others already do well. Effort there is kept minimal.
