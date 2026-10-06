# INTERFACE DESIGN: simple_taskman

Date: 2026-10-03

## Public API Summary (library, `SIMPLE_TASKMAN`)

### Creation
| Feature | Purpose | Typical Use |
|---------|---------|-------------|
| `make` | Live machine: native source if trusted, else documented; Windows system source; system clock | `create tm.make` |
| `make_with_sources (a_processes, a_system, a_clock)` | Injected sources: tests, replay, scripted demos | `create tm.make_with_sources (l_script, l_sys, l_clock)` |

### Configuration (fluent)
| Feature | Returns | Purpose |
|---------|---------|---------|
| `set_nominal_interval (a_ms)` | `like Current` | Expected time between samples; drives discontinuity detection |
| `set_logger (a_logger: SIMPLE_LOGGER)` | `like Current` | Where the library's own diagnostics go; none by default |
| `attach_store (a_store: TM_TRACE_STORE)` (P2) | `like Current` | Record every frame |

### Core Operations
| Feature | Kind | Purpose |
|---------|------|---------|
| `sample` | Command | Read the machine once |
| `close` | Command | Release counter query and store |
| `window_between (a_from, a_to)` (P2) | Query | Frames between two UTC tick values from the store |
| `diagnose (a_window)` (P3) | Query (pure) | Verdict for a window |

### Access and Status
| Feature | Returns | Purpose |
|---------|---------|---------|
| `last_frame` | `TM_FRAME` | Most recent frame; requires `has_frame` |
| `has_frame` | `BOOLEAN` | At least two samples taken |
| `capabilities` | `TM_CAPABILITIES` | What this machine supplies, and why not |
| `process_source_kind` | `STRING_8` | "native" or "documented" |
| `fallback_reason` | `STRING_32` | Why native was not used; empty when it was |
| `self_id` | `TM_PROCESS_ID` | This process, for self-overhead |
| `metrics` | `TM_METRICS` | The registry, for names and units |
| `is_closed` | `BOOLEAN` | |

### Value classes clients read

| Class | Key queries |
|-------|-------------|
| `TM_FRAME` | `start_ticks`, `end_ticks`, `duration`, `is_discontinuity`, `readings`, `activities`, `activity (id)`, `top_by (resource, n)`, `born`, `exited`, `is_complete`, `omitted_processes` |
| `TM_READINGS` | `reading (code, instance)`, `instances (code)`, `has (code, instance)` |
| `TM_READING` | `is_available`, `value` (requires available), `status`, `status_name` |
| `TM_PROCESS_ACTIVITY` | `id`, `name`, `cpu_status`, `cpu_cores`, `cpu_percent`, `io_status`, `io_read_bps`, `io_write_bps`, `memory_status`, `private_bytes`, `working_set`, `threads`, `handles`, `is_new` |
| `TM_PROCESS_ID` | `pid`, `creation_ticks`, `is_equal`, `hash_code` |
| `TM_WINDOW` | `aggregate (code, instance)`, `ranked (resource, n)`, `measured_seconds`, `count` |
| `TM_VERDICT` (P3) | `kind`, `is_found`, `sentence`, `culprits`, `evidence`, `confidence`, `reason` |

## Fluent API Example

```eiffel
show_top_processes
        -- Print the five busiest processes and the package power.
    local
        l_tm: SIMPLE_TASKMAN
        l_clock: TM_SYSTEM_CLOCK
        l_power: TM_READING
        l_format: TM_FORMAT
    do
        create l_clock.make
        create l_format
        l_tm := (create {SIMPLE_TASKMAN}.make).set_nominal_interval (1000)
        l_tm.sample
        l_clock.sleep_ms (1000)
        l_tm.sample
        if l_tm.has_frame then
            across l_tm.last_frame.top_by ({TM_RESOURCE}.Cpu, 5) as ic loop
                print (ic.name + {STRING_32} "  " + l_format.cores (ic.cpu_cores) + {STRING_32} "%N")
            end
            l_power := l_tm.last_frame.readings.reading ({TM_METRICS}.Cpu_package_watts, {STRING_32} "")
            print ({STRING_32} "Package: " + l_format.reading_text (l_power, l_tm.metrics.metric ({TM_METRICS}.Cpu_package_watts)) + {STRING_32} "%N")
        end
        l_tm.close
    end
```

