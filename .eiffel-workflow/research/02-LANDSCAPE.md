# LANDSCAPE: simple_taskman

Date: 2026-10-03. Every URL marked **[fetched]** was retrieved with WebFetch in
this session. URLs marked **[search hit]** appeared in WebSearch results and
were not opened; claims attributed to them come from the search summary only.

## Existing Solutions

### TMOG (Task Manager OG), Dave Plummer
| Aspect | Assessment |
|--------|------------|
| Type | Desktop application |
| Platform | Windows 11 (C++ and Win32/Direct2D), macOS 14+ (Swift and AppKit), Linux (C++ and Qt 6); one shared C++20 measuring core |
| URL | https://tmog.org **[fetched]**; https://www.engadget.com/2262039/vibe-coded-modern-task-manager-runs-on-mac-and-linux/ **[fetched]** |
| Maturity | EXPERIMENTAL (beta, per Engadget) |
| License | Proprietary; free tier plus Pro at $39.95 |

**Strengths:**
- Twelve views: CPU, memory, disk, network, energy, thermals, startup, services, installed software, disk space, benchmarks
- "Energy has a cause": watts shown beside the responsible processes
- Flight Recorder (Pro): "records, saves, scrubs, and replays the same seven telemetry panels in one interchangeable `.tmogtrace` format"
- Gaps drawn for missing sensor data; pid paired with creation identity (from the video transcript)
- Native on three platforms; no telemetry sent

**Weaknesses (relative to our goal):**
- Diagnosis is still done by the human reading correlated graphs. The site lists no automated verdict and no AI feature
- No stated remedy other than the classic process actions
- No declared "healthy" baseline that the machine is checked against
- How power and temperature are obtained is not documented on the site
- Trace format is proprietary

**Relevance:** 90%. It defines the category and the bar. Built in under six weeks
by three people with Claude Code from a "107-page spec sheet" (Engadget), which
says the differentiator must be ideas, not effort.

### Windows Task Manager and Resource Monitor (built in)
| Aspect | Assessment |
|--------|------------|
| Type | OS component |
| Platform | Windows |
| URL | https://devblogs.microsoft.com/performance-diagnostics/reduce-process-interference-with-task-manager-efficiency-mode/ **[fetched]**; https://www.thewindowsclub.com/analyze-wait-chain-traversal **[search hit]** |
| Maturity | MATURE |
| License | Part of Windows |

**Strengths:**
- Efficiency mode: lowers base priority to low and sets EcoQoS. Microsoft measured "14% ~ 76%" responsiveness improvement using app launch and Start Menu open times under a synthetic CPU load
- Resource Monitor has "Analyze Wait Chain" for a not-responding process (search hit)
- Per-process GPU since Windows 10 1709 (search hit)

**Weaknesses:**
- Live only; no history
- Efficiency mode is manual, CPU-only, and never tells the user whether it helped
- Wait chain is buried in a right-click menu of a second tool

**Relevance:** 70%. **Prior art for "throttle instead of kill"**. Our remedy idea
is not new by itself.

### Process Lasso (Bitsum), ProBalance
| Aspect | Assessment |
|--------|------------|
| Type | Desktop application plus service |
| Platform | Windows |
| URL | https://bitsum.com/how-probalance-works/ **[fetched]** |
| Maturity | MATURE |
| License | Proprietary, freemium |

**Strengths:**
- Automatically and temporarily lowers the priority class of a process that is monopolizing CPU, then restores it
- Long track record; rule persistence (affinities, priorities)

**Weaknesses:**
- Changes priority class only, CPU only
- The fetched page gives no thresholds and "doesn't explain whether ProBalance verifies the effect of its adjustments or provides causal explanations beyond logging activity"
- No resource-agnostic diagnosis (memory, disk, power budget)

**Relevance:** 65%. **Prior art for automatic restraint.** What is still open is
*measuring that the restraint fixed the user-visible symptom*.

### System Informer (formerly Process Hacker)
| Aspect | Assessment |
|--------|------------|
| Type | Desktop application with optional kernel driver |
| Platform | Windows, C/C++ |
| URL | https://github.com/winsiderss/systeminformer **[fetched]** |
| Maturity | MATURE |
| License | MIT |

