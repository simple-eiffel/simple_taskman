# CLASS DESIGN: simple_taskman

Date: 2026-10-03

Phase tags: **P1** see it move, **P2** remember, **P3** diagnose, **P4** act and
prove. Only P1 classes are specified to full contract depth in
`07-SPECIFICATION.md`; P2 and P3 are specified at interface level; P4 at
inventory level, so the design leaves room without pretending to be finished.

## Layering

```
  app (GUI)  cli  stress            <- application targets; may print or draw
      |       |      |
  handoff (SCOOP)                   <- the only cluster that knows `separate`
      |
  SIMPLE_TASKMAN (facade)
      |
  diagnosis  recorder  action       <- pure or I/O-owning, all sequential
      \        |        /
         sampling
            |
          model                     <- pure value classes, no externals
            |
          probe                     <- the only cluster with Win32 externals
```

Rules that keep it clean:
- `model` depends on nothing but base and simple_mml. `TM_FORMAT` lives here because the GUI, the CLI, and the verdict sentences must all format the same way.
- `probe` depends on `model`; it is the only place with `external`. Fake sources live in `probe/scripted` so tests need no Windows calls.
- `diagnosis` consumes `TM_WINDOW` only. It never sees a source, a clock, or a store (NFR-010).
- Only `handoff` and the three application roots use `separate`.
- The library never prints (FR-NEW-008). Diagnostics go to an optional `SIMPLE_LOGGER`.

## Class Inventory

### model (pure)

| Class | Phase | Role | Single Responsibility |
|-------|-------|------|----------------------|
| `TM_READING_STATUS` | P1 | Constants | The five statuses and their names |
| `TM_READING` | P1 | Value | One value, or the reason there is none |
| `TM_METRIC` | P1 | Value | What a metric is: name, unit, valid range, aggregation |
| `TM_METRICS` | P1 | Registry | The one list of metrics and their codes (single choice) |
| `TM_SHARED_METRICS` | P1 | Mixin | Exports `metrics` as a per-processor `once` |
| `TM_READINGS` | P1 | Collection | Readings for one interval, keyed by metric and instance |
| `TM_PROCESS_ID` | P1 | Value | Pid plus creation time |
| `TM_PROCESS_SAMPLE` | P1 | Value | One process's cumulative counters at an instant |
| `TM_SNAPSHOT` | P1 | Value | All samples and readings at an instant |
| `TM_RESOURCE` | P1 | Constants | CPU, memory, IO read, IO write, IO total |
| `TM_PROCESS_ACTIVITY` | P1 | Value | One process's rates over one interval |
| `TM_FRAME` | P1 | Value | What the machine did between two snapshots |
| `TM_SERIES` | P1 | Ring buffer | Compact history of one metric for a trend |
| `TM_AGGREGATE` | P1 | Value | An aggregate value with its coverage |
| `TM_WINDOW` | P1 | Collection | Time-ordered frames; aggregation and ranking |
| `TM_PROCESS_TOTAL` | P1 | Value | One identity's totals over a window |
| `TM_CLOCK` | P1 | Deferred | UTC ticks and monotonic ticks |
| `TM_FORMAT` | P1 | Text | The one place a reading or rate becomes text, used by GUI, CLI, and verdict sentences (DR-017) |
| `TM_MANUAL_CLOCK` | P1 | Effective | Clock set by tests and replay |

### probe (Win32, plus scripted fakes)

| Class | Phase | Role | Single Responsibility |
|-------|-------|------|----------------------|
| `TM_SYSTEM_CLOCK` | P1 | Effective clock | `GetSystemTimePreciseAsFileTime`, `QueryPerformanceCounter`, blocking sleep |
| `TM_PROCESS_SOURCE` | P1 | Deferred | Read all process samples |
| `TM_NATIVE_PROCESS_SOURCE` | P1 | Effective | One native call; layout self-check |
| `TM_DOCUMENTED_PROCESS_SOURCE` | P1 | Effective | Toolhelp plus per-process documented calls; fallback |
| `TM_SELF_CHECK` | P1 | Value | Result of the native layout check: ran, passed, failing field, bracketing values |
| `TM_SYSTEM_SOURCE` | P1 | Deferred | Read system readings; declare support per metric |
| `TM_WIN_SYSTEM_SOURCE` | P1 | Effective | Compose counters, topology, memory, volumes |
| `TM_COUNTER_QUERY` | P1 | Wrapper | One PDH query: add English counters, collect, read arrays |
| `TM_COUNTER_VALUE` | P1 | Value | One counter instance's value and PDH status |
| `TM_CPU_TOPOLOGY` | P1 | Value | Logical processor count and efficiency class per processor |
| `TM_SCRIPTED_PROCESS_SOURCE` | P1 | Fake | Replays a script of samples for tests |
| `TM_SCRIPTED_SYSTEM_SOURCE` | P1 | Fake | Replays a script of readings for tests |
| `TM_PATHS` | P1 | Platform | Per-user folders under `LOCALAPPDATA`: trace, logs (R-3) |
| `TM_SINGLE_WRITER` | P2 | Platform | Per-session named mutex: one recorder per user (R-3, intent Q2) |

