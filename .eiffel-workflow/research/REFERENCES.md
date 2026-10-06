# REFERENCES: simple_taskman

Date: 2026-10-03

**[fetched]** = page retrieved with WebFetch in this session; the note says what
was learned from the page itself.
**[search hit]** = URL returned by WebSearch and **not opened**; the note is the
search engine's summary and is used only as a lead, never as the sole support
for a design decision.

## Source material
- `D:\prod\simple_taskman\YouTube\Why Your Computer Is Slow — Task Manager Can't Tell You, but TMOG can!.md`
  Caption transcript of https://www.youtube.com/watch?v=z_mFHlUpC-g (Dave's Garage, 15:45). Read in full. Source of: measurement versus diagnosis, flight recorder, gap instead of zero, pid as hotel room number, shared C++ core, the Ryzen power-budget story, benchmark score.

## Documentation Consulted (all [fetched])
- https://tmog.org : platforms and toolkits per host, "one shared C++20 measuring core", twelve dashboard destinations, "Energy has a cause", Flight Recorder Pro with `.tmogtrace`, no telemetry sent. Sensor acquisition method not stated. No AI feature listed.
- https://learn.microsoft.com/en-us/windows/win32/api/winternl/nf-winternl-ntquerysysteminformation : `SystemProcessInformation` returns one `SYSTEM_PROCESS_INFORMATION` per process followed by thread records; needed fields documented as Reserved; "may be altered or unavailable"; use run-time dynamic linking; new `SystemBasicProcessInformation` with `SequenceNumber` "used to detect UniqueProcessId reuse", from build 26100.4770; per-processor idle, kernel, user times in 100 ns units.
- https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-processor_relationship : `EfficiencyClass` per core; higher value means more performance and less efficiency; nonzero only on heterogeneous systems; Windows 10 and later.
- https://learn.microsoft.com/en-us/windows-hardware/drivers/powermeter/energy-meter-interface : Energy Metering Interface since Windows 10; device interface GUID; energy in picowatt-hours with arbitrary zero; average power by differencing two samples.
- https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setprocessinformation : `ProcessPowerThrottling` and EcoQoS; needs `PROCESS_SET_INFORMATION`; control mask and state mask allow turning it on, off, or back to system-managed; `ProcessMemoryPriority`.
- https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_cpu_rate_control_information : job CPU rate control: hard cap as cycles per 10,000, weight 1 to 9, min and max rates; Windows 8 and later. Does not say whether a running process can be assigned afterward.
- https://learn.microsoft.com/en-us/windows/win32/debug/wait-chain-traversal : wait chain definition; covers ALPC, COM, critical sections, mutexes, SendMessage, waits on processes and threads; synchronous and asynchronous sessions.
- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-ishungappwindow : "not responding" means no `PeekMessage` within 5 seconds; function "not intended for general use".
- https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/rds-rdsh-performance-counters : User Input Delay counters; measure queue time of input before the app picks it up; report the maximum per interval because perception follows the slowest input; documented for Windows 10 1809 and later. **Local check contradicts availability on this machine.**
- https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer : handles and DLLs per process; search for who holds a file; no recorder.
- https://docs.rs/sysinfo/latest/sysinfo/ : long-lived system object, explicit refresh, refresh kinds, minimum CPU update interval, components may be empty on virtual systems.

## Repositories Examined
- https://github.com/winsiderss/systeminformer **[fetched]** : MIT; real-time graphs, network, disk, stack traces, services; kernel component folder present; README does not mention wait-chain analysis or history.
- https://github.com/winsiderss/phnt **[search hit]** : native API headers used as the layout reference for the process table.
- `C:\Program Files\Eiffel Software\EiffelStudio 25.02 Standard\library\process\classic\windows\wel_toolhelp.e` and `...\process\base\platform\windows\process_utility.e` (local, read by grep) : ISE Toolhelp wrapper; pid, parent pid, thread count, base priority, exe name only.
- `D:\prod\simple_system\src\simple_system.e`, `D:\prod\simple_speech\src\batch\speech_memory_monitor.e`, `D:\prod\simple_widgets\README.md` (local) : ecosystem state.

## Articles/Papers
- https://www.engadget.com/2262039/vibe-coded-modern-task-manager-runs-on-mac-and-linux/ **[fetched]** : TMOG built with Claude Code from a "107-page spec sheet", under six weeks, two collaborators; free tier live monitoring, Pro $39.95 adds Flight Recorder; beta; no App Store because of sandboxing.
- https://devblogs.microsoft.com/performance-diagnostics/reduce-process-interference-with-task-manager-efficiency-mode/ **[fetched]** : Efficiency mode equals low base priority plus EcoQoS; "14% ~ 76%" responsiveness improvement measured by app launch and Start Menu times under synthetic CPU load; CPU only; greyed out for core processes.
- https://bitsum.com/how-probalance-works/ **[fetched]** : ProBalance temporarily lowers the priority class of the offending process; priority only; thresholds and effect verification not documented on the page.
- https://people.csail.mit.edu/cpacheco/publications/daikon-tool-scp2006.pdf **[search hit]** : Daikon, dynamic detection of likely invariants from observed values; lead for "propose contracts from baseline".
- https://medium.com/@boutnaru/the-windows-forensic-journey-srum-system-resource-usage-monitor-d6926aac316c and https://github.com/libyal/esedb-kb/blob/main/documentation/System%20Resource%20Usage%20Monitor%20(SRUM).asciidoc **[search hits]** : Windows SRUM keeps roughly 30 days of per-application resource and energy data in an ESE database, flushed hourly.
- https://diskanalyzer.com/about **[search hit]** : WizTree reads the NTFS Master File Table directly for speed.
- https://minidump.net/measuring-ui-responsiveness/ **[search hit]** : measuring UI responsiveness by hooking the message loop; lead only.

## Discussions/Forums
- https://x.com/davepl1968/status/2099322418968068149 **[search hit]** : Plummer on TMOG beta 3: Linux Qt 6 host, "tombstone rows" for dead processes.
- https://x.com/davepl1968/status/2091923020269178925 **[search hit]** : Plummer announcing Flight Recorder in TMOG Pro.
- https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/commit/eb5e1a20be996d4865170b13bab97af43d97f341 **[search hit]** : LibreHardwareMonitor moved from WinRing0 to PawnIO; no-driver profile omits CPU and motherboard sensors.
- https://github.com/mgradwohl/tasksmack/issues/1033 **[search hit]** : Task Manager's GPU figure is the busiest engine, not the sum of engines; affects FR-010.
- https://www.thewindowsclub.com/analyze-wait-chain-traversal **[search hit]** : Resource Monitor's "Analyze Wait Chain" menu item.
- https://psutil.readthedocs.io/ **[search hit]** : Python psutil; not examined.

## Local Evidence
- `.eiffel-workflow/evidence/hardware-probe-2026-10-03.txt` : pasted output of every local probe and spike cited in these documents.

## Counts
- Fetched and read: 15 URLs
- Search hits recorded as leads: 12 URLs
- Local files and command outputs: see evidence file
