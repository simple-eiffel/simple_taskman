note
	description: "[
		Phase 6 for the recorder: hostile files, damaged rows, gap frames in
		retention, pins over the size cap, and two hours of frames at scale.
		A bad file must yield a reason, never an exception or a fake frame.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_HARDEN_RECORDER

inherit
	TM_TEST_SET

feature -- Tests: hostile files

	test_damaged_payload_is_skipped_with_a_reason
		local
			l_path: STRING_32
			l_store: TM_SQLITE_TRACE_STORE
			l_db: SIMPLE_SQL_DATABASE
		do
			l_path := fresh_trace ("taskman_harden_damaged.db")
			create l_store.make_writer (l_path, small_policy)
			fill (l_store, 5)
			l_store.close
			create l_db.make (l_path)
			l_db.perform ("UPDATE frames SET payload = X'0102030405' WHERE id = 3")
			assert_false ("damage written", l_db.has_error)
			l_db.close
			create l_store.make_reader (l_path)
			assert_integers_equal ("four of five come back", 4, l_store.window (T0, T0 + 5 * One_second).count)
			assert_string_contains ("says why", l_store.last_error, "damaged frame")
			assert_void ("the damaged moment is not invented", l_store.frame_nearest (T0 + 2 * One_second + 1))
			assert_string_not_empty ("and says why", l_store.last_error)
			l_store.close
			delete_trace (l_path)
		end

	test_newer_format_is_refused
		local
			l_path: STRING_32
			l_store: TM_SQLITE_TRACE_STORE
			l_db: SIMPLE_SQL_DATABASE
		do
			l_path := fresh_trace ("taskman_harden_v2.db")
			create l_store.make_writer (l_path, small_policy)
			l_store.close
			create l_db.make (l_path)
			l_db.perform ("UPDATE meta SET value = '2' WHERE key = 'schema_version'")
			l_db.close
			create l_store.make_writer (l_path, small_policy)
			assert_false ("not writable", l_store.is_writable)
			assert_string_contains ("names the format", l_store.last_error, "format 2")
			delete_trace (l_path)
		end

	test_a_database_that_is_not_a_recording_is_refused
		local
			l_path: STRING_32
			l_store: TM_SQLITE_TRACE_STORE
			l_db: SIMPLE_SQL_DATABASE
		do
			l_path := fresh_trace ("taskman_harden_other.db")
			create l_db.make (l_path)
			l_db.perform ("CREATE TABLE notes (body TEXT)")
			l_db.close
			create l_store.make_reader (l_path)
			assert_false ("not open", l_store.is_open)
			assert_string_contains ("says so", l_store.last_error, "not a simple_taskman recording")
			delete_trace (l_path)
		end

	test_a_text_file_is_refused
		local
			l_path: STRING_32
			l_store: TM_SQLITE_TRACE_STORE
		do
			l_path := fresh_trace ("taskman_harden_text.db")
			write_file (l_path, "this is not a database%N")
			create l_store.make_reader (l_path)
			assert_false ("not open", l_store.is_open)
			assert_string_not_empty ("reason", l_store.last_error)
			create l_store.make_writer (l_path, small_policy)
			assert_false ("not writable either", l_store.is_writable)
			assert_string_not_empty ("reason", l_store.last_error)
			delete_trace (l_path)
		end

feature -- Tests: retention edge cases

	test_gap_frames_move_alone_in_both_stores
		local
			l_path: STRING_32
			l_sqlite: TM_SQLITE_TRACE_STORE
			l_memory: TM_MEMORY_TRACE_STORE
			l_policy: TM_RETENTION_POLICY
			l_gaps: INTEGER
		do
			create l_policy.make (10, 20, 1_000, 250 * Mib, 0.01, 102_400.0, 256 * Mib, 40)
			l_path := fresh_trace ("taskman_harden_gap.db")
			create l_sqlite.make_writer (l_path, l_policy)
			create l_memory.make (l_policy)
			with_gap (l_sqlite)
			with_gap (l_memory)
			l_sqlite.apply_retention
			l_memory.apply_retention
			assert_integers_equal ("same count", l_memory.frame_count, l_sqlite.frame_count)
			across l_sqlite.entries as ic loop
				if ic.is_discontinuity then
					l_gaps := l_gaps + 1
					assert_true ("gap kept its own span", ic.end_ticks - ic.start_ticks = 45 * One_second)
				end
			end
			assert_integers_equal ("one gap, never merged", 1, l_gaps)
			l_sqlite.close
			delete_trace (l_path)
		end

	test_pinned_frames_survive_the_size_cap
		local
			l_path: STRING_32
			l_store: TM_SQLITE_TRACE_STORE
			l_pinned: INTEGER
			i: INTEGER
		do
			l_path := fresh_trace ("taskman_harden_pin_cap.db")
			create l_store.make_writer (l_path, create {TM_RETENTION_POLICY}.make (100_000, 100_000, 100_000, 32 * 1024, 0.01, 102_400.0, 256 * Mib, 40))
			from i := 0 until i = 200 loop
				l_store.append (merger.reduced (frame_with (T0 + i * One_second, 1, <<activity (1, 0.5, 300, 4096.0), activity (2, 1.5, 10, 0.0)>>, 25.0)))
				i := i + 1
			end
			l_store.pin (T0, T0 + 5 * One_second)
			l_store.apply_retention
			across l_store.entries as ic loop
				if ic.is_pinned then
					l_pinned := l_pinned + 1
				end
			end
			assert_integers_equal ("five pinned frames kept", 5, l_pinned)
			assert_true ("newest kept", l_store.latest_ticks = T0 + 200 * One_second)
			assert_true ("others went", l_store.frame_count < 200)
			l_store.close
			delete_trace (l_path)
		end

	test_out_of_order_append_is_refused
		local
			l_store: TM_MEMORY_TRACE_STORE
		do
			create l_store.make (small_policy)
			fill (l_store, 3)
			assert_true ("precondition", raises (agent l_store.append (merger.reduced (frame_with_cpu (T0, 1, 5.0)))))
			assert_integers_equal ("unchanged", 3, l_store.frame_count)
		end

	test_bad_policies_are_refused
		do
			assert_true ("tier ages must grow", raises (agent new_policy (60, 30, 90)))
			assert_true ("ages must be positive", raises (agent new_policy (0, 30, 90)))
		end