### sampling

| Class | Phase | Role | Single Responsibility |
|-------|-------|------|----------------------|
| `TM_FRAME_BUILDER` | P1 | Engine (pure) | Two snapshots into one frame |
| `TM_SAMPLER` | P1 | Engine | Long-lived, explicit refresh; keeps previous snapshot; emits frames and discontinuities |
| `TM_SELF_BUDGET` | P1 | Policy | The tool's own overhead bound and back-off |
| `TM_CAPABILITIES` | P1 | Report | Per metric: supported or not, and why |

### handoff (SCOOP)

| Class | Phase | Role | Single Responsibility |
|-------|-------|------|----------------------|
| `TM_FRAME_CODEC` | P1 | Codec (pure) | Frame to text and back, lossless, versioned |
| `TM_FRAME_SLOT` | P1 | Mailbox | Never-blocking latest-frame mailbox on its own processor |
| `TM_FRAME_FILE_REPLAYER` | P1 | Worker | Feeds frames from a file into the slot at the interval, in place of sampling (R-2) |
| `TM_SAMPLING_WORKER` | P1 | Worker | Sampling loop on its own processor; (P2) owns the recorder |

### facade

| Class | Phase | Role | Single Responsibility |
|-------|-------|------|----------------------|
| `SIMPLE_TASKMAN` | P1 | Facade | Headless entry point; coordinates sampler, store, diagnostician |

### recorder

| Class | Phase | Role | Single Responsibility |
|-------|-------|------|----------------------|
| `TM_TRACE_STORE` | P2 | Deferred | Append frames; retrieve windows and frames by time |
| `TM_SQLITE_TRACE_STORE` | P2 | Effective | SQLite schema, batching, writer and reader modes |
| `TM_MEMORY_TRACE_STORE` | P2 | Effective | In-memory store for tests and replay |
| `TM_RETENTION_POLICY` | P2 | Policy | Tiers, size cap, significance thresholds |
| `TM_FRAME_MERGER` | P2 | Engine (pure) | Merge consecutive frames for downsampling |
| `TM_TRACE_EXPORTER` | P2 | Exporter | Window to JSON, with redaction |

### diagnosis

| Class | Phase | Role | Single Responsibility |
|-------|-------|------|----------------------|
| `TM_BOTTLENECK_KIND` | P3 | Constants | Kinds and precedence |
| `TM_EVIDENCE` | P3 | Value | One supporting fact |
| `TM_CULPRIT` | P3 | Value | Display name plus identities |
| `TM_VERDICT` | P3 | Result | Kind, culprits, sentence, evidence, confidence |
| `TM_RULE` | P3 | Deferred | Recognize one kind in a window |
| `TM_CPU_SATURATION_RULE` | P3 | Effective | Machine-level CPU saturation |
| `TM_MEMORY_PRESSURE_RULE` | P3 | Effective | Commit or physical memory exhaustion with paging |
| `TM_DISK_SATURATION_RULE` | P3 | Effective | A physical disk busy most of the window |
| `TM_RULE_THRESHOLDS` | P3 | Config | Every numeric threshold in one place |
| `TM_DIAGNOSTICIAN` | P3 | Engine | Run rules, apply precedence, produce one verdict |
| `TM_SENTENCE_WRITER` | P3 | Text | The only place verdict wording is decided |
| `TM_CONTRACT`, `TM_CONTRACT_LOADER`, `TM_WATCHMAN`, `TM_INCIDENT` | P3 | Contracts | Machine contracts and incidents (SHOULD) |
| `TM_LAG_PROBE`, `TM_WIN_LAG_PROBE` | P3 | Probe | Felt lag, after its spike (SHOULD) |

