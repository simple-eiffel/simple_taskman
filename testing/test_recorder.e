note
	description: "[
		Phase 2 ("Remember"): retention policy, frame reduction and merging,
		the retention planner, the in-memory and SQLite trace stores, and the
		single-writer lock. Times start at T0, which sits on a 60-second
		boundary (TM_TEST_SET.Base_utc does not), so bucket arithmetic in the
		expectations is plain.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_RECORDER

inherit
	TM_TEST_SET

feature -- Tests: policy

	test_policy_defaults
		local
			l_policy: TM_RETENTION_POLICY
		do
			create l_policy.make_default
			assert_true ("hour, day, month", l_policy.age_limit_seconds (0) = 3_600
				and l_policy.age_limit_seconds (1) = 86_400 and l_policy.age_limit_seconds (2) = 2_592_000)
			assert_true ("1, 10, 60 s", l_policy.resolution_seconds (0) = 1 and l_policy.resolution_seconds (1) = 10
				and l_policy.resolution_seconds (2) = 60)
			assert_true ("250 MB", l_policy.size_cap_bytes = 250 * 1_048_576)
			assert_integers_equal ("40 processes", 40, l_policy.max_processes)
		end

	test_policy_significance
		local
			l_policy: TM_RETENTION_POLICY
		do
			create l_policy.make_default
			assert_true ("busy", l_policy.is_significant (activity (10, 0.5, 10, 0.0)))
			assert_true ("big", l_policy.is_significant (activity (11, 0.0, 300, 0.0)))
			assert_true ("disk", l_policy.is_significant (activity (12, 0.0, 10, 500_000.0)))
			assert_true ("born", l_policy.is_significant (newborn (13)))
			assert_false ("quiet", l_policy.is_significant (activity (14, 0.001, 10, 10.0)))
		end

	test_policy_buckets
		local
			l_policy: TM_RETENTION_POLICY
		do
			create l_policy.make_default
			assert_true ("same 10 s bucket", l_policy.bucket_of (T0, 1) = l_policy.bucket_of (T0 + 9 * One_second, 1))
			assert_true ("next 10 s bucket", l_policy.bucket_of (T0 + 10 * One_second, 1) = l_policy.bucket_of (T0, 1) + 1)
			assert_true ("same minute", l_policy.bucket_of (T0, 2) = l_policy.bucket_of (T0 + 59 * One_second, 2))
		end

