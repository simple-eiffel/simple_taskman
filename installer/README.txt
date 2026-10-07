simple_taskman 0.3.0
====================

A diagnostic task manager for Windows, written in Eiffel. It shows what the
machine is doing, records it, and lets you look back at any moment.

The window (taskman.exe)
------------------------
- Four tiles: CPU (% Processor Utility, as Task Manager shows it), memory
  commit, the busiest disk, and CPU package power, each with a line.
- The verdict, under the tiles: why the machine is slow right now (memory
  full, a disk saturated, or the CPU saturated), naming the process behind
  it and the numbers, or "No bottleneck" with the numbers. Memory pressure
  ranks first, because paging also shows up as disk and CPU load. A fourth
  finding, in amber: a single-thread limit, when one program keeps one full
  core busy while the CPU as a whole is not (the total CPU can read 3% while
  that program is at its ceiling; the Cores heatmap shows the one lit
  square). Drag the History strip and the verdict is for that moment
  instead.
- Look ahead: when memory will run out at the current rate, which disk
  fills and in how many days, and processes whose memory keeps growing
  (leak suspects). Each forecast shows its fit, and says "watching" until
  it has enough to go on. If memory will run out within 15 minutes the
  line turns red and the taskbar button flashes.
- Tabs:
  Processes    name, status (App, Not responding), PID, CPU, memory, disk;
               toolbar for End task, End process, End tree, Efficiency,
               Lower or Raise priority, and Undo. End process and End tree
               need a second click within four seconds. Core Windows
               processes, and any process Windows marks critical, are
               refused. Every action checks it still has the same process.
  Performance  CPU (speed, kernel time, caches, cores, uptime), memory
               (composition, commit, pools), each disk (active time,
               response time, speeds), each network adapter, and the GPU
               (per engine type, dedicated and shared memory).
  Services     every service: state, start type, process; start, stop,
               restart.
  Startup      what starts at logon (Run keys and Startup folders), its
               publisher, enabled or not, and its impact measured from the
               recording of the three minutes after Windows started (needs
               Record from logon); enable or disable.
  Users        signed-in sessions with their CPU and memory;
               disconnect, sign out (each needs a second click).
  Settings     update speed (0.5 s, 1 s, 4 s, paused), the page to open on,
               always on top, recording, recording from logon, run as
               administrator, and opening on Ctrl+Shift+Esc.
- History strip: drag to look back at any recorded moment. Every view
  follows it. Press Live to come back. Actions are off while you look back.
- A reading the machine cannot supply says why. It is never shown as 0.

Administrator rights
--------------------
taskman runs without them. Some actions on other users' or system
processes and services are then refused, and say so. Settings > Restart as
administrator asks Windows (the usual prompt) and reopens on the same page.

Ctrl+Shift+Esc: with administrator rights, Settings > "Open simple_taskman
on Ctrl+Shift+Esc" makes Ctrl+Shift+Esc (and anything else that starts Task
Manager) open simple_taskman, the way Process Explorer does it. Turn it off
the same way. Uninstall refuses while it is on, so Ctrl+Shift+Esc is never
left opening nothing.

Recording
---------
taskman records while it runs, to %LOCALAPPDATA%\simple_taskman\trace.db:
every second for the last hour, every 10 seconds for a day, every minute
for 30 days, at most 250 MB. Measured: about 6 to 13 MB written an hour.
Only one taskman records at a time; a second one shows the same history.
Settings > "Record from logon" starts taskman_recorder.exe (no window) at
every logon, so history exists from boot even when the window is closed.
Start "simple_taskman (do not record)" from the Start menu to watch
without recording.

Options: --history SECONDS (open looking back), --no-record, --size WxH,
--select PID, --page NAME (processes, performance, services, startup,
users, settings), --replay FILE. Settings live in
%LOCALAPPDATA%\simple_taskman\settings.toml.

Command line (taskman_cli.exe)
------------------------------
  taskman_cli snapshot [--top N] [--self]     what is running now
  taskman_cli capabilities                     what this PC can measure
  taskman_cli trace [--ago SECONDS] [--top N]  what the recording holds and
                                               what ran at that moment
  taskman_cli clockwatch [--seconds S]         clock check across sleep

Test loads (taskman_stress.exe)
-------------------------------
  taskman_stress cpu --threads 4 --seconds 30
  taskman_stress memory --mb 512 --seconds 30
  taskman_stress disk --path C:\Temp --mb 256 --seconds 30

Not in this version
-------------------
Per-process network and GPU columns, and the App history and Details
tabs of Task Manager.

Source: https://github.com/simple-eiffel/simple_taskman
