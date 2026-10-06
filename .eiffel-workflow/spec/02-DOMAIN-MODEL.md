# DOMAIN MODEL: simple_taskman

Date: 2026-10-03

## Domain Concepts

### Concept: Metric
**Definition:** A named kind of measurement the tool knows about, such as total CPU busy percent or CPU package watts. Known whether or not this machine can supply it.
**Attributes:** name (stable, dotted, lowercase), unit, display label, optional valid range, whether it has instances (per core, per disk, per volume).
**Behaviors:** Tells whether a raw value is inside its valid range.
**Related to:** Reading, Metric Registry, Machine Contract.
**Will become:** `TM_METRIC`

### Concept: Metric Registry
**Definition:** The single list of all metrics. The one place a metric name is decided.
**Attributes:** the metrics.
**Behaviors:** Look up by name; enumerate.
**Related to:** Metric, Capability Report, Recorder schema, Contract loader.
**Will become:** `TM_METRICS`

### Concept: Reading
**Definition:** One observation of one metric at one time: either a measured value or a stated reason why there is none.
**Attributes:** status (available, unavailable, not supported, access denied, invalid), value (only when available).
**Behaviors:** None beyond access; immutable.
**Related to:** Metric, System Readings, Series, Evidence.
**Will become:** `TM_READING`, with statuses in `TM_READING_STATUS`

### Concept: System Readings
**Definition:** All system-wide readings for one interval, keyed by metric and instance.
**Attributes:** the readings.
**Behaviors:** Reading for a metric (and instance); always answers, with status not supported if never supplied.
**Related to:** Frame, Reading, Metric.
**Will become:** `TM_READINGS`

### Concept: Process Identity
**Definition:** What makes a process the same process over time: its process number together with its creation time. A process number alone is a hotel room number.
**Attributes:** pid, creation time.
**Behaviors:** Equality and hashing over both fields.
**Related to:** Process Sample, Process Activity, Verdict, Restraint.
**Will become:** `TM_PROCESS_ID`

### Concept: Process Sample
**Definition:** The cumulative state of one process at one instant: counters since it started.
**Attributes:** identity, image name, parent pid, session, cumulative user and kernel CPU time, working set, private bytes, cumulative IO bytes read and written, threads, handles; whether the resource fields are available.
**Behaviors:** None; immutable.
**Related to:** Snapshot, Process Identity.
**Will become:** `TM_PROCESS_SAMPLE`

### Concept: Snapshot
**Definition:** Everything read from the machine at one instant: all process samples plus raw system counters.
**Attributes:** timestamp, process samples by identity, cumulative per-processor times, system gauges.
**Behaviors:** Lookup by identity.
**Related to:** Frame (two snapshots make one frame).
**Will become:** `TM_SNAPSHOT`

### Concept: Process Activity
**Definition:** What one process did during one interval: rates derived from two samples of the same identity.
**Attributes:** identity, name, CPU used in cores, CPU as percent of machine, IO read and write bytes per second, current working set, private bytes, threads, handles, whether it was born in this interval.
**Behaviors:** None; immutable.
**Related to:** Frame, Process Sample.
**Will become:** `TM_PROCESS_ACTIVITY`

### Concept: Frame
**Definition:** What the machine did between two consecutive snapshots. The unit that is displayed, recorded, transferred between processors, and diagnosed.
**Attributes:** start and end time, system readings, process activities, identities born, identities that exited.
**Behaviors:** Activity for an identity; top activities by a resource.
**Related to:** Window, Recorder, Views.
**Will become:** `TM_FRAME`

### Concept: Window
**Definition:** A time-ordered run of frames over which a question is asked.
**Attributes:** frames, start, end.
**Behaviors:** Aggregate a metric (mean, maximum, coverage); rank processes by a resource over the window.
**Related to:** Rule, Contract, Verdict, Trace Store.
**Will become:** `TM_WINDOW`

### Concept: Series
**Definition:** The history of one metric as a compact column, for drawing a trend.
**Attributes:** bounded capacity, timestamps, values, statuses.
**Behaviors:** Append; read item with status; gaps preserved.
**Related to:** Reading, trend views.
**Will become:** `TM_SERIES`

### Concept: Clock
**Definition:** The source of "now". Injected so tests and replay control time.
**Will become:** `TM_CLOCK` (deferred), `TM_SYSTEM_CLOCK`, `TM_MANUAL_CLOCK`

