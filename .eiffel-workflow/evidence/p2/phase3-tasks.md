# Phase 2 (Remember) - Phase 3: tasks
# Approval: delegated (Larry, 2026-10-06)

1. TM_RETENTION_POLICY bodies (done during contracts: trivial).
2. TM_FRAME_MERGER.reduced: round-robin over CPU, disk, memory rankings of significant activities.
3. TM_FRAME_MERGER.merged: readings (weighted mean, peak max, clamp, best reason), activities
   (weighted rates, latest memory), born/exited union, then reduce.
4. TM_RETENTION_PLANNER.groups.
5. TM_SINGLE_WRITER: CreateMutexW in the Local\ namespace (inline C), release by CloseHandle.
6. TM_MEMORY_TRACE_STORE: list store, window, nearest, entries, retention via planner + merger, pin.
7. TM_SQLITE_TRACE_STORE: schema v1, WAL, open transaction with commits every 10 frames, payload via
   TM_FRAME_CODEC, process rows, window/nearest/entries, retention (filtered queries), pin, size cap,
   incremental vacuum, reader mode.
8. Recording client: SIMPLE_TASKMAN.attach_store / recording through the facade (reduce, in-order guard,
   retention every 60 frames); TM_SAMPLING_WORKER owns writer lock + SQLite store.
9. GUI: DVR scrub control (slider + Live) driving every view from a reader store.
10. Gate measurements: one-hour recording soak (file size, bytes written per hour, window cost).
Dependencies: 2-3 before 6-7; 4 before 6-7; 5 and 7 before 8; 8 before 9 and 10.