### action (P4, inventory only)

`TM_PROCESS_HANDLE` (open with stated rights; verify identity on the handle),
`TM_PROTECTED_SET`, `TM_ACTION_OUTCOME`, `TM_RESTRAINT` (deferred),
`TM_ECO_QOS_RESTRAINT`, `TM_PRIORITY_RESTRAINT`, `TM_CPU_CAP_RESTRAINT`,
`TM_TERMINATOR`, `TM_RESTRAINT_JOURNAL`, `TM_EXPERIMENT`, `TM_ELEVATION`.

### Application targets

| Class | Target | Phase | Role |
|-------|--------|-------|------|
| `TM_APP` | `taskman` | P1 | GUI root: window, views, worker start and stop, tick |
| `TM_PROCESS_ROW` | `taskman` | P1 | Preformatted grid row with sort keys (A-106) |
| `TM_PROCESS_VIEW` | `taskman` | P1 | Process grid; selection follows identity (A-107) |
| `TM_CORE_VIEW` | `taskman` | P1 | Per-core heatmap labeled by efficiency class |
| `TM_TREND_VIEW` | `taskman` | P1 | Statistic tile plus sparkline per headline metric |
| `TM_CAPABILITY_VIEW` | `taskman` | P1 | What this machine can and cannot measure |
| `TM_SCRUB_VIEW`, `TM_INCIDENT_VIEW` | `taskman` | P2/P3 | Slider over recorded time; incident list |
| `TM_VERDICT_VIEW`, `TM_CAUSE_VIEW` | `taskman` | P3 | Verdict banner; Sankey cause chain |
| `TM_CLI` | `taskman_cli` | P1 | `snapshot`, `capabilities` |
| `TM_STRESS`, `TM_SPINNER`, `TM_DISK_LOAD` | `taskman_stress` | P1 | CPU, memory, uncached disk loads; prints its own identity |
| `TM_RECORDER_APP` | `taskman_recorder` | P2 SHOULD | Headless recorder: sampling worker plus store, no window (R-5) |
| `TEST_APP`, `LIB_TESTS`, `TEST_*` | `simple_taskman_tests` | P1+ | Test runner and test sets |

**Count:** see the tally at the end of `08-VALIDATION.md`.

## Facade Design: SIMPLE_TASKMAN

**Purpose:** Headless entry point for any Eiffel program: sample, inspect, (P2) record and look back, (P3) diagnose.
**Responsibility:** Coordinate. It owns a sampler and, optionally, a store and a diagnostician. It holds no measurement logic.

**Public interface (P1, with P2 and P3 additions marked):**
```eiffel
class SIMPLE_TASKMAN

create
    make, make_with_sources

feature -- Configuration
    set_nominal_interval (a_ms: INTEGER): like Current
    set_logger (a_logger: SIMPLE_LOGGER): like Current
    attach_store (a_store: TM_TRACE_STORE): like Current          -- P2

feature -- Sampling
    sample
        -- Read the machine once; make a frame if a previous snapshot exists.

feature -- Access
    last_frame: TM_FRAME
    capabilities: TM_CAPABILITIES
    process_source_kind: STRING_8
    self_id: TM_PROCESS_ID
    window_between (a_from, a_to: INTEGER_64): TM_WINDOW          -- P2
    diagnose (a_window: TM_WINDOW): TM_VERDICT                    -- P3

feature -- Status
    has_frame: BOOLEAN
    is_process_source_trusted: BOOLEAN
    has_store: BOOLEAN                                            -- P2
    is_closed: BOOLEAN

feature -- Termination
    close
```

**Hides:** `TM_SAMPLER`, `TM_FRAME_BUILDER`, both process sources and the fallback decision, `TM_WIN_SYSTEM_SOURCE`, `TM_COUNTER_QUERY`, `TM_SYSTEM_CLOCK`.

## Engine Design: TM_SAMPLER

**Purpose:** sysinfo's model (research, landscape): one long-lived object, explicit refresh, deltas between consecutive reads.
**Responsibility:** Turn source reads into snapshots and consecutive snapshots into frames.

