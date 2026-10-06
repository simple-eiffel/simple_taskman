# ADDENDUM: Intent Refinements (Phase 0)

Date: 2026-10-04
Source: `intent-v2.md`, approved by Larry ("Approve as written"). Each
refinement below records what changed in the spec and where.

| ID | From | Change | Spec files touched |
|----|------|--------|--------------------|
| R-1 | Q3 | The self-budget governs **sampling cost**, not whole-process CPU. `TM_SELF_BUDGET.assess (a_tick_cost, a_interval: INTEGER_64)`; facade gains `last_tick_cost` and `nominal_interval_ticks`. Whole-process CPU stays a displayed reading. | 05, 07 |
| R-2 | Q4 | Window runs live or from a frame file: `taskman --replay FILE`. New `TM_FRAME_FILE_REPLAYER` feeds the slot in place of sampling. CLI `snapshot --save-frames N FILE` writes such files. | 04, 06 |
| R-3 | Q2, Q11 | `TM_PATHS` (per-user folders from `LOCALAPPDATA`: trace, logs) in P1; `TM_SINGLE_WRITER` (per-session named mutex `Local\simple_taskman.recorder`) in P2. simple_env added to the library. GUI and recorder targets create their logger only with `SIMPLE_LOGGER.make_to_file`, one file per processor. | 04, 07 |
| R-4 | Q6 | Topology and PDH instance parsing handle processor groups (up to 1,024 logical processors); heatmap shape computed; scripted 5,000-process frame in the Phase 1 spike. | 04, 06 |
| R-5 | Q1 | `taskman_recorder` target (no window, no console) as Phase 2 SHOULD; opt-in per-user startup entry from the window; the window views the same file. | 04, 06, 07 (ECF) |
| R-6 | Q10 | MVP gate narrowed to the three rules, the verdict banner, and the evidence view. Cause chain, machine contracts and incidents, and the lag-probe spike follow, in that order. | intent-v2 acceptance criteria |
| R-7 | Q9 | No command lines, full paths, or window titles collected in Phases 1 to 3; image name, pid, and creation time only. Export redaction maps names to stable placeholders. | design already complied; stated here |
| R-8 | audit | Stress disk mode uses its own inline C (`CreateFileW` write-through, no buffering, aligned chunks) in `TM_DISK_LOAD`; simple_file removed from the stress target because it writes byte by byte and cannot bypass the cache. | 04, 06, 07 |

## Logging rule (R-3 detail)

`SIMPLE_LOGGER.make` prints every message to the console
(`simple_logger.e:522-526`), and a window target that writes to the console
makes Windows open a console window. So:

- Library classes accept an optional logger and never create one.
- `taskman` and `taskman_recorder` create loggers only with `make_to_file`.
- Each SCOOP processor gets its own log file, because the logger reopens the file per message and two writers would interleave.
- Log folder: `%LOCALAPPDATA%\simple_taskman\logs\`.

## Single-writer rule (R-3 detail)

The process that acquires `Local\simple_taskman.recorder` is the only writer
of `%LOCALAPPDATA%\simple_taskman\trace.db`. Any other instance opens the file
through `SIMPLE_SQL_DATABASE.make_read_only` (which opens with
`SQLITE_OPEN_READONLY`), sets `PRAGMA busy_timeout`, and shows "recording by
another instance". The mutex is released when the writer exits or crashes,
so a stale lock cannot outlive its owner.

## Upstream items added by the intent audit

| ID | Library | Item |
|----|---------|------|
| W-7 | simple_logger | `setup_file_writer` opens an append handle that is never written or closed; there is no setter to turn console output off after creation |
| W-8 | simple_file | Chunked binary write and append, flush, 64-bit offsets, optional write-through |
| W-9 | simple_env (or new) | Known-folder helper for per-user application data |
| W-10 | new or simple_shell | Single-instance named-mutex helper |