- `ic.cpu_cores` is safe without a status test because `top_by` ensures every returned activity has the resource measured.
- `reading_text` is the one feature that turns a reading into text (DR-017). It prints "61.2 W" or "not supported", never a number for a missing value.
- Calling `l_power.value` directly would require `l_power.is_available` first. That precondition is the point of I-007.

## Error Handling Pattern

There are three kinds of "it did not work", and each has one channel.

| Situation | Channel | Example |
|-----------|---------|---------|
| A measurement could not be taken | A `TM_READING` or group status that is not available | Temperature on this machine reads *not supported* |
| A source call failed this tick | `last_read_succeeded` false with `last_error`; the sampler emits readings as unavailable and keeps going | `NtQuerySystemInformation` returns an NTSTATUS failure |
| A caller broke a rule | Precondition violation | Reading `value` of an unavailable reading |
| An action was refused (P4) | `TM_ACTION_OUTCOME` with a refusal kind | `needs_administrator`, `identity_changed`, `protected` |

The library raises no exceptions of its own for environmental failures.
Contract violations remain exceptions, as in every simple_* library.

## Command-Query Separation

| Feature | Type | Modifies State? | Returns Value? |
|---------|------|-----------------|----------------|
| `SIMPLE_TASKMAN.sample` | Command | YES | NO |
| `SIMPLE_TASKMAN.set_*`, `attach_store` | Command (fluent) | YES | `like Current` for chaining |
| `SIMPLE_TASKMAN.last_frame`, `capabilities` | Query | NO | YES |
| `SIMPLE_TASKMAN.diagnose` | Query | NO (pure; postcondition `pure`) | YES |
| `TM_PROCESS_SOURCE.read_all` | Command | YES | NO; result in `last_samples` |
| `TM_SYSTEM_SOURCE.refresh` | Command | YES | NO; result in `last_readings` |
| `TM_COUNTER_QUERY.add_english` | Command returning an index | YES | YES (**CQS exception**: the counter index is the handle to what was added, like a creation result) |
| `TM_FRAME_CODEC.encode` | Query | NO | YES |
| `TM_FRAME_CODEC.decode` | Command | YES | NO; result in `last_frame`, `last_error` |
| `TM_FRAME_SLOT.put_frame`, `clear`, `request_stop` | Command | YES | NO |
| `TM_FRAME_SLOT.frame_text`, `has_frame`, `stop_requested` | Query | NO | YES |
| `TM_SAMPLING_WORKER.run` | Command | YES | NO |
| `TM_RESTRAINT.apply`, `undo` (P4) | Command returning an outcome | YES | YES (**CQS exception**, the receipt pattern; the outcome is also kept as `last_outcome`) |

## GUI Interface (target `taskman`)

Built once at startup; only contents change afterward (A-108).
Dark theme by default (`SW_THEME.make_dark`), switchable to light.
Window 1280 by 820. All sizes below are starting values.

### Live and replay modes (R-2)

```
taskman                       live machine
taskman --replay FILE         frames from FILE, one per interval, same screen every run
```

`FILE` holds encoded frames (`TMF1` blocks) written by
`taskman_cli snapshot --save-frames N FILE`. In Phase 2 a trace database is
also accepted. Replay gives deterministic screenshots for the phase gates
(intent Q4); the window code never assumes live sources.

### Machine sizes (R-4)

Topology uses the all-processor-groups calls, and PDH instances `group,number`
map to one flat index, so machines past 64 logical processors work. The
heatmap shape is computed from the count. Shapes this machine cannot produce
(processor groups, 5,000 processes) are exercised with scripted frames.