```eiffel
class TM_SAMPLER
create make
feature
    sample
    has_frame: BOOLEAN
    last_frame: TM_FRAME
    last_snapshot: TM_SNAPSHOT
    last_tick_cost: INTEGER_64          -- monotonic ticks spent in `sample'
    frames_made: INTEGER
    discontinuities: INTEGER
    nominal_interval: INTEGER_64        -- ticks
    set_nominal_interval (a_ticks: INTEGER_64)
end
```

Discontinuity rule (A-110): if the monotonic gap exceeds `Gap_factor * nominal_interval` (`Gap_factor = 5`), the frame is a discontinuity frame: no activities, every reading unavailable.

## Engine Design: TM_FRAME_BUILDER (pure)

```eiffel
class TM_FRAME_BUILDER
feature
    build (a_previous, a_current: TM_SNAPSHOT; a_logical_processors: INTEGER;
           a_self: TM_PROCESS_ID; a_previous_cost: INTEGER_64): TM_FRAME
    discontinuity (a_previous, a_current: TM_SNAPSHOT): TM_FRAME
end
```

Rates: CPU cores = delta(user + kernel ticks) / delta(monotonic ticks). CPU
percent of machine = cores / logical processors * 100. IO bytes per second =
delta(transfer bytes) / seconds. An identity present only in `a_current` is
*born* (no rates; status unavailable for CPU and IO this frame). An identity
present only in `a_previous` has *exited*. A cores value above
`logical_processors * 1.05` makes that activity's CPU status invalid (DR-008).
Pid 0 is excluded (A-111).

## Data Class Design: TM_READING

**Immutable:** YES

```eiffel
class TM_READING
create
    make_measured, make_unavailable, make_not_supported, make_access_denied, make_invalid
feature
    status: INTEGER
    value: REAL_64            -- require is_available
    is_available, is_unavailable, is_not_supported, is_access_denied, is_invalid: BOOLEAN
    status_name: STRING_8
invariant
    status_known: status >= {TM_READING_STATUS}.Available and status <= {TM_READING_STATUS}.Invalid
    value_only_when_available: not is_available implies stored_value = 0.0
    available_is_finite: is_available implies not (stored_value.is_nan or stored_value.is_positive_infinity or stored_value.is_negative_infinity)
end
```

`make_measured (a_value; a_metric)` classifies: finite and inside the metric's
range gives available, anything else gives invalid (DR-002). There is no
creation that takes a bare number without a metric, so a value cannot skip
its range check.

## Data Class Design: TM_PROCESS_ID

```eiffel
class TM_PROCESS_ID
inherit HASHABLE redefine is_equal end
create make
feature
    pid: INTEGER_64
    creation_ticks: INTEGER_64
    hash_code: INTEGER
    is_equal (other: like Current): BOOLEAN
    is_idle_pseudo_process: BOOLEAN    -- pid = 0
end
```

## Data Class Design: TM_FRAME

```eiffel
class TM_FRAME
create make, make_discontinuity
feature
    start_ticks, end_ticks: INTEGER_64      -- UTC
    duration: INTEGER_64                    -- monotonic, > 0
    logical_processors: INTEGER
    is_discontinuity: BOOLEAN
    is_complete: BOOLEAN                    -- False when decoded from a recording
    omitted_processes: INTEGER
    readings: TM_READINGS
    activity_count: INTEGER
    has_activity (a_id: TM_PROCESS_ID): BOOLEAN
    activity (a_id: TM_PROCESS_ID): TM_PROCESS_ACTIVITY
    activities: ARRAYED_LIST [TM_PROCESS_ACTIVITY]    -- a fresh copy each call
    top_by (a_resource, a_count: INTEGER): ARRAYED_LIST [TM_PROCESS_ACTIVITY]
    born: ARRAYED_LIST [TM_PROCESS_ID]
    exited: ARRAYED_LIST [TM_PROCESS_SAMPLE]
