# Changelog

## [0.2.0] - 2026-10-06 (development build, with installer)

Per-user installer (`installer/simple_taskman.iss`): taskman.exe, taskman_cli.exe, taskman_stress.exe, cairo.dll.

## [0.1.0] - 2026-10-05 (development, not released)

### Added
- Measurement library (P1): native process table with a layout self-check and a documented fallback; PDH counters for CPU, cores, utility, disks, hard faults, and package power; CPU topology across processor groups; memory and free-space gauges.
- Honest readings: every value is checked against its metric's range; a missing value carries a status (unavailable, not supported, access denied, invalid) and is never shown as 0.
- Process identity is pid plus creation time, so a recycled pid is a new process and never inherits its predecessor's rate.
- Frames, windows, aggregates with coverage, series, and a lossless versioned text codec (TMF1).
- Continuous timeline across wall-clock changes; frames are flagged when the clock moved.
- SCOOP sampling worker and frame slot; replay worker.
- `taskman` window, `taskman_cli` (snapshot, capabilities, synthetic, clockwatch), `taskman_stress` (cpu, memory, uncached disk).

- Recorder (phase 2): SQLite trace in `%LOCALAPPDATA%\simple_taskman\trace.db` with 1 s / 10 s / 60 s tiers (1 hour, 24 hours, 30 days), a 250 MB cap, pinned frames, one writer per session, and a read-only mode for viewers. Payloads are zlib-compressed TMF1 text; per-process rows for merged frames make history queryable in SQL.
- History strip in the window (scrub back, Live), `--history SECONDS`, `--no-record`; `taskman_cli trace`.
- Process details, app windows and Not responding, and the actions End task, End process, End tree, priority, and efficiency mode (with Undo), all by process identity; protected and critical processes refused.

### Measured
- Recorder: 6.3 MB written an hour while frames only accumulate, 13.3 MB an hour once merging runs (budget 20). The first design wrote 50, then 27.5 while merging; vacuuming after every merge pass was the churn. 1.6 KB a frame.
- Window: 4.9% of one CPU and 31 MB, against Windows Task Manager's 8.0% and 127 MB on the same PC.

### Technical
- Design by Contract throughout; void-safe; SCOOP.
- 244 tests passing, including scale tests (5,000 processes, 1,024 logical processors, an hour of frames), hostile input, SCOOP races, and the application targets.
- One-hour live soak of the window (lean build): sampling 0.74% of one processor, render 15.7 ms average, 0 frames dropped, memory 31-33 MB, handles and GDI objects constant.
- Inline C on system headers only; `_WIN32_WINNT` raised to 0x0A00 in the ECF (EiffelStudio's default C target is Windows 2000).