feature -- Tests: merger

	test_reduce_keeps_significant_only
		local
			l_frame, l_reduced: TM_FRAME
		do
			l_frame := frame_with (T0, 1, <<activity (1, 0.5, 10, 0.0), activity (2, 0.0, 10, 0.0), activity (3, 0.0, 400, 0.0)>>, 20.0)
			l_reduced := merger.reduced (l_frame)
			assert_integers_equal ("two kept", 2, l_reduced.activity_count)
			assert_true ("busy kept", l_reduced.has_activity (id (1, 1001)))
			assert_true ("big kept", l_reduced.has_activity (id (3, 1003)))
			assert_integers_equal ("one omitted", 1, l_reduced.omitted_processes)
			assert_true ("readings shared", l_reduced.readings = l_frame.readings)
		end

	test_reduce_caps_and_counts_omitted
		local
			l_list: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			l_frame, l_reduced: TM_FRAME
			i: INTEGER
		do
			create l_list.make (60)
			from i := 1 until i > 60 loop
				l_list.extend (activity (i, 0.02 + i / 1000, 10, 0.0))
				i := i + 1
			end
			l_frame := frame_from_list (T0, 1, l_list, 50.0)
			l_reduced := merger.reduced (l_frame)
			assert_integers_equal ("capped at 40", 40, l_reduced.activity_count)
			assert_integers_equal ("20 omitted", 20, l_reduced.omitted_processes)
			assert_true ("busiest kept", l_reduced.has_activity (id (60, 1060)))
		end

	test_reduce_picks_from_each_ranking
		local
			l_list: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			l_frame, l_reduced: TM_FRAME
			i: INTEGER
		do
			create l_list.make (60)
			from i := 1 until i > 58 loop
				l_list.extend (activity (i, 0.5 + i / 1000, 10, 0.0))
				i := i + 1
			end
			l_list.extend (activity (101, 0.0, 10, 50_000_000.0))
			l_list.extend (activity (102, 0.0, 9_000, 0.0))
			l_frame := frame_from_list (T0, 1, l_list, 50.0)
			l_reduced := merger.reduced (l_frame)
			assert_true ("top disk kept", l_reduced.has_activity (id (101, 1101)))
			assert_true ("top memory kept", l_reduced.has_activity (id (102, 1102)))
			assert_true ("top cpu kept", l_reduced.has_activity (id (58, 1058)))
		end

	test_merge_weighted_mean
		local
			l_frames: ARRAYED_LIST [TM_FRAME]
			l_merged: TM_FRAME
		do
			create l_frames.make (2)
			l_frames.extend (frame_with_cpu (T0, 1, 10.0))
			l_frames.extend (frame_with_cpu (T0 + One_second, 3, 50.0))
			l_merged := merger.merged (l_frames)
			assert_reals_equal ("duration-weighted", 40.0, l_merged.readings.reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "").value, 1.0e-9)
			assert_true ("spans both", l_merged.start_ticks = T0 and l_merged.end_ticks = T0 + 4 * One_second)
			assert_true ("durations summed", l_merged.duration = 4 * One_second)
			assert_false ("recorded", l_merged.is_complete)
		end

	test_merge_peak_takes_max
		local
			l_frames: ARRAYED_LIST [TM_FRAME]
			l_merged: TM_FRAME
		do
			create l_frames.make (3)
			l_frames.extend (frame_with_reading (T0, 1, {TM_METRICS}.Lag_max_ms, measured ({TM_METRICS}.Lag_max_ms, 20.0)))
			l_frames.extend (frame_with_reading (T0 + One_second, 1, {TM_METRICS}.Lag_max_ms, measured ({TM_METRICS}.Lag_max_ms, 900.0)))
			l_frames.extend (frame_with_reading (T0 + 2 * One_second, 1, {TM_METRICS}.Lag_max_ms, measured ({TM_METRICS}.Lag_max_ms, 30.0)))
			l_merged := merger.merged (l_frames)
			assert_reals_equal ("peak", 900.0, l_merged.readings.reading ({TM_METRICS}.Lag_max_ms, {STRING_32} "").value, 1.0e-9)
		end

	test_merge_never_available_keeps_reason
		local
			l_frames: ARRAYED_LIST [TM_FRAME]
			l_merged: TM_FRAME
		do
			create l_frames.make (2)
			l_frames.extend (frame_with_reading (T0, 1, {TM_METRICS}.Cpu_package_watts, create {TM_READING}.make_unavailable))
			l_frames.extend (frame_with_reading (T0 + One_second, 1, {TM_METRICS}.Cpu_package_watts, create {TM_READING}.make_access_denied))
			l_merged := merger.merged (l_frames)
			assert_true ("most useful reason", l_merged.readings.reading ({TM_METRICS}.Cpu_package_watts, {STRING_32} "").status = {TM_READING_STATUS}.Access_denied)
		end

	test_merge_partly_available_uses_measured_time_only
		local
			l_frames: ARRAYED_LIST [TM_FRAME]
			l_merged: TM_FRAME
		do
			create l_frames.make (2)
			l_frames.extend (frame_with_reading (T0, 1, {TM_METRICS}.Cpu_package_watts, measured ({TM_METRICS}.Cpu_package_watts, 40.0)))
			l_frames.extend (frame_with_reading (T0 + One_second, 5, {TM_METRICS}.Cpu_package_watts, create {TM_READING}.make_unavailable))
			l_merged := merger.merged (l_frames)
			assert_reals_equal ("mean of what was measured, not a zero", 40.0,
				l_merged.readings.reading ({TM_METRICS}.Cpu_package_watts, {STRING_32} "").value, 1.0e-9)
		end

	test_merge_process_rates_and_memory
		local
			l_frames: ARRAYED_LIST [TM_FRAME]
			l_merged: TM_FRAME
			l_activity: TM_PROCESS_ACTIVITY
		do
			create l_frames.make (2)
			l_frames.extend (frame_with (T0, 1, <<activity (7, 1.0, 300, 0.0)>>, 30.0))
			l_frames.extend (frame_with (T0 + One_second, 3, <<activity (7, 3.0, 500, 0.0)>>, 30.0))
			l_merged := merger.merged (l_frames)
			assert_true ("present", l_merged.has_activity (id (7, 1007)))
			l_activity := l_merged.activity (id (7, 1007))
			assert_reals_equal ("weighted cores", 2.5, l_activity.cpu_cores, 1.0e-9)
			assert_true ("latest memory", l_activity.private_bytes = 500 * Mib)
		end

	test_merge_flags
		local
			l_frames: ARRAYED_LIST [TM_FRAME]
			l_merged: TM_FRAME
		do
			create l_frames.make (2)
			l_frames.extend (frame_with_cpu (T0, 1, 10.0))
			l_frames.extend (adjusted_frame (T0 + One_second, 1))
			l_merged := merger.merged (l_frames)
			assert_true ("adjusted if any", l_merged.is_clock_adjusted)
			assert_false ("live", l_merged.is_discontinuity)
		end