end
```

## Handoff Design (SCOOP)

Pattern taken from simple_chat (`apps/client/client_app.e:1161-1201`,
`src/client/summary_slot.e`), the only proven SCOOP plus simple_widgets
application in the ecosystem.

```
GUI processor (TM_APP)                 slot processor            worker processor
-----------------------                ----------------          -------------------------
create slot: separate TM_FRAME_SLOT -> TM_FRAME_SLOT
create worker: separate TM_SAMPLING_WORKER -------------------->  TM_SAMPLING_WORKER.make
attach (worker, slot)  -------------------------------------->   slot := a_slot
launch (worker)   -- async, returns at once ------------------>   run: loop
                                                                    sample (own sources)
                                                                    text := codec.encode
                                       put_frame (text) <------     deposit (slot, text)  [short lock]
                                                                    (P2) store.append
                                                                    sleep (blocking external)
                                                                    exit when should_stop (slot)
on_tick (every 250 ms):
  collect (slot) ------------------->  frame_text, clear
  copy, decode, update views
on close:
  request_stop (slot) -------------->  stop_requested := True
```

- The slot's routines are only field reads and assignments, so a GUI call to it returns in one call's time and never queues behind sampling.
- The worker never holds the slot across a sample: `run` keeps the slot in an attribute and locks it only inside `deposit` and `should_stop`, each a routine with a `separate` argument (scoop.md, "The Separate Argument Rule").
- Only text crosses: `make_from_separate` copies it on arrival (ISE base, `readable_string_8.e:161`).
- The slot keeps the latest frame. A frame not taken before the next one arrives counts as `dropped`. At 1 s sampling and a 250 ms tick, a drop means the GUI is stalled, which is itself worth showing.
- Capabilities cross once, as text, through the same slot.

## Recorder Design (P2)

```sql
-- schema version 1
CREATE TABLE meta      (key TEXT PRIMARY KEY, value TEXT NOT NULL);
   -- schema_version, codec_version, metric_catalog (JSON), created_utc_ticks
CREATE TABLE frames (
   id INTEGER PRIMARY KEY,
   start_ticks INTEGER NOT NULL, end_ticks INTEGER NOT NULL,
   duration_ticks INTEGER NOT NULL CHECK (duration_ticks > 0),
   tier INTEGER NOT NULL CHECK (tier IN (0, 1, 2)),
   discontinuity INTEGER NOT NULL CHECK (discontinuity IN (0, 1)),
   pinned INTEGER NOT NULL DEFAULT 0,
   process_count INTEGER NOT NULL, omitted_processes INTEGER NOT NULL,
   cpu_busy_pct REAL, cpu_busy_status INTEGER NOT NULL,
   mem_commit_pct REAL, mem_commit_status INTEGER NOT NULL,
   disk_busy_max_pct REAL, disk_busy_status INTEGER NOT NULL,
   package_watts REAL, package_watts_status INTEGER NOT NULL,
   lag_max_ms REAL, lag_status INTEGER NOT NULL,
   payload TEXT NOT NULL,                       -- TM_FRAME_CODEC text, significant processes only
   CHECK ((cpu_busy_status = 0) = (cpu_busy_pct IS NOT NULL)),
   CHECK ((mem_commit_status = 0) = (mem_commit_pct IS NOT NULL)),
   CHECK ((disk_busy_status = 0) = (disk_busy_max_pct IS NOT NULL)),
   CHECK ((package_watts_status = 0) = (package_watts IS NOT NULL)),
   CHECK ((lag_status = 0) = (lag_max_ms IS NOT NULL)));
CREATE INDEX frames_by_end ON frames (tier, end_ticks);
CREATE TABLE processes (
   frame_id INTEGER NOT NULL REFERENCES frames (id) ON DELETE CASCADE,
   pid INTEGER NOT NULL, creation_ticks INTEGER NOT NULL, name TEXT NOT NULL,
   cpu_cores REAL, cpu_status INTEGER NOT NULL,
   io_read_bps REAL, io_write_bps REAL, io_status INTEGER NOT NULL,
   private_bytes INTEGER, working_set INTEGER, memory_status INTEGER NOT NULL,
   PRIMARY KEY (frame_id, pid, creation_ticks));
