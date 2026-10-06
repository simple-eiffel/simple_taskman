# CHALLENGED ASSUMPTIONS: simple_taskman

Date: 2026-10-03

Evidence sources for this step: the research files, the hardware probe, and an
ecosystem survey of simple_widgets, simple_shell, and their client applications
run for this spec (file and line citations below come from that survey).

## Assumptions Challenged

### A-101: "The window receives immutable snapshots from the sampler's processor" (D-009, D-013)
**Challenge:** In SCOOP an object belongs to the processor that created it. A frame built by the sampler is `separate` to the window; every field read is a cross-processor call, and it waits whenever the sampler is busy. Sharing by reference would make the window slower, not faster, and can stall it.
**Evidence for:** None in the ecosystem.
**Evidence against:** simple_chat is the one existing SCOOP plus simple_widgets application (`simple_chat/apps/client/client_app.e:1161-1201`). It never shares objects. A separate host deposits text into a separate mailbox; the window's heartbeat drains it with short calls and copies with `make_from_separate` (`chat_presenter.e:261-300, 544-560`; `src/client/summary_slot.e`).
**Verdict:** INVALID as worded.
**Action:** Frames cross processors **by value**. The sampler's processor encodes a frame to a `STRING_8`, deposits it in a separate slot, and the window's processor copies and decodes it into its own objects. Three classes carry this: `TM_FRAME_CODEC`, `TM_FRAME_SLOT`, `TM_SAMPLING_WORKER`. Pattern credited to simple_chat.

### A-102: "The window can be notified when a frame is ready"
**Challenge:** Is there any way to post to the UI thread?
**Evidence against:** `SW_WINDOW` has no post, invoke, or queue facility; the shell forbids callbacks from other threads ("never dollar-callbacks - they SEGV under EIF_THREADS", `shell_window.e:4-6`).
**Verdict:** INVALID.
**Action:** The window **polls** the slot from `on_tick`, the 250 ms heartbeat (`sw_window.e:592, 638`). Worst-case display latency is one heartbeat. The heartbeat already repaints unconditionally, so no extra render call is needed.

### A-103: "The sampler worker may simply sleep between samples"
**Challenge:** Any blocking C call on a worker can stop the garbage collector from synchronizing, freezing the GUI thread.
**Evidence:** simple_chat measured a 21,058 ms GUI freeze until blocking externals were declared `external "C blocking inline"` (`client_app.e:24-34`).
**Verdict:** VALID only with a rule.
**Action:** New constraint C-015: every external that can block (sleep, counter collection, the process-table call, SQLite commit, timed message send) is declared `"C blocking inline"`. Listed per class in the class design.

### A-104: "SW_TIMELINE gives us the Phase 2 scrubber" (FR-052)
**Challenge:** What is `SW_TIMELINE`?
**Evidence against:** It is a list of dated entries: `add_entry (a_when, a_title, a_detail; a_kind)` (`sw_timeline.e:49`). No time axis, no drag.
**Verdict:** INVALID.
**Action:** The scrubber is an `SW_SLIDER` (fraction 0..1 with `on_change`) mapped onto the recorded time range, beside a label showing the selected time. `SW_TIMELINE` is used for what it is: the incident list. FR-052 reworded below.

### A-105: "A sparkline can show a gap" (NFR-009, I-007)
**Challenge:** The whole honesty story fails at the last step if the widget joins the dots.
**Evidence against:** `SW_SPARKLINE` offers only `add_value (a_value: REAL_64)` (`sw_sparkline.e:96`). `SW_LINE_CHART.add_point` likewise, and only to the last series (`sw_line_chart.e:56-68`).
**Verdict:** INVALID.
**Action:** Upstream work item W-1 on simple_widgets: gap support on `SW_SPARKLINE` (for example `add_gap`), fixed in the library, not worked around in the client. Until W-1 lands, a trend for a metric that is not available shows its status text and no line, and an intermittent gap resets the line (the view starts a fresh sparkline segment) rather than bridging it. No number is ever fed to a widget for a reading that is not available.

### A-106: "The GUI redraws only what changed"
**Evidence against:** Every heartbeat and every input event re-renders the whole tree; the grid calls each column's value function for every visible cell on every frame (`sw_window.e:1621-1646, 2042-2062`; `sw_data_grid.e:274-307`).
**Verdict:** INVALID.
**Action:** Row objects handed to the grid carry **preformatted** strings and sort keys, computed once per frame arrival. Column functions only return stored attributes. This is the reason `TM_PROCESS_ROW` exists as its own class.