feature -- Tests: planner

	test_planner_groups_by_bucket
		local
			l_groups: ARRAYED_LIST [TM_MERGE_GROUP]
		do
			l_groups := planner.groups (seconds_entries (25), 0, T0 + 20 * One_second)
			assert_integers_equal ("two buckets", 2, l_groups.count)
			assert_integers_equal ("ten in the first", 10, l_groups [1].ids.count)
			assert_integers_equal ("ten in the second", 10, l_groups [2].ids.count)
			assert_integers_equal ("to tier 1", 1, l_groups [1].target_tier)
		end

	test_planner_breaks_at_pin_and_gap
		local
			l_entries: ARRAYED_LIST [TM_TRACE_ENTRY]
			l_groups: ARRAYED_LIST [TM_MERGE_GROUP]
		do
			create l_entries.make (10)
			l_entries.extend (create {TM_TRACE_ENTRY}.make (1, T0, T0 + One_second, 0, False, False))
			l_entries.extend (create {TM_TRACE_ENTRY}.make (2, T0 + One_second, T0 + 2 * One_second, 0, False, False))
			l_entries.extend (create {TM_TRACE_ENTRY}.make (3, T0 + 2 * One_second, T0 + 3 * One_second, 0, True, False))
			l_entries.extend (create {TM_TRACE_ENTRY}.make (4, T0 + 3 * One_second, T0 + 4 * One_second, 0, False, False))
			l_entries.extend (create {TM_TRACE_ENTRY}.make (5, T0 + 4 * One_second, T0 + 6 * One_second, 0, False, True))
			l_entries.extend (create {TM_TRACE_ENTRY}.make (6, T0 + 6 * One_second, T0 + 7 * One_second, 0, False, False))
			l_groups := planner.groups (l_entries, 0, T0 + 60 * One_second)
			assert_integers_equal ("runs: 1-2, 4, gap 5, 6", 4, l_groups.count)
			assert_integers_equal ("first run", 2, l_groups [1].ids.count)
			assert_true ("gap alone", l_groups [3].ids.count = 1 and l_groups [3].ids.first = 5)
			assert_true ("pinned never planned", across l_groups as g all not g.ids.has (3) end)
		end

	test_planner_ignores_young_frames
		do
			assert_integers_equal ("nothing old enough", 0, planner.groups (seconds_entries (25), 0, T0).count)
		end