feature -- Tests: scale

	test_two_hours_of_frames_retain_in_time
		local
			l_path: STRING_32
			l_store: TM_SQLITE_TRACE_STORE
			l_clock: TM_SYSTEM_CLOCK
			l_before, l_ms: INTEGER_64
			l_tier1: INTEGER
		do
			l_path := fresh_trace ("taskman_harden_scale.db")
			create l_store.make_writer (l_path, create {TM_RETENTION_POLICY}.make_default)
			fill (l_store, 7_200)
			create l_clock.make
			l_before := l_clock.monotonic_ticks
			l_store.apply_retention
			l_ms := (l_clock.monotonic_ticks - l_before) // 10_000
			across l_store.entries as ic loop
				if ic.tier = 1 then
					l_tier1 := l_tier1 + 1
				end
			end
			assert_integers_equal ("first hour became 10 s frames", 360, l_tier1)
			assert_integers_equal ("second hour stays at 1 s", 3_600 + 360, l_store.frame_count)
			assert_true ("one pass of a full hour within 10 s: " + l_ms.out + " ms", l_ms < 10_000)
			l_store.close
			delete_trace (l_path)
		end

feature {NONE} -- Fixtures

	Mib: INTEGER_64 = 1_048_576

	T0: INTEGER_64 = 133_699_999_800_000_000
			-- A whole number of minutes (see TEST_RECORDER).

	small_policy: TM_RETENTION_POLICY
		do
			create Result.make (60, 600, 3_600, 250 * Mib, 0.01, 102_400.0, 256 * Mib, 40)
		end

	merger: TM_FRAME_MERGER
		do
			create Result.make (create {TM_RETENTION_POLICY}.make_default)
		end

	new_policy (a_t0, a_t1, a_t2: INTEGER_64)
		local
			l_policy: TM_RETENTION_POLICY
		do
			create l_policy.make (a_t0, a_t1, a_t2, Mib, 0.01, 1.0, Mib, 1)
		end

	activity (a_pid: INTEGER_64; a_cores: REAL_64; a_private_mb: INTEGER_64; a_io_bps: REAL_64): TM_PROCESS_ACTIVITY
		do
			create Result.make_decoded (id (a_pid, 1000 + a_pid), {STRING_32} "p" + a_pid.out.to_string_32, 4, 1, 8, 100, False, 4,
				{TM_READING_STATUS}.Available, a_cores,
				{TM_READING_STATUS}.Available, a_private_mb * Mib, a_private_mb * Mib,
				{TM_READING_STATUS}.Available, a_io_bps, 0.0)
		end

	frame_with (a_start: INTEGER_64; a_seconds: INTEGER; a_activities: ARRAY [TM_PROCESS_ACTIVITY]; a_busy: REAL_64): TM_FRAME
		local
			l_readings: TM_READINGS
		do
			create l_readings.make
			l_readings.put ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "", measured ({TM_METRICS}.Cpu_busy_pct, a_busy))
			create Result.make (a_start, a_start + a_seconds * One_second, a_seconds * One_second, 4, False,
				l_readings, create {ARRAYED_LIST [TM_PROCESS_ACTIVITY]}.make_from_array (a_activities),
				create {ARRAYED_LIST [TM_PROCESS_ID]}.make (0),
				create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0))
		end

	with_gap (a_store: TM_TRACE_STORE)
			-- 30 one-second frames, a 45 s gap frame, then 30 more.
		local
			i: INTEGER
		do
			from i := 0 until i = 30 loop
				a_store.append (merger.reduced (frame_with_cpu (T0 + i * One_second, 1, 20.0)))
				i := i + 1
			end
			a_store.append (merger.reduced (create {TM_FRAME}.make_discontinuity (T0 + 30 * One_second, T0 + 75 * One_second,
				45 * One_second, 4, False, <<{TM_METRICS}.Cpu_busy_pct>>)))
			from i := 0 until i = 30 loop
				a_store.append (merger.reduced (frame_with_cpu (T0 + (75 + i) * One_second, 1, 20.0)))
				i := i + 1
			end
		end

	fill (a_store: TM_TRACE_STORE; a_count: INTEGER)
			-- `a_count' one-second frames from T0.
		local
			i: INTEGER
		do
			from i := 0 until i = a_count loop
				a_store.append (merger.reduced (frame_with_cpu (T0 + i * One_second, 1, (i \\ 100).to_double)))
				i := i + 1
			end
		end

	fresh_trace (a_name: STRING_32): STRING_32
		do
			Result := scratch_path (a_name)
			delete_trace (Result)
		end

	delete_trace (a_path: STRING_32)
		do
			delete_file (a_path)
			delete_file (a_path + {STRING_32} "-wal")
			delete_file (a_path + {STRING_32} "-shm")
		end

end
