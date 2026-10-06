note
	description: "Tests for TM_WINDOW and TM_SERIES: aggregates carry coverage; history keeps its gaps."
	author: "Larry Rix"
	testing: "covers"

class
	TEST_WINDOW

inherit
	TM_TEST_SET

feature -- Tests: TM_WINDOW

	test_extend_sets_the_span
		note
			testing: "covers/{TM_WINDOW}.extend"
		local
			l_window: TM_WINDOW
		do
			create l_window.make
			l_window.extend (empty_frame (Base_utc, 1))
			l_window.extend (empty_frame (Base_utc + One_second, 2))
			assert_integers_equal ("two frames", 2, l_window.count)
			assert_true ("start", l_window.start_ticks = Base_utc)
			assert_true ("end", l_window.end_ticks = Base_utc + 3 * One_second)
		end

	test_out_of_order_frame_refused
			-- DR-006.
		note
			testing: "covers/{TM_WINDOW}.extend"
		local
			l_window: TM_WINDOW
		do
			create l_window.make
			l_window.extend (empty_frame (Base_utc + 10 * One_second, 1))
			assert_true ("precondition fires", raises (agent l_window.extend (empty_frame (Base_utc, 1))))
		end

	test_mean_is_weighted_by_duration
			-- 90% for 3 s and 30% for 1 s is 75%, not 60%.
		note
			testing: "covers/{TM_WINDOW}.aggregate"
		local
			l_window: TM_WINDOW
			l_mean: TM_AGGREGATE
		do
			create l_window.make
			l_window.extend (frame_with_cpu (Base_utc, 3, 90.0))
			l_window.extend (frame_with_cpu (Base_utc + 3 * One_second, 1, 30.0))
			l_mean := l_window.aggregate ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "")
			assert_true ("available", l_mean.reading.is_available)
			assert_reals_equal ("weighted", 75.0, l_mean.reading.value, 0.000_001)
			assert_reals_equal ("full coverage", 1.0, l_mean.coverage, 0.000_001)
		end

	test_discontinuity_adds_span_not_coverage
		note
			testing: "covers/{TM_WINDOW}.aggregate"
		local
			l_window: TM_WINDOW
			l_mean: TM_AGGREGATE
		do
			create l_window.make
			l_window.extend (frame_with_cpu (Base_utc, 1, 50.0))
			l_window.extend (create {TM_FRAME}.make_discontinuity (Base_utc + One_second, Base_utc + 4 * One_second,
				3 * One_second, 4, False, <<{TM_METRICS}.Cpu_busy_pct>>))
			l_mean := l_window.aggregate ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "")
			assert_reals_equal ("a quarter measured", 0.25, l_mean.coverage, 0.000_001)
			assert_reals_equal ("measured seconds", 1.0, l_window.measured_seconds, 0.000_001)
		end

	test_unmeasured_metric_has_zero_coverage
		note
			testing: "covers/{TM_WINDOW}.aggregate"
		local
			l_window: TM_WINDOW
			l_mean: TM_AGGREGATE
		do
			create l_window.make
			l_window.extend (frame_with_cpu (Base_utc, 2, 50.0))
			l_mean := l_window.aggregate ({TM_METRICS}.Mem_commit_pct, {STRING_32} "")
			assert_reals_equal ("no coverage", 0.0, l_mean.coverage, 0.0)
			assert_false ("no value", l_mean.reading.is_available)
		end

	test_peak_metric_takes_the_maximum
		note
			testing: "covers/{TM_WINDOW}.aggregate"
		local
			l_window: TM_WINDOW
			l_readings: TM_READINGS
			l_peak: TM_AGGREGATE
		do
			create l_window.make
			across <<120.0, 900.0, 40.0>> as ic loop
				create l_readings.make
				l_readings.put ({TM_METRICS}.Lag_max_ms, {STRING_32} "", measured ({TM_METRICS}.Lag_max_ms, ic))
				l_window.extend (create {TM_FRAME}.make (Base_utc + @ic.cursor_index * One_second,
					Base_utc + (@ic.cursor_index + 1) * One_second, One_second, 4, False, l_readings,
					create {ARRAYED_LIST [TM_PROCESS_ACTIVITY]}.make (0),
					create {ARRAYED_LIST [TM_PROCESS_ID]}.make (0),
					create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0)))
			end
			l_peak := l_window.aggregate ({TM_METRICS}.Lag_max_ms, {STRING_32} "")
			assert_integers_equal ("peak kind", {TM_AGGREGATE}.Peak, l_peak.kind)
			assert_reals_equal ("maximum", 900.0, l_peak.reading.value, 0.0)
		end

	test_extend_frame_condition_in_mml
			-- The MML form of extend's frame condition, kept here because building
			-- models in the contract is cubic at live sizes (review issue 1).
		note
			testing: "covers/{TM_WINDOW}.extend"
		local
			l_window: TM_WINDOW
			l_before: MML_SEQUENCE [TM_FRAME]
			l_frame: TM_FRAME
		do
			create l_window.make
			l_window.extend (empty_frame (Base_utc, 1))
			l_before := l_window.frames_model
			l_frame := empty_frame (Base_utc + One_second, 1)
			l_window.extend (l_frame)
			assert_true ("appended, rest unchanged", l_window.frames_model |=| (l_before & l_frame))
		end

	test_ranked_totals_by_identity
			-- Core-seconds per identity; a recycled pid is a different identity.
		note
			testing: "covers/{TM_WINDOW}.ranked"
		local
			l_window: TM_WINDOW
			s0, s1, s2: TM_SNAPSHOT
			l_ranked: ARRAYED_LIST [TM_PROCESS_TOTAL]
		do
			s0 := snapshot (Base_utc, 0, <<sample (100, Base_utc, {STRING_32} "a.exe", 0, 1, 0),
				sample (200, Base_utc, {STRING_32} "b.exe", 0, 1, 0)>>)
			s1 := snapshot (Base_utc + One_second, One_second, <<sample (100, Base_utc, {STRING_32} "a.exe", One_second, 1, 0),
				sample (200, Base_utc, {STRING_32} "b.exe", One_second // 2, 1, 0)>>)
			s2 := snapshot (Base_utc + 2 * One_second, 2 * One_second, <<sample (100, Base_utc, {STRING_32} "a.exe", 2 * One_second, 1, 0),
				sample (200, Base_utc, {STRING_32} "b.exe", One_second, 1, 0),
				sample (300, Base_utc + 9, {STRING_32} "new.exe", 0, 1, 0)>>)
			create l_window.make
			l_window.extend (built (s0, s1, False))
			l_window.extend (built (s1, s2, False))
			l_ranked := l_window.ranked ({TM_RESOURCE}.Cpu, 5)
			assert_integers_equal ("two with CPU measured", 2, l_ranked.count)
			assert_true ("a.exe first", l_ranked [1].id ~ id (100, Base_utc))
			assert_reals_equal ("two core-seconds", 2.0, l_ranked [1].total, 0.000_001)
			assert_reals_equal ("one core-second", 1.0, l_ranked [2].total, 0.000_001)
			assert_integers_equal ("seen in both frames", 2, l_ranked [1].frames_seen)
		end

feature -- Tests: TM_SERIES

	test_new_series_is_empty
		note
			testing: "covers/{TM_SERIES}.make"
		local
			l_series: TM_SERIES
		do
			create l_series.make (60)
			assert_integers_equal ("empty", 0, l_series.count)
			assert_integers_equal ("capacity", 60, l_series.capacity)
		end

	test_extend_keeps_value_and_gap
		note
			testing: "covers/{TM_SERIES}.extend"
		local
			l_series: TM_SERIES
		do
			create l_series.make (60)
			l_series.extend (Base_utc, measured ({TM_METRICS}.Cpu_busy_pct, 23.0))
			l_series.extend (Base_utc + One_second, create {TM_READING}.make_unavailable)
			assert_integers_equal ("two", 2, l_series.count)
			assert_reals_equal ("value", 23.0, l_series.value_at (1), 0.0)
			assert_false ("gap stays a gap", l_series.is_available_at (2))
		end

	test_full_series_drops_the_oldest
		note
			testing: "covers/{TM_SERIES}.extend"
		local
			l_series: TM_SERIES
		do
			create l_series.make (2)
			l_series.extend (Base_utc, measured ({TM_METRICS}.Cpu_busy_pct, 1.0))
			l_series.extend (Base_utc + 1, measured ({TM_METRICS}.Cpu_busy_pct, 2.0))
			l_series.extend (Base_utc + 2, measured ({TM_METRICS}.Cpu_busy_pct, 3.0))
			assert_integers_equal ("bounded", 2, l_series.count)
			assert_reals_equal ("oldest is now 2", 2.0, l_series.value_at (1), 0.0)
			assert_reals_equal ("newest is 3", 3.0, l_series.value_at (2), 0.0)
		end

end