CREATE INDEX processes_by_identity ON processes (pid, creation_ticks);
```

Status 0 is available. The `CHECK` pairs put DR-001 into the file format, so
a third-party writer cannot store a fake zero either.

Headline columns make the trace queryable in plain SQL (I-006). The payload
carries everything else, so the GUI and replay rebuild a full `TM_FRAME`.

Retention: tier 0 keeps 1 s frames for 1 hour; tier 1 keeps 10 s frames for
24 hours; tier 2 keeps 60 s frames for 30 days. Pinned frames are never
merged or deleted. The size cap deletes the oldest unpinned tier 2 frames
first, then reclaims pages with incremental vacuum (auto_vacuum set at
creation).

Size estimate, **not measured**: a payload with system readings plus about 20
significant processes is roughly 3 KB, so tier 0 is about 11 MB, tier 1 about
26 MB, and tier 2 about 130 MB, totaling about 167 MB, under the 250 MB cap.
That is about 11 MB of writes per hour against the 20 MB budget (NFR-004).
The Phase 2 gate replaces these numbers with measurements.

## Diagnosis Design (P3)

Precedence when several rules find something: memory pressure, then disk
saturation, then CPU saturation. Memory pressure causes paging, which shows up
as disk and CPU load, so the root cause is ranked first. Lower-precedence
findings join the verdict as secondary evidence ("also: disk 0 busy 92%").

| Rule | Needs | Finds when (defaults in `TM_RULE_THRESHOLDS`) | Culprit |
|------|-------|-----------------------------------------------|---------|
| CPU saturation | `cpu.busy_pct` | Window mean >= 85% with coverage >= 0.8 over >= 10 s | Fewest processes, or one name group, covering >= 50% of CPU used |
| Memory pressure | `mem.commit_pct`, `mem.available_bytes`, `mem.hard_faults_per_s` | (commit >= 90% or available < 5% of physical) and mean hard faults >= 200/s | Largest private-bytes growth over the window, then largest private bytes |
| Disk saturation | `disk.busy_pct` per disk | Any disk's mean busy >= 80% over >= 10 s | Largest total IO bytes; confidence at most medium (A-113) |

A rule that cannot judge (coverage too low) says so. If no rule can judge, the
verdict is inconclusive and names the missing metrics. If every rule that can
judge finds nothing, the verdict is none.

## Inheritance Hierarchy

```
TM_CLOCK*                TM_PROCESS_SOURCE*                 TM_SYSTEM_SOURCE*
  |- TM_SYSTEM_CLOCK       |- TM_NATIVE_PROCESS_SOURCE        |- TM_WIN_SYSTEM_SOURCE
  |- TM_MANUAL_CLOCK       |- TM_DOCUMENTED_PROCESS_SOURCE    |- TM_SCRIPTED_SYSTEM_SOURCE
                           |- TM_SCRIPTED_PROCESS_SOURCE

TM_TRACE_STORE*          TM_RULE*                           TM_RESTRAINT* (P4)
  |- TM_SQLITE_TRACE_STORE |- TM_CPU_SATURATION_RULE          |- TM_ECO_QOS_RESTRAINT
  |- TM_MEMORY_TRACE_STORE |- TM_MEMORY_PRESSURE_RULE         |- TM_PRIORITY_RESTRAINT
                           |- TM_DISK_SATURATION_RULE         |- TM_CPU_CAP_RESTRAINT

