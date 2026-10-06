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

🚧 **In development: v0.1.0, product phase 1 ("see it move")**

- Measurement library done and hardened: 191 tests pass (2026-10-05), with contracts monitored
- Window, command line, and stress tool built and run live on Windows 11
- One-hour live soak passed: sampling cost 0.74% of one processor (budget 1%), 3,557 frames with none dropped, and no growth in memory, handles, or GDI objects
- Sleep/wake checked: the high-resolution timer keeps counting through standby, so a sleep shows as a gap frame, never as a rate
- Not yet: the recorder (phase 2) and the diagnosis rules (phase 3)

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
- **`taskman`**: the window. It shows the process grid, a per-core heatmap, trend tiles, the capability panel, and its own overhead. Options: `--replay FILE`, `--soak SECONDS`, `--echo PNG`.
- **`taskman_cli`**: `snapshot`, `capabilities`, `synthetic`, and `clockwatch`.
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