### A-107: "Giving the grid a fresh list each second is safe" (FR-057)
**Evidence for:** `set_rows` twins the list (`sw_data_grid.e:110-125`, `ensure owns_snapshot`).
**Evidence against:** Selection is kept as an index, so after a refresh that reorders rows the selection points at a different process.
**Verdict:** VALID with a rule.
**Action:** The process view remembers the selected `TM_PROCESS_ID`, and after each `set_rows` re-selects the row with that identity through `select_model_row`, or clears the selection if the process has exited.

### A-108: "Widgets can be cleared and refilled"
**Evidence against:** No clear feature on sparkline, line chart, timeline, Sankey, treemap, or on row and column containers.
**Verdict:** INVALID.
**Action:** Layout is built once and stays. Views update contents (`set_text`, `set_cell`, `set_rows`, `set_value`). The cause chain (Sankey) is rebuilt as a new widget per verdict inside a fixed host. Upstream work item W-2: clear features on those widgets.

### A-109: "Wall-clock timestamps are enough"
**Challenge:** The system clock can be set backward or jump. Rates divided by a wrong interval are wrong, and "end after start" can be violated.
**Verdict:** INVALID.
**Action:** `TM_CLOCK` supplies both UTC time for labels and a monotonic counter for durations. A frame stores `end_time` (UTC) and `duration` (monotonic, positive). FR-NEW-001.

### A-110: "Consecutive snapshots are always one interval apart"
**Challenge:** Sleep and resume, a debugger pause, or a stalled machine produce a snapshot pair minutes apart. Averaging activity over that span is a quiet lie.
**Verdict:** INVALID.
**Action:** If the interval exceeds a multiple of the configured one, the sampler emits a **discontinuity frame**: no activities, readings unavailable, flagged as a gap. The recorder stores it as a gap. FR-NEW-002.

### A-111: "Every row in the process table is a process"
**Challenge:** Pid 0 is the idle pseudo-process; its CPU time is idle time. Counting it would make "System Idle Process" the top culprit of every verdict.
**Verdict:** INVALID.
**Action:** The idle entry is excluded from activities and from every ranking; its time feeds only the idle reading. FR-NEW-003.

### A-112: "Naming the culprit process is enough" (FR-031)
**Challenge:** On this machine 82 processes are named `svchost`. "svchost.exe is the culprit" tells the owner nothing. Browsers run dozens of processes that are jointly, not singly, the cause.
**Verdict:** NEEDS MODIFICATION.
**Action:** A culprit is a small object: a display name plus one or more identities. Rules may blame a **group** sharing an image name. For service hosts the hosted service names should be shown; whether a standard user can list them is unverified, so that part is SHOULD with a spike. FR-NEW-004, FR-NEW-005.

### A-113: "Per-process IO counters identify who is hammering the disk" (FR-031, disk rule)
**Challenge:** The per-process IO byte counters cover all IO: files, pipes, network, devices.
**Verdict:** VALID only with a caveat.
**Action:** The disk rule's culprit is reported with confidence at most medium and its evidence says "total IO". Per-file attribution needs ETW, which is deferred.

### A-114: "Total CPU at 90% is what CPU slowness means" (FR-030)
**Challenge:** On 32 logical processors, one pegged thread is 3% of the machine. The machine is fine; that one application is slow.
**Verdict:** VALID for the machine-level rule; a gap for the application-level case.
**Action:** MVP rule stays machine-level, matching the acceptance scenario. The single-application case is recorded as a later rule (belongs with the hung-application kind). Not silently claimed.

### A-115: "The UI processor can read history from the recorder"
**Challenge:** The recorder lives on another processor and may be mid-commit.
**Verdict:** INVALID as an object call.
**Action:** The window opens its **own read-only** store on the same file. WAL mode allows a reader beside the writer. `TM_SQLITE_TRACE_STORE` has a writer creation and a reader creation.

### A-116: "50 MB covers the GUI" (NFR-003)
**Challenge:** NFR-003 was written for the headless recorder. A cairo-drawn window with fonts is a different footprint.
**Verdict:** NEEDS_VALIDATION.
**Action:** NFR-003 applies to the library and CLI. A GUI footprint target is set after the Phase 1 measurement, not invented now.

### A-117: "POINTER blocks would be a faster handoff than strings"
**Challenge:** A malloc'd block passed as an expanded `POINTER` crosses processors with no copy.
**Evidence for:** Zero copy.
**Evidence against:** Unproven in this ecosystem; manual ownership; the string pattern is already working in production in simple_chat.
**Verdict:** Keep in reserve.
**Action:** Use the proven string handoff. The Phase 1 spike measures the copy cost of a full frame. If it breaks NFR-002, the slot's payload type is the only thing that changes.