### Phase 1 layout

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ CPU 23%         │ Memory 61%       │ Disk 0: 4%        │ Package 61.2 W      │ <- SW_STATISTIC x4
│ ▁▂▂▃▅▇▅▃▂▁▁▂   │ ▅▅▅▅▅▅▆▆▆▆▆▆    │ ▁▁▁▁▃▁▁▁▁▁▁▁     │ ▃▃▄▅▆▅▄▃▃▃▃▃       │ <- SW_SPARKLINE x4
├──────────────────────────────────────────────┬───────────────────────────────┤
│ Processes (349)               [filter.....]  │ Cores (32)                    │
│ Name         PID    CPU    Private  Read/s   │ ┌───────────────────────────┐ │
│ msedge.exe   10176  4.1%   812 MB   1.2 MB   │ │ 4 x 8 heatmap, % busy     │ │ <- SW_HEATMAP
│ Obsidian.exe 20152  2.0%   402 MB   0        │ │ labels: P0..P31           │ │
│ taskman.exe  41232  0.3%    38 MB   0        │ └───────────────────────────┘ │
│ ...                                          │ This machine measures         │
│                                              │  ✓ CPU, per core              │
│ (SW_DATA_GRID of TM_PROCESS_ROW)             │  ✓ Memory, commit             │
│                                              │  ✓ Disk activity, 2 disks     │ <- TM_CAPABILITY_VIEW
│                                              │  ✓ CPU package power          │
│                                              │  ✗ Temperature: not supported │
│                                              │  ✗ Battery: not supported     │
│                                              │  Process table: native,       │
│                                              │   self-check passed           │
├──────────────────────────────────────────────┴───────────────────────────────┤
│ Sampling every 1 s · native table · 349 processes  │ taskman: 0.3% CPU, 38 MB │ <- SW_STATUS_BAR
└──────────────────────────────────────────────────────────────────────────────┘
```

- **Grid columns:** Name, PID, CPU (percent of machine), Private bytes, Working set, Read per second, Write per second, Threads. Each cell's text comes from the library's `TM_FORMAT`; a group that is not available shows its status word ("denied", "n/a"), never 0.
- **Sort keys:** numeric, from `TM_PROCESS_ROW`; an unavailable value sorts below every available one in either direction.
- **Default sort:** CPU descending. Clicking a header cycles as the widget does (ascending, descending, unsorted).
- **Selection** follows identity across refreshes (FR-NEW-007). A selected process that exits shows a one-line notice in the status bar.
- **Self row** is marked with a badge so the tool's own cost is always visible (FR-053, I-008).
- **Heatmap** shape: the most nearly square grid of the logical processor count (32 gives 4 by 8). On a hybrid machine, row labels say P-core or E-core from `TM_CPU_TOPOLOGY`.
- **Trend tiles** show the status word and no sparkline motion while a metric is not available (A-105, until W-1 lands).
- **Interaction during a stall:** if the slot reports a dropped frame, the status bar says "display fell behind", which is a symptom worth showing.

### Phase 2 additions

```
├──────────────────────────────────────────────────────────────────────────────┤
│ ◄ History ────────────────●───────────────────────── Live ►   14:02:17       │ <- SW_SLIDER + SW_LABEL
│ Incidents: 14:01 Memory pressure (msedge.exe) · 13:40 Disk saturation ...    │ <- SW_TIMELINE (P3 entries)
```

- Dragging the slider off "Live" freezes live updates and shows the recorded frame nearest that time, read through the window's own read-only store connection (A-115).
- A recorded frame shows "N processes below the recording threshold" in the grid footer (FR-NEW-012).
- Returning the slider to the right end resumes live display.

### Phase 3 additions

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ● Memory pressure: msedge.exe grew 6.1 GB in 4 minutes; commit is at 96%.    │ <- verdict banner
│   Evidence ▸  (expands: commit 96% mean, 2,300 hard faults/s, ... )         │
│   [Cause chain]  msedge.exe ──► Memory ──► Paging ──► Slow                   │ <- SW_SANKEY
└──────────────────────────────────────────────────────────────────────────────┘
```