HASHABLE -> TM_PROCESS_ID
TM_READING_STATUS, TM_RESOURCE, TM_BOTTLENECK_KIND: constant holders, used by
qualified access ({TM_READING_STATUS}.Available), not inherited, so no class
gains a parent just to see a constant.
```

**Inheritance Justification:**
| Child | Parent | IS-A Valid? | Liskov OK? |
|-------|--------|-------------|------------|
| `TM_NATIVE_PROCESS_SOURCE` | `TM_PROCESS_SOURCE` | A way to read processes | YES; may be untrusted, which the parent's `is_trusted` already expresses |
| `TM_DOCUMENTED_PROCESS_SOURCE` | `TM_PROCESS_SOURCE` | Same | YES; may report access denied per process group, which the sample's statuses already express |
| `TM_SCRIPTED_PROCESS_SOURCE` | `TM_PROCESS_SOURCE` | Same | YES |
| `TM_WIN_SYSTEM_SOURCE`, `TM_SCRIPTED_SYSTEM_SOURCE` | `TM_SYSTEM_SOURCE` | Ways to read system readings | YES |
| `TM_SYSTEM_CLOCK`, `TM_MANUAL_CLOCK` | `TM_CLOCK` | Sources of time | YES; both keep the monotonic postcondition |
| `TM_SQLITE_TRACE_STORE`, `TM_MEMORY_TRACE_STORE` | `TM_TRACE_STORE` | Places frames are kept | YES; the SQLite reader mode refuses `append` via `is_writable`, a parent query |
| Each rule | `TM_RULE` | A way to recognize a kind | YES; each returns a verdict of its own kind or none |
| `TM_PROCESS_ID` | `HASHABLE` | Usable as a table key | YES |

## Generic Classes

None introduced. Every collection is a base library structure of a specific
element type, wrapped by the class that owns it. `TM_SERIES` is deliberately
not generic: it stores `REAL_64` and a status byte per entry, which is the
whole point (D-006).

## Class Diagram (P1 runtime)

```
┌───────────────────────────────┐        ┌──────────────────────────────┐
│ TM_APP  (GUI processor)       │ tick   │ TM_FRAME_SLOT (own processor)│
│ - window: SW_WINDOW           │──────► │ + put_frame / frame_text     │
│ - views                       │ collect│ + request_stop / stop_req.   │
│ - codec: TM_FRAME_CODEC       │        └──────────────▲───────────────┘
└───────────────────────────────┘                       │ deposit (short lock)
                                         ┌──────────────┴───────────────┐
                                         │ TM_SAMPLING_WORKER (own proc)│
                                         │ - taskman: SIMPLE_TASKMAN    │
                                         │ - codec                      │
                                         │ + run (loop)                 │
                                         └──────────────┬───────────────┘
                                                        │ owns
                                         ┌──────────────▼───────────────┐
                                         │ SIMPLE_TASKMAN (facade)      │
                                         │ - sampler: TM_SAMPLER        │
                                         └──────────────┬───────────────┘
                              ┌─────────────────────────┼──────────────────────┐
                              ▼                         ▼                      ▼
                 TM_NATIVE_PROCESS_SOURCE     TM_WIN_SYSTEM_SOURCE     TM_SYSTEM_CLOCK
                 (or documented fallback)     - TM_COUNTER_QUERY
                                              - TM_CPU_TOPOLOGY
                              │ produce
                              ▼
         TM_SNAPSHOT ──(TM_FRAME_BUILDER, two of them)──► TM_FRAME
                                                         - TM_READINGS
                                                         - TM_PROCESS_ACTIVITY *