### Concept: Process Source
**Definition:** Where process samples come from.
**Behaviors:** Read all processes; report whether it is trusted.
**Will become:** `TM_PROCESS_SOURCE` (deferred), `TM_NATIVE_PROCESS_SOURCE`, `TM_DOCUMENTED_PROCESS_SOURCE`, and a scripted source for tests

### Concept: System Source
**Definition:** Where system-wide raw values come from.
**Will become:** `TM_SYSTEM_SOURCE` (deferred), `TM_WIN_SYSTEM_SOURCE`, built from `TM_COUNTER_QUERY`, `TM_CPU_TOPOLOGY`, and memory and volume externals

### Concept: Sampler
**Definition:** The component that reads the sources on request, keeps the previous snapshot, and produces frames. Long-lived, explicit refresh.
**Attributes:** sources, clock, last snapshot, last frame, tick cost.
**Will become:** `TM_SAMPLER`

### Concept: Capability Report
**Definition:** For every registered metric, whether this machine supplies it and, if not, why.
**Will become:** `TM_CAPABILITIES`

### Concept: Self Budget
**Definition:** The bound on the tool's own overhead and the policy for backing off.
**Attributes:** CPU bound, current interval, minimum and maximum interval.
**Behaviors:** Given measured overhead, recommend the next interval.
**Will become:** `TM_SELF_BUDGET`

### Concept: Trace Store
**Definition:** Where frames and incidents are kept and retrieved by time.
**Behaviors:** Append frame; window between two times; record and query incidents; apply retention.
**Will become:** `TM_TRACE_STORE` (deferred), `TM_SQLITE_TRACE_STORE`, `TM_MEMORY_TRACE_STORE`

### Concept: Retention Policy
**Definition:** How long each resolution is kept, the size cap, and which processes are significant enough to store.
**Will become:** `TM_RETENTION_POLICY`

### Concept: Bottleneck Kind
**Definition:** The class of problem: none, CPU saturation, memory pressure, disk saturation, power limit, hung application, inconclusive.
**Will become:** `TM_BOTTLENECK_KIND`

### Concept: Evidence
**Definition:** One fact supporting a verdict: a metric aggregate over a time range, optionally about one process, stated in words.
**Will become:** `TM_EVIDENCE`

### Concept: Verdict
**Definition:** The answer to "why is it slow": a kind, the culprit identities, one sentence, the evidence, and a confidence.
**Will become:** `TM_VERDICT`

### Concept: Rule
**Definition:** One way of recognizing one bottleneck kind in a window.
**Behaviors:** Say which metrics it needs; say whether a window lets it judge; produce a verdict.
**Will become:** `TM_RULE` (deferred), `TM_CPU_SATURATION_RULE`, `TM_MEMORY_PRESSURE_RULE`, `TM_DISK_SATURATION_RULE`

### Concept: Diagnostician
**Definition:** The holder of the rules and the precedence among them; turns a window into one verdict.
**Will become:** `TM_DIAGNOSTICIAN`

### Concept: Machine Contract
**Definition:** A declared bound on a metric that should hold for a healthy machine, with a tolerance duration.
**Will become:** `TM_CONTRACT`, loaded by `TM_CONTRACT_LOADER`

### Concept: Incident
**Definition:** A period during which a contract was violated, with culprit and evidence window.
**Will become:** `TM_INCIDENT`, opened and closed by `TM_WATCHMAN`

### Concept: Frame Handoff
**Definition:** The passing of a frame from the processor that sampled it to a processor that displays or records it, by value.
**Will become:** `TM_FRAME_CODEC`, `TM_FRAME_SLOT`, `TM_SAMPLING_WORKER`

### Concept: Restraint, Receipt, Experiment (Phase 4)
**Definition:** A reversible limit on a process; the record of prior state that makes undo exact; a timed restrain-and-observe trial.
**Will become:** `TM_RESTRAINT` (deferred) and three effective classes, `TM_ACTION_OUTCOME`, `TM_PROCESS_HANDLE`, `TM_PROTECTED_SET`, `TM_RESTRAINT_JOURNAL`, `TM_EXPERIMENT`, `TM_ELEVATION`

## Concept Relationships