**Strengths:** Deep inspection: stack traces, handles, services, network, disk
access in real time. Its `phnt` headers (https://github.com/winsiderss/phnt,
search hit) are the reference for native structure layouts.

**Weaknesses:** Expert tool. Live data emphasis. No verdict. Kernel component.

**Relevance:** 45%. Source of truth for native API layouts, not a competitor in
intent.

### Process Explorer (Sysinternals)
| Aspect | Assessment |
|--------|------------|
| Type | Desktop application |
| URL | https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer **[fetched]** |
| Maturity | MATURE |
| License | Sysinternals license (free) |

**Strengths:** Handles and DLLs per process; search for who holds a file.
**Weaknesses:** Inspection tool; no diagnosis, no recorder.
**Relevance:** 30%.

### LibreHardwareMonitor and PawnIO
| Aspect | Assessment |
|--------|------------|
| Type | Library plus signed kernel driver |
| URL | https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/commit/eb5e1a20be996d4865170b13bab97af43d97f341 **[search hit]** |
| Maturity | MATURE |

**Finding (from search summary):** LibreHardwareMonitor replaced WinRing0 with the
signed PawnIO driver. Without the driver it falls back to a user-mode profile
that keeps GPU, storage, and network sensors and omits CPU and motherboard
sensors. This agrees with our local probe: CPU temperature is not available
user-mode on this machine.

**Relevance:** 40%. Tells us where the no-driver boundary is.

### sysinfo (Rust crate)
| Aspect | Assessment |
|--------|------------|
| Type | Library |
| URL | https://docs.rs/sysinfo/latest/sysinfo/ **[fetched]** |
| Maturity | MATURE |
| License | MIT |

**Strengths:** Clean model worth copying: one long-lived `System` object, explicit
refresh, granular "refresh kinds", a minimum CPU update interval because CPU
usage is a difference between two readings.
**Weaknesses:** Measurement only.
**Relevance:** 60% as an API design reference. Search results state it uses
`NtQuerySystemInformation` for the Windows process list.

### Windows SRUM (System Resource Usage Monitor)
| Aspect | Assessment |
|--------|------------|
| Type | OS component, ESE database `%windir%\System32\sru\SRUDB.dat` |
| URL | https://github.com/libyal/esedb-kb/blob/main/documentation/System%20Resource%20Usage%20Monitor%20(SRUM).asciidoc **[search hit]** |

**Finding (from search summary):** Windows already keeps about 30 days of
per-application CPU cycles, bytes read and written, network bytes, and energy
use, flushed hourly. It is a forensic source, coarse-grained, in ESE format.
(Whether a standard user can read the file was not researched.)

**Relevance:** 35%. **Prior art for "the OS has a flight recorder."** Too coarse
(hourly) to explain a five-minute incident. Possible later import source.

### Microsoft "User Input Delay" counters
| Aspect | Assessment |
|--------|------------|
| URL | https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/rds-rdsh-performance-counters **[fetched]** |

**Finding:** Microsoft's own argument for a felt-lag metric: resource counters
"have frequent and large variations", so they added a counter that "measures how
long any user input ... stays in the queue before a process picks it up", and
reports the **maximum** per interval because "the user's perception of 'slow' is
determined by the slowest input time". Documented for Windows 10 1809+.

**Local check:** both counter sets are **ABSENT** on this Windows 11 Pro 26200
machine (see `evidence/hardware-probe-2026-10-03.txt`).

**Relevance:** 75%. **Prior art and validation for the felt-lag idea**, and proof
that we cannot rely on the built-in counter.

## Eiffel Ecosystem Check

### ISE Libraries
- `process` library, `wel_toolhelp.e` and `process_utility.e`: a Toolhelp
  wrapper giving pid, parent pid, thread count, base priority, exe name. No CPU
  time, memory, IO, or counters. Verified by grep of the installed 25.02 tree.
- `wel`: no process metrics.

