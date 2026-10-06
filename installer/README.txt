simple_taskman 0.2.0
====================

A diagnostic task manager for Windows, written in Eiffel. It shows what the
machine is doing, records it, and lets you look back at any moment.

The window (taskman.exe)
------------------------
- Four tiles: CPU (% Processor Utility, as Task Manager shows it), memory
  commit, the busiest disk, and CPU package power, each with a line.
- The process list: name, status (App, Not responding), PID, CPU, memory,
  disk. Click a column to sort. Your own taskman row is marked with *.
- Toolbar for the selected process: End task, End process, End tree,
  Efficiency (efficiency mode on or off), Lower or Raise priority, and Undo.
  End process and End tree need a second click within four seconds.
  Core Windows processes, and any process Windows marks critical, are
  refused. Every action checks it still has the same process, so a
  reused process id is never touched.
- History strip: drag to look back at any recorded moment. Every view
  follows it. Press Live to come back. Actions are off while you look back.
- Right side: a core heatmap; the Selected process tab (path, command
  line, user, elevated, architecture, priority, efficiency mode, window);
  and This machine (what this PC can and cannot measure, and why).
- A reading the machine cannot supply says why. It is never shown as 0.

Recording
---------
taskman records while it runs, to %LOCALAPPDATA%\simple_taskman\trace.db:
every second for the last hour, every 10 seconds for a day, every minute
for 30 days, at most 250 MB. Measured: about 6 to 13 MB written an hour.
Only one taskman records at a time; a second one shows the same history.
Start "simple_taskman (do not record)" from the Start menu to watch
without recording.

Options: --history SECONDS (open looking back), --no-record,
--select PID, --replay FILE.

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
The "why is it slow" verdict, forecasts, Services, Startup apps, Users,
network and GPU pages, settings, run as administrator, and opening on
Ctrl+Shift+Esc are planned (see the project's intent-v3).

Source: https://github.com/simple-eiffel/simple_taskman