feature -- Tests: memory store

	test_memory_store_append_window_nearest
		local
			l_store: TM_MEMORY_TRACE_STORE
			l_window: TM_WINDOW
		do
			create l_store.make (small_policy)
			fill (l_store, 30)
			assert_integers_equal ("thirty", 30, l_store.frame_count)
			assert_true ("span", l_store.earliest_ticks = T0 and l_store.latest_ticks = T0 + 30 * One_second)
			l_window := l_store.window (T0 + 10 * One_second, T0 + 20 * One_second)
			assert_integers_equal ("ten inside", 10, l_window.count)
			if attached l_store.frame_nearest (T0 + 15 * One_second + 5) as al_frame then
				assert_true ("holds the instant", al_frame.start_ticks = T0 + 15 * One_second)
			else
				assert_true ("found", False)
			end
			if attached l_store.frame_nearest (T0 + 99 * One_second) as al_late then
				assert_true ("nearest is newest", al_late.end_ticks = l_store.latest_ticks)
			else
				assert_true ("found late", False)
			end
		end

	test_memory_store_retention_merges_old_frames
		local
			l_store: TM_MEMORY_TRACE_STORE
		do
			create l_store.make (create {TM_RETENTION_POLICY}.make (60, 600, 3_600, 250 * Mib, 0.01, 102_400.0, 256 * Mib, 40))
			fill (l_store, 180)
			l_store.apply_retention
			assert_integers_equal ("12 merged + 60 recent", 72, l_store.frame_count)
			assert_integers_equal ("first is tier 1", 1, l_store.entries.first.tier)
			assert_true ("first spans 10 s", l_store.entries.first.end_ticks - l_store.entries.first.start_ticks = 10 * One_second)
			assert_integers_equal ("last is tier 0", 0, l_store.entries.last.tier)
			assert_true ("span unchanged", l_store.earliest_ticks = T0 and l_store.latest_ticks = T0 + 180 * One_second)
		end

	test_memory_store_retention_runs_all_tiers
		local
			l_store: TM_MEMORY_TRACE_STORE
		do
			create l_store.make (create {TM_RETENTION_POLICY}.make (10, 20, 40, 250 * Mib, 0.01, 102_400.0, 256 * Mib, 40))
			fill (l_store, 180)
			l_store.apply_retention
			assert_integers_equal ("tier 2, tier 1, ten tier 0", 12, l_store.frame_count)
			assert_true ("oldest kept tier 2 frame starts at 120 s", l_store.earliest_ticks = T0 + 120 * One_second)
			assert_integers_equal ("first tier 2", 2, l_store.entries.first.tier)
			assert_integers_equal ("second tier 1", 1, l_store.entries [2].tier)
		end

	test_memory_store_pinned_frames_survive
		local
			l_store: TM_MEMORY_TRACE_STORE
			l_pinned: INTEGER
		do
			create l_store.make (create {TM_RETENTION_POLICY}.make (10, 20, 40, 250 * Mib, 0.01, 102_400.0, 256 * Mib, 40))
			fill (l_store, 180)
			l_store.pin (T0 + 30 * One_second, T0 + 35 * One_second)
			l_store.apply_retention
			across l_store.entries as ic loop
				if ic.is_pinned then
					l_pinned := l_pinned + 1
					assert_integers_equal ("pinned stays tier 0", 0, ic.tier)
				end
			end
			assert_integers_equal ("five pinned kept", 5, l_pinned)
			assert_true ("pinned frames are the oldest left", l_store.earliest_ticks = T0 + 30 * One_second)
		end