Banner colors by verdict kind: none (quiet), inconclusive (neutral, with
reason), found (warning or danger by confidence). The banner sits above the
tiles, so it is the first thing read (I-001).

## CLI Interface (target `taskman_cli`, console)

```
taskman_cli snapshot [--top N] [--self] [--interval MS]
taskman_cli capabilities
```

- `snapshot` samples twice, `--interval` apart (default 1000), and prints the system readings and the top N processes by CPU (default 10).
- `--self` prints this process's CPU share and private bytes (FR-053).
- `capabilities` prints one line per metric: name, status, and reason.
- Exit code 0 on success, 2 for bad arguments, 3 if the machine could not be read.
- Command logic lives in classes that take parsed values, because `SIMPLE_CLI.parse` reads only the process's own arguments (survey of simple_cli). Tests call those classes directly.

Example output, format only:

```
$ taskman_cli capabilities
cpu.busy_pct              available
cpu.core.busy_pct         available      32 instances
cpu.package_watts         available
temperature.c             not supported  no thermal zone instance
battery.pct               not supported  no battery
process_table             native         self-check passed
```

## Stress Tool Interface (target `taskman_stress`, console)

```
taskman_stress cpu    --threads N   --seconds S
taskman_stress memory --mb M        --seconds S   [--step-mb K]
taskman_stress disk   --mb M        --seconds S   --path DIR
```

- First line printed is always the tool's own identity: `pid=NNNN creation=TTTT`. Acceptance tests compare it with the verdict's culprit (FR-031).
- `cpu` runs N SCOOP processors, each spinning for S seconds.
- `memory` allocates and touches pages in K MB steps until M MB, then holds until S seconds pass. Growth is what the memory rule looks for.
- `disk` writes and rereads a file of M MB under DIR through its own inline C (`CreateFileW` with write-through and no buffering, in aligned chunks), so the load reaches the disk instead of the cache; then deletes it (R-8).
- Every mode stops cleanly at S seconds and prints what it did.

## Build Targets (one ECF)

| Target | Root | Console? | Extends | Adds |
|--------|------|----------|---------|------|
| `simple_taskman` | none (library, `all_classes`) | n/a | | base, simple_mml, simple_logger; (P2) simple_sql, simple_json; (P3) simple_toml, simple_statistics |
| `simple_taskman_tests` | `TEST_APP.make` | yes | library | simple_testing, ISE testing, cluster `testing/` |
| `taskman` | `TM_APP.make` | **no** | library | simple_widgets, simple_shell, simple_cairo, simple_datetime, cluster `app/` |
| `taskman_cli` | `TM_CLI.make` | yes | library | simple_cli, cluster `cli/` |
| `taskman_stress` | `TM_STRESS.make` | yes | library | simple_cli, cluster `stress/`; disk mode in its own inline C (R-8) |
| `taskman_recorder` (P2 SHOULD) | `TM_RECORDER_APP.make` | **no** | library | cluster `recorder_app/`; records with no window open (R-5) |

All targets: `concurrency support="scoop" use="scoop"` (simple_chat's
setting), `void_safety support="all"`, full assertions in the test target.
`pdh.lib` linked under a Windows condition. `cairo.dll` must sit beside the
`taskman` executable after every finalize (simple_widgets README).

Build commands, mode word first:

```bash
/d/prod/ec.sh check -config simple_taskman.ecf -target simple_taskman_tests
/d/prod/ec.sh test  -config simple_taskman.ecf -target simple_taskman_tests
/d/prod/ec.sh test  -config simple_taskman.ecf -target taskman
```