### A-118: "The recorder can run on its own processor, like the sampler" (D-009, Phase 2 bullet)
**Challenge:** A-103 says a long C call that is not declared blocking stops the collector from synchronizing and freezes the GUI. Are the SQLite calls declared blocking?
**Evidence against:** A grep of `eiffel_sqlite_2025` and `simple_sql/src` for "C blocking" finds **zero** files. Every SQLite call, including commit and its fsync, is a plain external.
**Verdict:** NEEDS MODIFICATION. Any processor that runs SQLite can stall the GUI for the length of a commit, wherever it lives.
**Action:**
1. **D-020:** the recorder runs on the *sampling worker's* processor, not a third one. One writer, no second handoff, commits batched every 5 s. A slow commit delays one tick; the monotonic clock keeps that tick's rates correct.
2. Upstream work item **W-4** (eiffel_sqlite_2025): declare the long-running externals (`sqlite3_step`, `sqlite3_exec`, `sqlite3_close_v2`, WAL checkpoint) as `"C blocking"`, after confirming they touch no Eiffel-managed memory while running.
3. Phase 2 gate measures the worst commit time and the GUI's worst frame time while committing. Until W-4 lands, the commit interval is the lever.
4. The GUI's own read-only connection (A-115) only ever runs single-frame and short-window queries.

### A-119: "simple_statistics serves the rule engine"
**Evidence:** `STATISTICS.percentile` copies and sorts with a bubble sort (O(n squared)) and takes `ARRAY [REAL_64]`; `variance` is the population variance (survey of `simple_statistics/src/statistics.e`).
**Verdict:** VALID for small inputs only.
**Action:** MVP rules need mean, maximum, and coverage, which `TM_WINDOW` computes in one pass. simple_statistics is used for contract proposals (FR-036, later) on bounded arrays. Upstream item **W-5:** replace the bubble sort in `percentile`.

### A-120: "simple_datetime supplies timestamps"
**Evidence:** No sub-second API; `to_timestamp` is whole seconds (survey of `simple_datetime`).
**Verdict:** INVALID for sampling.
**Action:** Timestamps are `INTEGER_64` counts of 100 ns UTC ticks from `GetSystemTimePreciseAsFileTime`, inside `TM_SYSTEM_CLOCK`. simple_datetime formats labels only, through `make_from_timestamp`.

### A-121: "simple_sql prepared statements give fast inserts"
**Evidence:** `SIMPLE_SQL_PREPARED_STATEMENT.execute` substitutes escaped literals into the SQL text and runs a one-shot statement; `is_query` tests for a leading "SELECT" (survey of `simple_sql`).
**Verdict:** VALID as an API, not as a performance feature.
**Action:** The recorder writes about 1 frame row and at most 25 process rows per second inside one transaction per batch; one-shot statements are adequate at that rate. Queries that start with `WITH` or `PRAGMA` go through `execute` or `query`, never through `execute_returning_result`. Recorder statements are wrapped in one class so a native prepared path can replace them later.

### Carried forward from research, unchanged
| ID | Assumption | Verdict | Action |
|----|------------|---------|--------|
| A-5 | Null-message round trip tracks felt lag | NEEDS_VALIDATION | Phase 3 spike before any rule depends on it |
| A-6 | Standard user can probe elevated windows | NEEDS_VALIDATION | Same spike; result access_denied is acceptable |
| A-7 | Running process can be put under a job CPU cap | NEEDS_VALIDATION | Phase 4; EcoQoS and priority are the documented fallbacks |
| A-4 | Native offsets for IO and memory fields | NEEDS_VALIDATION | Self-check covers them in Phase 1 |
| A-9 | Full tick fits the budget | NEEDS_VALIDATION | Measured at the Phase 1 gate |

## Requirements Questioned

### FR-052: GUI views
**Challenge:** Wording assumed a scrubbing timeline widget.
**Verdict:** MODIFY
**New requirement:** Phase 2 delivers a time scrubber (slider over the recorded range with a time label) and an incident list. Phase 1 and 3 parts unchanged.

### FR-031: Name the culprit
**Verdict:** MODIFY
**New requirement:** Name the culprit as a display name with one or more process identities; a group sharing an image name may be the culprit.

### FR-010: Per-process GPU
**Challenge:** 1384 counter instances; is it worth Phase 1?
**Verdict:** KEEP as SHOULD, Phase 1 stretch. Not on the Phase 1 gate.