```
Metric Registry ── has-many ──> Metric
Reading ── of-a ──> Metric
System Readings ── has-many ──> Reading

Snapshot ── has-many ──> Process Sample ── has-a ──> Process Identity
Frame ── derived-from ──> two Snapshots
Frame ── has-a ──> System Readings
Frame ── has-many ──> Process Activity ── has-a ──> Process Identity
Window ── has-many ──> Frame
Series ── has-many ──> Reading (compact)

Sampler ── uses ──> Process Source, System Source, Clock
Sampler ── produces ──> Frame
Native Process Source ── is-a ──> Process Source
Documented Process Source ── is-a ──> Process Source

Trace Store ── stores ──> Frame, Incident
SQLite Trace Store ── is-a ──> Trace Store
Memory Trace Store ── is-a ──> Trace Store

Rule ── reads ──> Window
Rule ── produces ──> Verdict ── has-many ──> Evidence
Diagnostician ── has-many ──> Rule
Contract ── refers-to ──> Metric
Watchman ── evaluates ──> Contract ── opens ──> Incident ── has-a ──> Verdict

Restraint ── targets ──> Process Identity
Restraint ── yields ──> Action Outcome
```

## Domain Rules

| Rule | Description | Enforcement |
|------|-------------|-------------|
| DR-001 | A reading has a value if and only if its status is available | Precondition on `value`; class invariant on `TM_READING`; `CHECK` constraint in the recorder schema |
| DR-002 | An available value is finite and inside its metric's valid range; otherwise the reading is invalid | Postcondition of the measuring creation procedure |
| DR-003 | A process is identified by pid and creation time together | `is_equal` and `hash_code` of `TM_PROCESS_ID` |
| DR-004 | A rate is computed only between two samples of the same identity | Precondition of `TM_PROCESS_ACTIVITY` creation |
| DR-005 | A frame spans positive time | Invariant `end_time > start_time` |
| DR-006 | Frames in a window are in time order and do not overlap | Precondition of `extend`; O(1) check against the last frame |
| DR-007 | Commit charge never exceeds commit limit when both are available | Postcondition of the system source |
| DR-008 | CPU used by one process in an interval cannot exceed the machine's capacity; beyond tolerance it is invalid, not clamped silently | Postcondition and status |
| DR-009 | A native process source is read only after its layout self-check passed | Precondition `is_trusted` |
| DR-010 | A verdict that names a bottleneck carries at least one evidence item, and all its evidence lies inside its window | Invariant (count check); postcondition of each rule |
| DR-011 | A verdict of kind none or inconclusive names no culprit | Invariant |
| DR-012 | A contract refers only to registered metric names | Precondition of contract creation; loader reports unknown names as errors |
| DR-013 | An incident's end is not before its start; an open incident has no end | Invariant |
| DR-014 | A restraint is applied to an identity verified on an open handle, never to a bare pid | Precondition on `apply` |
| DR-015 | A protected process is never restrained or terminated | Precondition |
| DR-016 | After undo, the process attribute equals the recorded prior state | Postcondition of `undo` |
| DR-017 | Text shown for a reading that is not available is never a number | Postcondition of the one formatting feature all views use |
| DR-018 | A frame decoded from its encoded form equals the original | Postcondition of the codec; round-trip test |
| DR-019 | A handed-off block has exactly one owner at a time and is freed exactly once | Slot contracts; ownership stated in each feature's header comment |
| DR-020 | Downsampling never invents data: an aggregate records how much of its interval was actually measured | `coverage` column and attribute |

Invariants above are all O(1) (C-011). Rules that quantify over collections
(DR-006 in full, DR-010's "all evidence inside window") are stated as
postconditions with MML model queries, not as invariants.

## Glossary

| Term | Definition |
|------|------------|
| Tick | One sampling cycle |
| Ticks (time unit) | 100-nanosecond units, the Windows file-time unit; all timestamps are `INTEGER_64` counts of these in UTC |
| Snapshot | Raw cumulative state at one instant |
| Frame | Derived activity between two snapshots |
| Window | A run of frames |
| Reading | Value or reason for no value |
| Available | Measured and valid |
| Unavailable | The source exists but gave nothing this tick |
| Not supported | This machine has no such source |
| Access denied | The source exists but our rights do not reach it |
| Invalid | The source returned a value that cannot be true |
| Identity | Pid plus creation time |
| Culprit | Identity a verdict holds responsible |
| Bottleneck | The resource whose exhaustion explains the slowness |
| Cores (unit) | CPU use measured in logical processors' worth; 1.0 means one processor fully busy |
| Coverage | Fraction of an interval for which a reading was available |
| Handoff | Transfer of a frame between SCOOP processors by value |
| Restraint | Reversible limit on a process |
| Receipt | Recorded prior state that makes undo exact |
| Incident | Period of contract violation |
| Trusted | Layout self-check passed |