feature -- Tests: SQLite store

	test_sqlite_round_trip
		local
			l_path: STRING_32
			l_writer: TM_SQLITE_TRACE_STORE
			l_reader: TM_SQLITE_TRACE_STORE
			l_codec: TM_FRAME_CODEC
			l_original: TM_FRAME
		do
			l_path := fresh_trace ("taskman_trace_round_trip.db")
			create l_writer.make_writer (l_path, small_policy)
			assert_string_empty ({STRING_32} "writer opened: " + l_writer.last_error, l_writer.last_error)
			l_original := merger.reduced (frame_with (T0, 1, <<activity (5, 1.25, 300, 2048.0)>>, 37.5))
			l_writer.append (l_original)
			fill_from (l_writer, T0 + One_second, 24)
			l_writer.close
			create l_reader.make_reader (l_path)
			assert_string_empty ({STRING_32} "reader opened: " + l_reader.last_error, l_reader.last_error)
			assert_integers_equal ("all frames", 25, l_reader.frame_count)
			assert_true ("span", l_reader.earliest_ticks = T0 and l_reader.latest_ticks = T0 + 25 * One_second)
			create l_codec.make
			if attached l_reader.frame_nearest (T0) as al_back then
				assert_true ("identical text", l_codec.encode (al_back).same_string (l_codec.encode (l_original)))
			else
				assert_true ({STRING_32} "readable: " + l_reader.last_error, False)
			end
			assert_integers_equal ("window", 25, l_reader.window (T0, T0 + 25 * One_second).count)
			l_reader.close
			delete_trace (l_path)
		end

	test_sqlite_keeps_non_ascii_names
		local
			l_path: STRING_32
			l_store: TM_SQLITE_TRACE_STORE
			l_name: STRING_32
			l_frame: TM_FRAME
		do
			l_name := {STRING_32} "%/0x05E1/%/0x05E4/%/0x05E8/ caf%/0xE9/.exe"
			l_path := fresh_trace ("taskman_trace_names.db")
			create l_store.make_writer (l_path, small_policy)
			l_frame := frame_with (T0, 1, <<named_activity (9, l_name)>>, 10.0)
			l_store.append (merger.reduced (l_frame))
			l_store.close
			create l_store.make_reader (l_path)
			if attached l_store.frame_nearest (T0) as al_back and then al_back.has_activity (id (9, 1009)) then
				assert_true ("name intact", al_back.activity (id (9, 1009)).name.same_string (l_name))
			else
				assert_true ({STRING_32} "readable: " + l_store.last_error, False)
			end
			l_store.close
			delete_trace (l_path)
		end

	test_sqlite_reader_sees_committed_frames_only
		local
			l_path: STRING_32
			l_writer, l_reader: TM_SQLITE_TRACE_STORE
		do
			l_path := fresh_trace ("taskman_trace_commits.db")
			create l_writer.make_writer (l_path, small_policy)
			fill (l_writer, 3)
			create l_reader.make_reader (l_path)
			assert_integers_equal ("none committed yet", 0, l_reader.frame_count)
			l_reader.close
			l_writer.flush
			create l_reader.make_reader (l_path)
			assert_integers_equal ("three after flush", 3, l_reader.frame_count)
			l_reader.close
			l_writer.close
			delete_trace (l_path)
		end

	test_sqlite_writer_reopens_and_continues
		local
			l_path: STRING_32
			l_writer: TM_SQLITE_TRACE_STORE
		do
			l_path := fresh_trace ("taskman_trace_reopen.db")
			create l_writer.make_writer (l_path, small_policy)
			fill (l_writer, 5)
			l_writer.close
			create l_writer.make_writer (l_path, small_policy)
			assert_integers_equal ("five back", 5, l_writer.frame_count)
			assert_true ("latest back", l_writer.latest_ticks = T0 + 5 * One_second)
			fill_from (l_writer, T0 + 5 * One_second, 5)
			assert_integers_equal ("ten", 10, l_writer.frame_count)
			l_writer.close
			delete_trace (l_path)
		end

	test_sqlite_retention_matches_memory
		local
			l_path: STRING_32
			l_sqlite: TM_SQLITE_TRACE_STORE
			l_memory: TM_MEMORY_TRACE_STORE
			l_policy: TM_RETENTION_POLICY
			l_same: BOOLEAN
			i: INTEGER
		do
			create l_policy.make (10, 20, 40, 250 * Mib, 0.01, 102_400.0, 256 * Mib, 40)
			l_path := fresh_trace ("taskman_trace_retention.db")
			create l_sqlite.make_writer (l_path, l_policy)
			create l_memory.make (l_policy)
			fill (l_sqlite, 180)
			fill (l_memory, 180)
			l_sqlite.pin (T0 + 30 * One_second, T0 + 35 * One_second)
			l_memory.pin (T0 + 30 * One_second, T0 + 35 * One_second)
			l_sqlite.apply_retention
			l_memory.apply_retention
			assert_integers_equal ("same count", l_memory.frame_count, l_sqlite.frame_count)
			l_same := l_memory.frame_count = l_sqlite.frame_count
			from i := 1 until not l_same or i > l_memory.frame_count loop
				l_same := l_memory.entries [i].start_ticks = l_sqlite.entries [i].start_ticks
					and l_memory.entries [i].end_ticks = l_sqlite.entries [i].end_ticks
					and l_memory.entries [i].tier = l_sqlite.entries [i].tier
				i := i + 1
			end
			assert_true ("same spans and tiers", l_same)
			l_sqlite.close
			delete_trace (l_path)
		end

	test_sqlite_size_cap_deletes_oldest
		local
			l_path: STRING_32
			l_store: TM_SQLITE_TRACE_STORE
			i: INTEGER
		do
			l_path := fresh_trace ("taskman_trace_cap.db")
			create l_store.make_writer (l_path, create {TM_RETENTION_POLICY}.make (100_000, 100_000, 100_000, 64 * 1024, 0.01, 102_400.0, 256 * Mib, 40))
			from i := 0 until i = 300 loop
				l_store.append (merger.reduced (frame_with (T0 + i * One_second, 1,
					<<activity (1, 0.5, 300, 4096.0), activity (2, 0.25, 600, 0.0), activity (3, 1.5, 10, 0.0)>>, 25.0)))
				i := i + 1
			end
			l_store.flush
			assert_true ("over the cap before: " + l_store.size_bytes.out, l_store.size_bytes > 64 * 1024)
			l_store.apply_retention
			assert_true ("under the cap after: " + l_store.size_bytes.out, l_store.size_bytes <= 64 * 1024)
			assert_true ("oldest went first", l_store.earliest_ticks > T0)
			assert_true ("newest kept", l_store.latest_ticks = T0 + 300 * One_second)
			l_store.close
			delete_trace (l_path)
		end

	test_sqlite_schema_refuses_a_fake_zero
		local
			l_path: STRING_32
			l_store: TM_SQLITE_TRACE_STORE
			l_db: SIMPLE_SQL_DATABASE
		do
			l_path := fresh_trace ("taskman_trace_check.db")
			create l_store.make_writer (l_path, small_policy)
			l_store.close
			create l_db.make (l_path)
			l_db.perform ("INSERT INTO frames (start_ticks, end_ticks, duration_ticks, tier, discontinuity, process_count, omitted_processes, cpu_busy_pct, cpu_busy_status, mem_commit_status, disk_busy_status, package_watts_status, lag_status, payload) VALUES (1, 2, 1, 0, 0, 0, 0, NULL, 0, 1, 1, 1, 1, 'x')")
			assert_true ("CHECK refused available-without-value", l_db.has_error)
			l_db.close
			delete_trace (l_path)
		end

	test_sqlite_reader_of_missing_file_says_why
		local
			l_store: TM_SQLITE_TRACE_STORE
		do
			create l_store.make_reader (scratch_path ({STRING_32} "taskman_no_such_trace.db"))
			assert_false ("not open", l_store.is_open)
			assert_string_not_empty ("reason", l_store.last_error)
		end

