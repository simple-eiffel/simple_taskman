note
	description: "Tests for TM_FRAME and TM_FRAME_BUILDER: frames are sealed, discontinuities are honest, rates never cross identities."
	author: "Larry Rix"
	testing: "covers"

class
	TEST_FRAME

inherit
	TM_TEST_SET

feature -- Tests: TM_FRAME

	test_make_seals_readings
		note
			testing: "covers/{TM_FRAME}.make"
		local
			l_frame: TM_FRAME
		do
			l_frame := empty_frame (Base_utc, 1)
			assert_true ("sealed", l_frame.readings.is_sealed)
			assert_true ("complete", l_frame.is_complete)
			assert_false ("live", l_frame.is_discontinuity)
		end

	test_activities_is_a_fresh_list
			-- FR-057: a view sorting its list cannot disturb the frame.
		note
			testing: "covers/{TM_FRAME}.activities"
		local
			l_frame: TM_FRAME
		do
			l_frame := empty_frame (Base_utc, 1)
			assert_not_same_reference ("fresh", l_frame.activities, l_frame.activities)
		end

	test_discontinuity_reads_unavailable_not_unsupported
		note
			testing: "covers/{TM_FRAME}.make_discontinuity"
		local
			l_frame: TM_FRAME
		do
			create l_frame.make_discontinuity (Base_utc, Base_utc + 60 * One_second, 60 * One_second, 4, False,
				<<{TM_METRICS}.Cpu_busy_pct, {TM_METRICS}.Mem_commit_pct>>)
			assert_true ("flagged", l_frame.is_discontinuity)
			assert_integers_equal ("no activities", 0, l_frame.activity_count)
			assert_true ("cpu unavailable", l_frame.readings.reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "").is_unavailable)
			assert_true ("unsupported stays unsupported", l_frame.readings.reading ({TM_METRICS}.Temperature_c, {STRING_32} "z").is_not_supported)
		end

	test_decoded_frame_is_incomplete
		note
			testing: "covers/{TM_FRAME}.make_decoded"
		local
			l_frame: TM_FRAME
		do
			create l_frame.make_decoded (Base_utc, Base_utc + One_second, One_second, 4, False, False, 312,
				create {TM_READINGS}.make,
				create {ARRAYED_LIST [TM_PROCESS_ACTIVITY]}.make (0),
				create {ARRAYED_LIST [TM_PROCESS_ID]}.make (0),
				create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0))
			assert_false ("incomplete", l_frame.is_complete)
			assert_integers_equal ("omitted kept", 312, l_frame.omitted_processes)
		end

	test_backward_frame_refused
			-- DR-005: end must follow start.
		note
			testing: "covers/{TM_FRAME}.make"
		do
			assert_true ("precondition fires", raises (agent empty_frame (Base_utc, 0)))
		end

	test_top_by_cpu_is_descending_and_measured
		note
			testing: "covers/{TM_FRAME}.top_by"
		local
			l_frame: TM_FRAME
			l_top: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
		do
			l_frame := frame_of_three
			l_top := l_frame.top_by ({TM_RESOURCE}.Cpu, 2)
			assert_integers_equal ("two", 2, l_top.count)
			assert_strings_equal_case_insensitive ("busiest first", "busy.exe", l_top [1].name)
		end

feature -- Tests: TM_FRAME_BUILDER

	test_survivor_gets_a_rate
		note
			testing: "covers/{TM_FRAME_BUILDER}.build"
		local
			l_frame: TM_FRAME
		do
			l_frame := build_pair (
				<<sample (100, Base_utc, {STRING_32} "a.exe", 0, 1, 0)>>,
				<<sample (100, Base_utc, {STRING_32} "a.exe", One_second, 1, 0)>>)
			assert_true ("present", l_frame.has_activity (id (100, Base_utc)))
			assert_false ("survivor", l_frame.activity (id (100, Base_utc)).is_new)
			assert_reals_equal ("one core", 1.0, l_frame.activity (id (100, Base_utc)).cpu_cores, 0.000_001)
		end

	test_recycled_pid_is_born_not_rated
			-- FR-003 as a test: same pid, new creation time.
		note
			testing: "covers/{TM_FRAME_BUILDER}.build"
		local
			l_frame: TM_FRAME
		do
			l_frame := build_pair (
				<<sample (100, Base_utc, {STRING_32} "old.exe", 50 * One_second, 1, 0)>>,
				<<sample (100, Base_utc + 7, {STRING_32} "new.exe", One_second, 1, 0)>>)
			assert_true ("new identity is an activity", l_frame.has_activity (id (100, Base_utc + 7)))
			assert_true ("born", l_frame.activity (id (100, Base_utc + 7)).is_new)
			assert_integers_equal ("old one exited", 1, l_frame.exited.count)
		end

	test_idle_is_left_out
		note
			testing: "covers/{TM_FRAME_BUILDER}.build"
		local
			l_frame: TM_FRAME
		do
			l_frame := build_pair (
				<<idle_sample (0), sample (100, Base_utc, {STRING_32} "a.exe", 0, 1, 0)>>,
				<<idle_sample (3 * One_second), sample (100, Base_utc, {STRING_32} "a.exe", 0, 1, 0)>>)
			assert_false ("no idle activity", l_frame.has_activity (id (0, 0)))
			assert_integers_equal ("one activity", 1, l_frame.activity_count)
		end

	test_self_readings_added
		note
			testing: "covers/{TM_FRAME_BUILDER}.build"
		local
			l_frame: TM_FRAME
		do
			l_frame := build_pair (no_samples, no_samples)
			assert_true ("sample cost", l_frame.readings.has ({TM_METRICS}.Sample_cost_ms, {STRING_32} ""))
			assert_true ("self cpu unavailable without a self row",
				l_frame.readings.reading ({TM_METRICS}.Self_cpu_pct, {STRING_32} "").is_unavailable)
		end

feature {NONE} -- Fixtures

	build_pair (a_before, a_after: ARRAY [TM_PROCESS_SAMPLE]): TM_FRAME
			-- Frame over one second between snapshots of `a_before' and `a_after'.
		local
			l_builder: TM_FRAME_BUILDER
		do
			create l_builder
			Result := l_builder.build (snapshot (Base_utc, 0, a_before),
				snapshot (Base_utc + One_second, One_second, a_after),
				Base_utc, Base_utc + One_second, False, 4, Void, 20_000)
		end

	frame_of_three: TM_FRAME
			-- Frame with three survivors using 0.1, 2.0, and 0.5 cores.
		do
			Result := build_pair (
				<<sample (1, Base_utc, {STRING_32} "quiet.exe", 0, 1, 0),
				sample (2, Base_utc, {STRING_32} "busy.exe", 0, 1, 0),
				sample (3, Base_utc, {STRING_32} "mid.exe", 0, 1, 0)>>,
				<<sample (1, Base_utc, {STRING_32} "quiet.exe", One_second // 10, 1, 0),
				sample (2, Base_utc, {STRING_32} "busy.exe", 2 * One_second, 1, 0),
				sample (3, Base_utc, {STRING_32} "mid.exe", One_second // 2, 1, 0)>>)
		end

end