```

## Win32 Surface (all inline C, no header of our own)

Every external uses system headers only (`windows.h`, `winternl.h`, `pdh.h`,
`pdhmsg.h`, `tlhelp32.h`, `psapi.h`). There is no `Clib/simple_taskman.h`, so
there are no header statics to fork per translation unit (C-007). All native
state (query handles, buffers, the ntdll function pointer) is a `POINTER` or
`MANAGED_POINTER` attribute of the owning object.

| Class | Calls | Blocking? (C-015) |
|-------|-------|-------------------|
| `TM_SYSTEM_CLOCK` | `GetSystemTimePreciseAsFileTime`, `QueryPerformanceCounter`, `QueryPerformanceFrequency`, `Sleep` | `Sleep` YES |
| `TM_NATIVE_PROCESS_SOURCE` | `GetModuleHandleW`, `GetProcAddress`, `NtQuerySystemInformation` (via pointer), and for the self-check `GetCurrentProcess`, `GetProcessTimes`, `GetProcessMemoryInfo`, `GetProcessIoCounters` | The native call YES |
| `TM_DOCUMENTED_PROCESS_SOURCE` | `CreateToolhelp32Snapshot`, `Process32FirstW`, `Process32NextW`, `OpenProcess`, `GetProcessTimes`, `GetProcessMemoryInfo`, `GetProcessIoCounters`, `GetProcessHandleCount`, `CloseHandle` | Snapshot YES |
| `TM_COUNTER_QUERY` | `PdhOpenQueryW`, `PdhAddEnglishCounterW`, `PdhCollectQueryData`, `PdhGetFormattedCounterArrayW`, `PdhCloseQuery` | Collect YES |
| `TM_CPU_TOPOLOGY` | `GetActiveProcessorCount (ALL_PROCESSOR_GROUPS)`, `GetLogicalProcessorInformationEx` (R-4) | no |
| `TM_SINGLE_WRITER` (P2) | `CreateMutexW`, `ReleaseMutex`, `CloseHandle` | no |
| `TM_DISK_LOAD` (stress) | `CreateFileW` (write-through, no buffering), `WriteFile`, `ReadFile`, `DeleteFileW` | write and read YES |
| `TM_WIN_SYSTEM_SOURCE` | `GlobalMemoryStatusEx`, `GetPerformanceInfo`, `GetLogicalDriveStringsW`, `GetDriveTypeW`, `GetDiskFreeSpaceExW` | `GetDiskFreeSpaceExW` YES (a sleeping USB disk can stall it; seen in the probe's drive list) |

Link: `pdh.lib` through `<external_linker_flag>` under a Windows condition,
the pattern simple_speech uses for `psapi.lib` (simple_speech.ecf:47). No ECF
in the ecosystem links pdh.lib yet. ntdll is reached through
`GetProcAddress`, as Microsoft's page asks, so it needs no import library.

### Counter catalog (English paths)

| Metric | Counter | Notes |
|--------|---------|-------|
| `cpu.busy_pct` | `\Processor Information(_Total)\% Processor Time` | PDH default cap at 100 |
| `cpu.core.busy_pct` | `\Processor Information(*)\% Processor Time` | Instances `g,n`; skip `_Total` and `g,_Total` |
| `cpu.utility_pct` | `\Processor Information(_Total)\% Processor Utility` | Frequency-aware; `PDH_FMT_NOCAP100`; valid 0..400 |
| `mem.hard_faults_per_s` | `\Memory\Page Reads/sec` | Read operations that hit disk |
| `disk.read_bps`, `disk.write_bps` | `\PhysicalDisk(*)\Disk Read Bytes/sec`, `...\Disk Write Bytes/sec` | Skip `_Total` |
| `disk.busy_pct` | `\PhysicalDisk(*)\% Idle Time` | busy = 100 - idle; `% Disk Time` exceeds 100 and is not used |
| `cpu.package_watts` | `\Energy Meter(*)\Power` | Use the instance ending `_PKG`; value in mW / 1000 (verified by arithmetic in the probe); `_Total` reads 0 and is ignored |
| `gpu.busy_pct` (stretch) | `\GPU Engine(*)\Utilization Percentage` | Separate query collected every 5th tick; busiest engine per adapter |
| `gpu.dedicated_bytes` (stretch) | `\GPU Adapter Memory(*)\Dedicated Usage` | Same slow query |
| `temperature.c` | `\Thermal Zone Information(*)\High Precision Temperature` | Tenths of kelvin; not supported when no instance (this machine) |

Memory from `GlobalMemoryStatusEx` and `GetPerformanceInfo`; volumes from
`GetDiskFreeSpaceExW` over fixed drives.

### Native process table layout (x64)

From Microsoft's documented structure (fixed fields) and the phnt headers
(the fields Microsoft calls Reserved). Offsets marked with a check were
verified by the 2026-10-03 spike; the rest are verified at run time by the
self-check before any read.

| Offset | Field | Verified |
|--------|-------|----------|
| 0x00 | NextEntryOffset (ULONG) | spike |
| 0x04 | NumberOfThreads (ULONG) | self-check (count vs own thread count) |
| 0x20 | CreateTime (LARGE_INTEGER) | spike |
| 0x28 | UserTime | spike |
| 0x30 | KernelTime | spike |
| 0x38 | ImageName.Length (USHORT, bytes) | self-check (own name) |
| 0x40 | ImageName.Buffer (PWSTR) | self-check |
| 0x48 | BasePriority (LONG) | not used in P1 |
| 0x50 | UniqueProcessId (HANDLE) | spike |
| 0x58 | InheritedFromUniqueProcessId | self-check (own parent via Toolhelp) |
| 0x60 | HandleCount (ULONG) | self-check (`GetProcessHandleCount`, bracketed) |
| 0x64 | SessionId (ULONG) | self-check (`ProcessIdToSessionId`) |
| 0x90 | WorkingSetSize (SIZE_T) | self-check (`GetProcessMemoryInfo`, bracketed) |
| 0xB8 | PagefileUsage = private bytes | self-check (`PrivateUsage`, bracketed) |
| 0xE8 | ReadTransferCount (LARGE_INTEGER) | self-check (`GetProcessIoCounters`, bracketed) |
| 0xF0 | WriteTransferCount | self-check (bracketed) |

"Bracketed" means documented value read before, native value, documented
value after; the native value must lie between the two (monotonic counters)
or within the pair's range plus a stated slack (memory). Creation time must
match exactly.