feature -- Tests: recording through the facade

	test_facade_records_each_new_frame
		note
			testing: "covers/{SIMPLE_TASKMAN}.attach_store"
		local
			l_tm: SIMPLE_TASKMAN
			l_store: TM_MEMORY_TRACE_STORE
			l_clock: TM_MANUAL_CLOCK
			i: INTEGER
		do
			create l_store.make (small_policy)
			create l_clock.make (T0 + 3_600 * One_second, 0)
			l_tm := busy_facade (6, l_clock)
			l_tm.attach_store (l_store).do_nothing
			from i := 1 until i > 6 loop
				l_tm.sample
				l_clock.advance (One_second)
				i := i + 1
			end
			assert_integers_equal ("five frames from six samples", 5, l_store.frame_count)
			assert_integers_equal ("counted", 5, l_tm.recorded)
			if attached l_store.frame_nearest (l_store.latest_ticks - 1) as al_frame then
				assert_true ("busy process recorded", al_frame.has_activity (id (100, T0)))
			else
				assert_true ("readable", False)
			end
			l_tm.close
			assert_false ("store closed with the facade", l_store.is_open)
		end

	test_facade_skips_frames_out_of_order
		note
			testing: "covers/{SIMPLE_TASKMAN}.attach_store"
		local
			l_tm: SIMPLE_TASKMAN
			l_store: TM_MEMORY_TRACE_STORE
			l_clock: TM_MANUAL_CLOCK
		do
			create l_store.make (small_policy)
			l_store.append (merger.reduced (frame_with_cpu (T0 + 3_600 * One_second, 1, 5.0)))
			create l_clock.make (T0 + 3_600 * One_second, 0)
			l_tm := busy_facade (3, l_clock)
			l_tm.attach_store (l_store).do_nothing
			l_tm.sample
			l_clock.advance (One_second)
			l_tm.sample
			assert_integers_equal ("not recorded", 1, l_store.frame_count)
			assert_integers_equal ("counted as skipped", 1, l_tm.skipped_out_of_order)
			l_tm.close
		end