### simple_* Libraries
- simple_system: static machine facts only (305 lines). Not a sampler.
- simple_process: launches processes (`CreateProcess`). Does not enumerate.
- simple_telemetry: application-level counters, gauges, spans. Not OS metrics.
- simple_widgets 0.8.1: drawn Win32 toolkit with sparkline, line chart, gauge,
  heatmap, treemap, Sankey, timeline, data grid, tree table, dock host. This is
  the GUI.
- simple_chart: braille canvas and sparkline renderers for a terminal view.
- simple_sql: SQLite. This is the recorder.
- simple_statistics, simple_json, simple_toml, simple_cli, simple_datetime,
  simple_pdf, simple_ai_client, simple_shell, simple_registry: all present.

### Gobo Libraries
- Clusters present: argument, common, kernel, lexical, math, parse, pattern,
  regexp, string, structure, test, thread, time, tools, utility, xml, xpath,
  xslt. Nothing for processes or system metrics.

### Gap Analysis
Not available in Eiffel: process table with resource usage, performance counter
(PDH) access, per-core CPU, memory pressure, disk activity, energy counters, GPU
counters, process control beyond launch. A web search for an Eiffel library
doing any of this returned nothing relevant.

## Comparison Matrix

| Feature | TMOG | Task Mgr / ResMon | Process Lasso | System Informer | Our Need |
|---------|------|-------------------|---------------|-----------------|----------|
| Live process and resource view | Yes | Yes | Yes | Yes | MUST |
| History after the incident | Yes (Pro) | No | Log of actions | No | MUST |
| Missing data shown as gap | Yes | No | ? | ? | MUST |
| Pid-reuse-safe actions | Yes | ? | ? | Yes | MUST |
| Power beside processes | Yes | Partial ("power usage" label) | No | No | SHOULD |
| Automated verdict in words | No | No | No | No | MUST |
| Measures felt lag directly | No | No | Not documented | No | SHOULD |
| Throttle instead of kill | No (not stated) | Yes, manual | Yes, automatic | Manual priority | SHOULD |
| Verifies the remedy worked | No | No | Not documented | No | SHOULD |
| Declared healthy-state contracts | No | No | No | No | SHOULD |
| Open, queryable trace | No (`.tmogtrace`) | n/a | n/a | n/a | SHOULD |
| Wait chain | No | Yes (hidden) | No | Not in README | DEFERRED |
| Cross-platform | Yes | No | No | No | NO |
| Benchmark score | Yes (Pro) | No | No | No | NO |

"?" means the fetched source did not say.

## Patterns Identified

| Pattern | Seen In | Adopt? |
|---------|---------|--------|
| Long-lived sampler object with explicit refresh and refresh kinds | sysinfo | YES |
| CPU usage as a delta with a minimum interval | sysinfo | YES |
| Gap instead of zero for missing data | TMOG | YES, enforced by types |
| Pid plus creation identity | TMOG, Windows `SequenceNumber` | YES |
| Report the maximum delay per interval, not the mean | Microsoft User Input Delay | YES |
| Priority plus EcoQoS as the gentle restraint | Task Manager Efficiency mode | YES |
| Temporary restraint, auto-restore | ProBalance | YES, with measured effect |
| Refuse to touch core OS processes | Task Manager | YES |
| Measuring core separate from host UI | TMOG | YES |
| Kernel driver for sensors | LibreHardwareMonitor | NO |
| Proprietary trace format | TMOG | NO; SQLite plus JSON export |

## Build vs Buy vs Adapt

| Option | Effort | Risk | Fit |
|--------|--------|------|-----|
| Build (Eiffel sampler, recorder, diagnosis; GUI on simple_widgets) | HIGH | MED | 90% |
| Adopt (wrap a C or Rust metrics library) | MED | MED | 50%; violates inline-C and simple_* rules, adds a foreign build, and still leaves diagnosis to build |
| Adapt (extend simple_system into a sampler) | MED | LOW | 60%; right home for a few static queries, wrong home for a stateful sampler |

**Initial Recommendation:** BUILD. The measurement layer is thin Win32 that fits
the inline-C pattern, and the parts that matter (diagnosis, contracts,
experiments) do not exist anywhere to adopt.
