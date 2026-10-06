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

🚧 **In development: v0.3.0.** Goal (intent v3): a full replacement for Windows Task Manager, plus a recorder, a diagnosis, and forecasts.

- 274 tests pass (2026-10-06), with contracts monitored
- **Verdict:** why the machine is slow (memory pressure, disk saturation, or CPU saturation), naming the process and the evidence, live or for any recorded moment
- **Look ahead:** memory runway, days until a disk fills, and leak suspects, each with its fit shown
- **Task Manager's tabs:** Processes (with End task / End process / End tree / priority / efficiency mode, always by process identity), Performance (CPU, memory, disks, network, GPU), Services, Startup apps (with measured impact), Users, Settings; run as administrator; open on Ctrl+Shift+Esc
- **Recorder:** every frame goes to `%LOCALAPPDATA%\simple_taskman\trace.db` (SQLite), kept at 1 s for an hour, 10 s for a day, 60 s for 30 days, capped at 250 MB; 6 to 13 MB written an hour. Optional background recorder from logon. The History strip scrubs back; `taskman_cli trace` reads any recorded moment
- One-hour live soak passed: sampling cost 0.74% of one processor (budget 1%), 3,557 frames with none dropped, no growth in memory, handles, or GDI objects. Sleep/wake shows as a gap frame, never as a rate

A reading the machine cannot supply says why ("not supported: no thermal zone instance"). It is never shown as 0.

## Install

Build the four targets (`taskman`, `taskman_recorder`, `taskman_cli`, `taskman_stress`) with `ec.sh release`, then compile `installer/simple_taskman.iss` with Inno Setup 6. The setup installs per user (no administrator rights) to `%LOCALAPPDATA%\Programs\simple_taskman`, with Start-menu entries. Silent: `simple_taskman-0.3.0-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART` (from PowerShell or cmd).

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
- **`taskman`**: the window: trend tiles, the verdict and look-ahead lines, a History strip, and the Processes, Performance, Services, Startup, Users, and Settings tabs. Options: `--history SECONDS` (open scrubbed back), `--page NAME`, `--select PID`, `--no-record`, `--replay FILE`, `--soak SECONDS`, `--echo PNG`.
- **`taskman_recorder`**: the background recorder (no window), started at logon when Settings asks for it.
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
