# Changelog

## [0.3.0] - 2026-10-06 (development build, with installer)

### Added
- **Verdict (phase 4):** three rules over the last 30 seconds (or the 30 recorded seconds before a moment in the History strip): memory pressure (commit at 90% or more, or under 5% available, with 200 or more hard faults a second), disk saturation (80% busy or more), and CPU saturation (85% or more). Memory ranks first, because paging also shows up as disk and CPU load; the others are listed as "also". Each verdict names its culprit and evidence. With too few readings it says it can't tell and names what is missing.
- **Look ahead (phase 5):** memory runway (commit trend over 15 minutes), days until each disk fills (24 hours of free space), and leak suspects (private bytes growing 50 MB an hour or more over the last hour), fitted by least squares (simple_statistics). Each forecast shows its R squared, and says "watching" until it has enough points. If memory runs out within 15 minutes, the line turns red and the taskbar button flashes.
- **Tabs:** Performance (CPU, memory composition, disks with response time, network adapters, GPU engines and memory), Services (start, stop, restart), Startup apps (enable, disable, and impact measured from the recording of the three minutes after Windows started), Users (disconnect, sign out), and Settings (TOML).
- **Administrator rights:** status in Settings; Restart as administrator (Windows' runas prompt, reopening on the same page); "Open simple_taskman on Ctrl+Shift+Esc" through the taskmgr.exe Image File Execution Options Debugger value, set only with administrator rights and removed only when it points at a simple_taskman.
- **Background recorder:** `taskman_recorder.exe` (no window) records from logon when "Record from logon" is on (HKCU Run value), stops on a named event, and gives way to a recording window.
- Installer: ships `taskman_recorder.exe`; stops the recorder before replacing it and restarts it after an upgrade; uninstall removes the Run value, and refuses while Ctrl+Shift+Esc still opens this copy.

### Fixed
- The window fills the screen when it grows: the process, services, startup, and users grids, the side panel, and the performance chart take the extra height; each grid's main column (Name, Description, Where, User) takes the extra width. Toolbars, buttons, and switches keep their natural size. Column dividers show the left-right resize pointer (simple_widgets PR #13). `--size WxH` opens the window at a given size.
- A 5.5 s window freeze: account names for the selected process were looked up on the window thread, which can wait on the network. Now a local-only lookup with a 64-entry cache; ticks over 500 ms are logged.

### Technical
- 274 tests pass, with contracts monitored.


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
