# simple_taskman

[GitHub](https://github.com/simple-eiffel/simple_taskman) •
[Issues](https://github.com/simple-eiffel/simple_taskman/issues)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Eiffel 25.02](https://img.shields.io/badge/Eiffel-25.02-purple.svg)
![DBC: Contracts](https://img.shields.io/badge/DBC-Contracts-green.svg)
![SCOOP](https://img.shields.io/badge/SCOOP-ready-orange.svg)

A diagnostic task manager for Windows, written in Eiffel, that aims to answer *why* the computer is slow, even after the slowdown has ended.

Part of the [Simple Eiffel](https://github.com/simple-eiffel) ecosystem.

## Status

🚧 **In development: v0.1.0.** Goal (intent v3): a full replacement for Windows Task Manager, plus a recorder, a diagnosis, and forecasts.

- Measurement library, recorder, and process controls: 244 tests pass (2026-10-06), with contracts monitored
- Window, command line, and stress tool built and run live on Windows 11
- One-hour live soak passed: sampling cost 0.74% of one processor (budget 1%), 3,557 frames with none dropped, and no growth in memory, handles, or GDI objects
- Sleep/wake checked: the high-resolution timer keeps counting through standby, so a sleep shows as a gap frame, never as a rate
- **Recorder (phase 2) built:** every frame goes to `%LOCALAPPDATA%\simple_taskman\trace.db` (SQLite) and is kept at 1 s for an hour, 10 s for a day, 60 s for 30 days, capped at 250 MB. Measured: 6.3 MB written an hour, 1.6 KB a frame. The window has a History strip to scrub back; `taskman_cli trace` reads any recorded moment while the window records (the History strip is built; its on-screen check is pending)
- **Everyday features (phase 3) started:** process details (path, command line, user, elevation, architecture, priority, efficiency mode), app windows and Not responding, and End task / End process / End tree / priority / efficiency mode, always by process identity so a reused process id is never touched (tested on its own child processes; the toolbar and details panel await an on-screen check)
- Not yet: the diagnosis rules, forecasts, services, startup apps

A reading the machine cannot supply says why ("not supported: no thermal zone instance"). It is never shown as 0.

## Quick Start

```eiffel
-- locals: tm: SIMPLE_TASKMAN; clock: TM_SYSTEM_CLOCK; format: TM_FORMAT
create tm.make
create clock.make
create format
tm.set_nominal_interval (1000).do_nothing
tm.sample
clock.sleep_ms (1000)
tm.sample
across tm.last_frame.top_by ({TM_RESOURCE}.Cpu, 5) as ic loop
    print (ic.name + {STRING_32} "  " + format.percent (ic.cpu_percent) + {STRING_32} "%N")
end
tm.close
```

## What is here

- **Library** (`simple_taskman`): processes from the native table (with a layout self-check and a documented fallback), PDH counters, CPU topology across processor groups, memory, disks, and CPU package power. Frames, windows, and aggregates come with coverage, and there is a lossless text codec. The SCOOP sampling worker hands frames to the GUI through a mailbox that never blocks.
- **`taskman`**: the window. It shows the process grid with a Status column, actions toolbar, per-core heatmap, trend tiles, a History strip, the selected process's details, the capability panel, and its own overhead. Options: `--history SECONDS` (open scrubbed back), `--no-record`, `--replay FILE`, `--soak SECONDS`, `--echo PNG`.
- **`taskman_cli`**: `snapshot`, `capabilities`, `synthetic`, `clockwatch`, and `trace [--ago SECONDS] [--top N] [--file PATH]`.
- **`taskman_stress`**: known CPU, memory, and uncached disk loads, for testing the diagnosis.

## Build

```bash
ec.sh test    -config simple_taskman.ecf -target simple_taskman_tests
ec.sh release -config simple_taskman.ecf -target taskman
```

`taskman` needs `cairo.dll` (from simple_cairo) next to the executable. Requires Windows 10 or 11, x64.

## Installation

```xml
<library name="simple_taskman" location="$SIMPLE_EIFFEL/simple_taskman/simple_taskman.ecf"/>
```

## License

MIT License. See the LICENSE file.