feature -- Tests: single writer

	test_single_writer_second_is_refused
		local
			l_first, l_second: TM_SINGLE_WRITER
		do
			create l_first.make ({STRING_32} "simple_taskman.test_writer")
			create l_second.make ({STRING_32} "simple_taskman.test_writer")
			assert_true ("first owns", l_first.is_owner)
			assert_false ("second refused", l_second.is_owner)
			assert_integers_equal ("already exists", 183, l_second.last_error_code)
			l_first.release
			l_second.release
		end

	test_single_writer_release_lets_the_next_in
		local
			l_first, l_next: TM_SINGLE_WRITER
		do
			create l_first.make ({STRING_32} "simple_taskman.test_writer_2")
			l_first.release
			create l_next.make ({STRING_32} "simple_taskman.test_writer_2")
			assert_true ("next owns", l_next.is_owner)
			l_next.release
		end

feature {NONE} -- Fixtures

	Mib: INTEGER_64 = 1_048_576

	T0: INTEGER_64 = 133_699_999_800_000_000
			-- 13,369,999,980 s: a whole number of minutes, near Base_utc.

	small_policy: TM_RETENTION_POLICY
			-- Default thresholds; short ages so tests stay small.
		do
			create Result.make (60, 600, 3_600, 250 * Mib, 0.01, 102_400.0, 256 * Mib, 40)
		end

	merger: TM_FRAME_MERGER
		do
			create Result.make (create {TM_RETENTION_POLICY}.make_default)
		end

	planner: TM_RETENTION_PLANNER
		do
			create Result.make (create {TM_RETENTION_POLICY}.make_default)
		end

	activity (a_pid: INTEGER_64; a_cores: REAL_64; a_private_mb: INTEGER_64; a_io_bps: REAL_64): TM_PROCESS_ACTIVITY
			-- Measured activity of process `a_pid' (created at 1000 + `a_pid').
		do
			create Result.make_decoded (id (a_pid, 1000 + a_pid), {STRING_32} "p" + a_pid.out.to_string_32, 4, 1, 8, 100, False, 4,
				{TM_READING_STATUS}.Available, a_cores,
				{TM_READING_STATUS}.Available, a_private_mb * Mib, a_private_mb * Mib,
				{TM_READING_STATUS}.Available, a_io_bps, 0.0)
		end

	named_activity (a_pid: INTEGER_64; a_name: STRING_32): TM_PROCESS_ACTIVITY
			-- Busy activity of process `a_pid' called `a_name'.
		do
			create Result.make_decoded (id (a_pid, 1000 + a_pid), a_name, 4, 1, 8, 100, False, 4,
				{TM_READING_STATUS}.Available, 0.5,
				{TM_READING_STATUS}.Available, Mib, Mib,
				{TM_READING_STATUS}.Available, 0.0, 0.0)
		end

	newborn (a_pid: INTEGER_64): TM_PROCESS_ACTIVITY
			-- A process born this interval: memory only, no rates.
		do
			create Result.make_decoded (id (a_pid, 1000 + a_pid), {STRING_32} "new", 4, 1, 1, 10, True, 4,
				{TM_READING_STATUS}.Unavailable, 0.0,
				{TM_READING_STATUS}.Available, Mib, Mib,
				{TM_READING_STATUS}.Unavailable, 0.0, 0.0)
		end

	frame_with (a_start: INTEGER_64; a_seconds: INTEGER; a_activities: ARRAY [TM_PROCESS_ACTIVITY]; a_busy: REAL_64): TM_FRAME
		local
			l_list: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
		do
			create l_list.make_from_array (a_activities)
			Result := frame_from_list (a_start, a_seconds, l_list, a_busy)
		end

	frame_from_list (a_start: INTEGER_64; a_seconds: INTEGER; a_activities: ARRAYED_LIST [TM_PROCESS_ACTIVITY]; a_busy: REAL_64): TM_FRAME
			-- Live frame with these activities and cpu.busy_pct `a_busy'.
		local
			l_readings: TM_READINGS
		do
			create l_readings.make
			l_readings.put ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "", measured ({TM_METRICS}.Cpu_busy_pct, a_busy))
			create Result.make (a_start, a_start + a_seconds * One_second, a_seconds * One_second, 4, False,
				l_readings, a_activities,
				create {ARRAYED_LIST [TM_PROCESS_ID]}.make (0),
				create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0))
		end

	frame_with_reading (a_start: INTEGER_64; a_seconds, a_code: INTEGER; a_reading: TM_READING): TM_FRAME
			-- Live frame holding one system reading.
		local
			l_readings: TM_READINGS
		do
			create l_readings.make
			l_readings.put (a_code, {STRING_32} "", a_reading)
			create Result.make (a_start, a_start + a_seconds * One_second, a_seconds * One_second, 4, False,
				l_readings,
				create {ARRAYED_LIST [TM_PROCESS_ACTIVITY]}.make (0),
				create {ARRAYED_LIST [TM_PROCESS_ID]}.make (0),
				create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0))
		end

	adjusted_frame (a_start: INTEGER_64; a_seconds: INTEGER): TM_FRAME
			-- Live frame during which the wall clock was changed.
		do
			create Result.make (a_start, a_start + a_seconds * One_second, a_seconds * One_second, 4, True,
				create {TM_READINGS}.make,
				create {ARRAYED_LIST [TM_PROCESS_ACTIVITY]}.make (0),
				create {ARRAYED_LIST [TM_PROCESS_ID]}.make (0),
				create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0))
		end

	seconds_entries (a_count: INTEGER): ARRAYED_LIST [TM_TRACE_ENTRY]
			-- `a_count' consecutive one-second tier 0 entries from T0.
		local
			i: INTEGER
		do
			create Result.make (a_count)
			from i := 1 until i > a_count loop
				Result.extend (create {TM_TRACE_ENTRY}.make (i, T0 + (i - 1) * One_second, T0 + i * One_second, 0, False, False))
				i := i + 1
			end
		end

	busy_facade (a_rounds: INTEGER; a_clock: TM_MANUAL_CLOCK): SIMPLE_TASKMAN
			-- Scripted facade: process 100 busy on one core for `a_rounds' samples.
		local
			l_processes: TM_SCRIPTED_PROCESS_SOURCE
			i: INTEGER
		do
			create l_processes.make
			from i := 0 until i = a_rounds loop
				l_processes.add_round (<<sample (100, T0, {STRING_32} "busy.exe", i * One_second, 1, 0)>>)
				i := i + 1
			end
			create Result.make_with_sources (l_processes, create {TM_SCRIPTED_SYSTEM_SOURCE}.make (4), a_clock)
			Result.set_nominal_interval (1000).do_nothing
		end

	fill (a_store: TM_TRACE_STORE; a_count: INTEGER)
			-- Append `a_count' one-second frames from T0.
		require
			writable: a_store.is_writable
			empty: a_store.is_empty
		do
			fill_from (a_store, T0, a_count)
		end

	fill_from (a_store: TM_TRACE_STORE; a_start: INTEGER_64; a_count: INTEGER)
			-- Append `a_count' one-second frames from `a_start'.
		require
			writable: a_store.is_writable
		local
			i: INTEGER
		do
			from i := 0 until i = a_count loop
				a_store.append (merger.reduced (frame_with_cpu (a_start + i * One_second, 1, (i \\ 100).to_double)))
				i := i + 1
			end
		end

	fresh_trace (a_name: STRING_32): STRING_32
			-- Scratch path for a trace file, with any earlier copy removed.
		do
			Result := scratch_path (a_name)
			delete_trace (Result)
		end

	delete_trace (a_path: STRING_32)
			-- Remove the trace and its WAL side files.
		do
			delete_file (a_path)
			delete_file (a_path + {STRING_32} "-wal")
			delete_file (a_path + {STRING_32} "-shm")
		end

end
