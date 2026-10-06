# Phase 2 (Remember) - Phase 2: adversarial review of the recorder contracts
# STATUS: COMPLETE  Date: 2026-10-06  Model: Claude (self-review)
# Approval: delegated - Larry, 2026-10-06: "Do your best. I take your recommendations"

### ISSUE 1: merged mean can leave the metric range by rounding
- LOCATION: TM_FRAME_MERGER.merged (readings)
- SEVERITY: HIGH
- DESCRIPTION: a duration-weighted mean of in-range values can exceed the maximum by one ulp
  (e.g. 100.0 averaged), and make_measured would then make the merged reading invalid.
- SUGGESTION: clamp each mean to [min, max] of its inputs before make_measured. ACCEPTED.

### ISSUE 2: size-cap test could not reach the cap code
- LOCATION: TEST_RECORDER.test_sqlite_size_cap_deletes_oldest
- SEVERITY: MEDIUM
- DESCRIPTION: with short ages, merging alone shrinks the file below the cap.
- SUGGESTION: ages of 100,000 s so only the cap can delete; assert over-cap before. APPLIED.

### ISSUE 3: cap deletion vs. "newest kept"
- LOCATION: TM_TRACE_STORE.apply_retention (newest_kept) / TM_SQLITE_TRACE_STORE
- SEVERITY: MEDIUM
- DESCRIPTION: a cap smaller than the newest frames could delete everything.
- SUGGESTION: delete oldest unpinned frames of any tier, oldest first, never the newest frame. ACCEPTED.

### ISSUE 4: queries that record a decode failure
- LOCATION: TM_TRACE_STORE.frame_nearest, window
- SEVERITY: LOW (CQS)
- DESCRIPTION: a damaged payload sets last_error inside a query.
- SUGGESTION: keep; it is the documented error-state exception of the CQS audit (Phase 4.5 rule 4),
  stated in the postcondition `said_why`.

### ISSUE 5: read-only WAL open after the writer closed
- LOCATION: TM_SQLITE_TRACE_STORE.make_reader
- SEVERITY: MEDIUM (to verify)
- DESCRIPTION: a read-only connection cannot create the -shm file of a WAL database.
- SUGGESTION: test test_sqlite_round_trip opens a reader after the writer closed; if it fails,
  fall back to a read-write connection that never writes (is_writable stays False).

### ISSUE 6: out-of-order frames across recorder restarts
- LOCATION: TM_TRACE_STORE.append (in_order)
- SEVERITY: MEDIUM
- DESCRIPTION: a new session's timeline can start before the stored latest_ticks (the UTC offset
  resets on restart, or the clock moved back while not recording).
- SUGGESTION: the recording client skips such frames and counts them (skipped_out_of_order); the
  store keeps its precondition. ACCEPTED for the facade task.

### ISSUE 7: retention cost on a full file
- LOCATION: TM_SQLITE_TRACE_STORE.apply_retention
- SEVERITY: MEDIUM (performance)
- DESCRIPTION: loading all ~55,000 entries per pass is too slow for the sampling processor.
- SUGGESTION: per tier, load only entries with end_ticks <= cutoff and (tier = T or pinned = 1);
  ages run on the store's own latest_ticks, which only grows, so higher-tier frames never sit among
  tier T candidates. ACCEPTED.

Overall: PASS WITH CONDITIONS (issues 1, 3, 5, 6, 7 handled in implementation).