### FR-004: Efficiency class per core
**Challenge:** Untestable here.
**Verdict:** KEEP. One documented call; the heatmap labels need it on hybrid machines; tests use a fake topology.

### FR-051: CLI
**Challenge:** GUI applications must not print (`sw_window.e:9-12`).
**Verdict:** KEEP, with a rule: the library never prints. The CLI is a separate console target.

### FR-025: Replay
**Challenge:** Is replay a feature or a test mechanism?
**Verdict:** KEEP as both. It costs nothing extra once diagnosis consumes a `TM_WINDOW`.

### FR-006: Disk activity
**Verdict:** KEEP. Per physical disk through counters; volumes through the documented free-space call.

## Missing Requirements Identified

| ID | Missing Requirement | Priority | How Discovered |
|----|---------------------|----------|----------------|
| FR-NEW-001 | Durations come from a monotonic clock; labels from UTC | MUST | A-109 |
| FR-NEW-002 | An over-long interval yields a discontinuity frame, recorded as a gap | MUST | A-110 |
| FR-NEW-003 | The idle pseudo-process is excluded from activities and rankings | MUST | A-111 |
| FR-NEW-004 | A culprit may be a group of processes sharing an image name | MUST | A-112 |
| FR-NEW-005 | Service-host culprits show hosted service names | SHOULD, needs spike | A-112 |
| FR-NEW-006 | Frame encode then decode is lossless | MUST | A-101 |
| FR-NEW-007 | Process selection in the grid follows identity across refreshes | MUST | A-107 |
| FR-NEW-008 | The library never writes to the console; diagnostics go to an injected logger | MUST | FR-051 challenge |
| FR-NEW-009 | The recorder file can be opened read-only by a second connection while being written | MUST | A-115 |
| FR-NEW-010 | The trace schema carries a version and the metric catalog it was written with | MUST | Metric names are now part of a persistent format |
| FR-NEW-011 | Every external that can block is declared `"C blocking inline"` | MUST | A-103, A-118 |
| FR-NEW-012 | Recorded frames keep only significant processes and state how many were omitted | MUST | Size budget in 04-CLASS-DESIGN (recorder) |

## Upstream Work Items (other libraries)

Per the standing rule to fix library gaps in the library, not in the client.

| ID | Library | Item | Needed by |
|----|---------|------|-----------|
| W-1 | simple_widgets | Gap support on `SW_SPARKLINE` | Phase 1 gate for any intermittently available metric |
| W-2 | simple_widgets | Clear or reset features on sparkline, Sankey, timeline | Phase 2 and 3 convenience; rebuild-the-widget workaround exists |
| W-3 | simple_widgets | Record the `set_rows` twin fix (commit 2b460f7) in CHANGELOG | Housekeeping noticed during the survey |
| W-4 | eiffel_sqlite_2025 | Declare long-running SQLite externals `"C blocking"` | Phase 2 gate (A-118) |
| W-5 | simple_statistics | Replace the bubble sort in `percentile` | FR-036, later |
| W-6 | simple_sql | Record commit f233149 (2026-09-28 statement cleanup before close) in CHANGELOG; clients must call `close` explicitly | Housekeeping noticed during the survey |

## Design Constraints Validated

| Constraint | Valid? | Notes |
|------------|--------|-------|
| simple_* first | YES | simple_widgets, simple_shell, simple_cairo (GUI); simple_sql (recorder); simple_json (export, fixtures); simple_toml (contracts); simple_statistics (baselines); simple_datetime (labels); simple_cli (CLI); simple_logger (diagnostics); simple_testing (tests). ISE base, time, testing only. |
| SCOOP-compatible | YES | Library target `support="scoop"`. GUI application follows simple_chat: `support="scoop" use="scoop"`. Model classes are sequential; separateness appears only at the three handoff classes and the application roots. |
| Void-safe | YES | Absence is modeled by status objects, not by Void, except where an attribute is truly optional (an open incident's end). |
| Inline C only | YES | Externals grouped in a few `TM_WIN_*` classes; blocking ones marked `"C blocking inline"` (C-015). |
| No header statics | YES | Native handles and buffers are `POINTER` attributes of the owning Eiffel object. |
| O(1) invariants | YES | Collection properties are postconditions with MML models; invariants compare counts and scalars only. |
| No console output in GUI | YES | New from the survey; FR-NEW-008. |
| cairo.dll beside the executable | YES | New from the survey (`simple_widgets/README.md:103-126`); build note for the GUI target, since every finalize wipes F_code. |
