note
	description: "[
		Phase 6 stress: the sizes R-4 promises (5,000 processes, 1,024
		logical processors), an hour of frames, a long sampler run with churn
		and clock chaos, and a long series. Built with contracts kept, so the
		times printed are the contract-on cost; each test also asserts a
		generous bound that a cubic regression would blow through.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_HARDEN_SCALE

inherit
	TM_TEST_SET

feature -- Tests

	test_five_thousand_processes
			-- R-4: a 5,000-process machine. Build, rank, encode, decode.
		note
			testing: "covers/{TM_FRAME_BUILDER}.build"
		local
			l_before, l_after: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			l_frame: TM_FRAME
			l_codec: TM_FRAME_CODEC
			l_text: STRING_8
			i: INTEGER
			t0, t_build, t_top, t_encode, t_decode: INTEGER_64
		do
			create l_before.make (5_050)
			create l_after.make (5_050)
			from i := 1 until i > 5_050 loop
				if i <= 5_000 then
					l_before.extend (sample (i, Base_utc, {STRING_32} "p" + i.out.to_string_32 + {STRING_32} ".exe", 0, i, 0))
				end
				if i > 50 then
					l_after.extend (sample (i, Base_utc, {STRING_32} "p" + i.out.to_string_32 + {STRING_32} ".exe",
						(i \\ 97) * 10_000, i, i * 10))
				end
				i := i + 1
			end
			t0 := now
			l_frame := (create {TM_FRAME_BUILDER}).build (
				create {TM_SNAPSHOT}.make (Base_utc, 0, l_before, sealed_readings),
				create {TM_SNAPSHOT}.make (Base_utc + One_second, One_second, l_after, sealed_readings),
				Base_utc, Base_utc + One_second, False, 64, Void, 0)
			t_build := now - t0
			t0 := now
			assert_integers_equal ("top 20", 20, l_frame.top_by ({TM_RESOURCE}.Cpu, 20).count)
			t_top := now - t0
			create l_codec.make
			t0 := now
			l_text := l_codec.encode (l_frame)
			t_encode := now - t0
			t0 := now
			l_codec.decode (l_text)
			t_decode := now - t0
			assert_integers_equal ("activities", 5_000, l_frame.activity_count)
			assert_integers_equal ("born", 50, l_frame.born.count)
			assert_integers_equal ("exited", 50, l_frame.exited.count)
			assert_true ("decoded", l_codec.has_frame and then l_codec.last_frame.activity_count = 5_000)
			bench ("5,000 processes: build " + ms (t_build) + ", top_by " + ms (t_top) + ", encode " + ms (t_encode)
				+ ", decode " + ms (t_decode) + ", text " + (l_text.count // 1024).out + " KB")
			assert_true ("well under 10 s with contracts on", t_build + t_top + t_encode + t_decode < 10 * One_second)
		end

	test_thousand_cores
			-- R-4: 1,024 logical processors, one reading each, through a frame and the codec.
		note
			testing: "covers/{TM_READINGS}.put"
		local
			l_readings: TM_READINGS
			l_frame: TM_FRAME
			l_codec: TM_FRAME_CODEC
			i: INTEGER
			t0, t_put, t_frame, t_codec: INTEGER_64
		do
			create l_readings.make
			t0 := now
			from i := 0 until i = 1_024 loop
				l_readings.put ({TM_METRICS}.Cpu_core_busy_pct, i.out.to_string_32,
					measured ({TM_METRICS}.Cpu_core_busy_pct, (i \\ 101).to_double))
				i := i + 1
			end
			l_readings.seal
			t_put := now - t0
			t0 := now
			l_frame := (create {TM_FRAME_BUILDER}).build (
				create {TM_SNAPSHOT}.make (Base_utc, 0, no_samples, l_readings),
				create {TM_SNAPSHOT}.make (Base_utc + One_second, One_second, no_samples, l_readings),
				Base_utc, Base_utc + One_second, False, 1_024, Void, 0)
			t_frame := now - t0
			create l_codec.make
			t0 := now
			l_codec.decode (l_codec.encode (l_frame))
			t_codec := now - t0
			assert_integers_equal ("1,024 cores", 1_024, l_codec.last_frame.readings.instances ({TM_METRICS}.Cpu_core_busy_pct).count)
			bench ("1,024 cores: put+seal " + ms (t_put) + ", build " + ms (t_frame) + ", encode+decode " + ms (t_codec))
			assert_true ("well under 10 s with contracts on", t_put + t_frame + t_codec < 10 * One_second)
		end

	test_an_hour_of_frames
			-- 3,600 one-second frames of 20 processes: window, aggregate, ranking.
		note
			testing: "covers/{TM_WINDOW}.extend"
		local
			l_window: TM_WINDOW
			l_previous, l_current: TM_SNAPSHOT
			i: INTEGER
			t0, t_extend, t_query: INTEGER_64
			l_mean: TM_AGGREGATE
		do
			create l_window.make
			l_previous := churn_snapshot (0)
			t0 := now
			from i := 1 until i > 3_600 loop
				l_current := churn_snapshot (i)
				l_window.extend (built (l_previous, l_current, False))
				l_previous := l_current
				i := i + 1
			end
			t_extend := now - t0
			t0 := now
			l_mean := l_window.aggregate ({TM_METRICS}.Self_cpu_pct, {STRING_32} "")
			assert_integers_equal ("ten ranked", 10, l_window.ranked ({TM_RESOURCE}.Cpu, 10).count)
			t_query := now - t0
			assert_integers_equal ("3,600 frames", 3_600, l_window.count)
			assert_reals_equal ("an hour measured", 3_600.0, l_window.measured_seconds, 0.000_001)
			assert_false ("no self row, so self CPU never measured", l_mean.reading.is_available)
			bench ("hour window: build+extend 3,600 frames " + ms (t_extend) + ", aggregate+rank " + ms (t_query))
			assert_true ("well under 60 s with contracts on", t_extend + t_query < 60 * One_second)
		end

	test_long_run_with_churn_and_clock_chaos
			-- 2,000 ticks: processes born and exiting every tick; the wall clock thrown
			-- back or forward every 97 ticks. Frames stay continuous, ordered, and
			-- every window extend is accepted.
		note
			testing: "covers/{TM_SAMPLER}.sample"
		local
			l_processes: TM_SCRIPTED_PROCESS_SOURCE
			l_clock: TM_MANUAL_CLOCK
			l_sampler: TM_SAMPLER
			l_window: TM_WINDOW
			l_last_end: INTEGER_64
			i, l_adjusted: INTEGER
		do
			create l_processes.make
			from i := 0 until i > 2_000 loop
				l_processes.add_round (churn_snapshot (i).samples)
				i := i + 1
			end
			create l_clock.make (Base_utc, 0)
			create l_sampler.make (l_processes, create {TM_SCRIPTED_SYSTEM_SOURCE}.make (4), l_clock)
			create l_window.make
			l_sampler.sample
			from i := 1 until i > 2_000 loop
				if i \\ 97 = 0 then
					if i \\ 2 = 0 then
						l_clock.set_utc (l_clock.utc_ticks - (i \\ 13 + 1) * 600 * One_second)
					else
						l_clock.set_utc (l_clock.utc_ticks + (i \\ 7 + 1) * 900 * One_second)
					end
				end
				l_clock.advance (One_second)
				l_sampler.sample
				if l_last_end > 0 then
					assert_true ("continuous at tick " + i.out, l_sampler.last_frame.start_ticks = l_last_end)
				end
				l_last_end := l_sampler.last_frame.end_ticks
				if l_sampler.last_frame.is_clock_adjusted then
					l_adjusted := l_adjusted + 1
				end
				l_window.extend (l_sampler.last_frame)
				i := i + 1
			end
			assert_integers_equal ("frames", 2_000, l_sampler.frames_made)
			assert_integers_equal ("no gaps", 0, l_sampler.discontinuities)
			assert_integers_equal ("every change flagged", 2_000 // 97, l_adjusted)
			assert_integers_equal ("window took all", 2_000, l_window.count)
			assert_true ("offset never negative", l_sampler.utc_offset >= 0)
			bench ("2,000 ticks with churn: " + l_adjusted.out + " clock changes absorbed, final offset "
				+ (l_sampler.utc_offset // One_second).out + " s")
		end

	test_hundred_thousand_series_writes
		note
			testing: "covers/{TM_SERIES}.extend"
		local
			l_series: TM_SERIES
			i: INTEGER
			t0: INTEGER_64
		do
			create l_series.make (60)
			t0 := now
			from i := 1 until i > 100_000 loop
				l_series.extend (Base_utc + i, measured ({TM_METRICS}.Cpu_busy_pct, (i \\ 100).to_double))
				i := i + 1
			end
			bench ("100,000 series writes: " + ms (now - t0))
			assert_integers_equal ("bounded", 60, l_series.count)
			assert_reals_equal ("newest", (100_000 \\ 100).to_double, l_series.value_at (60), 0.0)
			assert_true ("oldest kept in order", l_series.ticks_at (1) = Base_utc + 100_000 - 59)
		end

feature {NONE} -- Fixtures

	churn_snapshot (a_tick: INTEGER): TM_SNAPSHOT
			-- 20 processes at tick `a_tick': pids a_tick .. a_tick + 19, so one is born
			-- and one exits every tick; CPU grows with the tick.
		local
			l_samples: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			p: INTEGER
		do
			create l_samples.make (20)
			from p := a_tick until p = a_tick + 20 loop
				l_samples.extend (sample (p + 1, Base_utc + p, {STRING_32} "churn.exe", (a_tick - p + 20) * 1_000_000, 4096, 0))
				p := p + 1
			end
			create Result.make (Base_utc + a_tick * One_second, a_tick * One_second, l_samples, sealed_readings)
		end

	now: INTEGER_64
			-- Monotonic ticks.
		do
			Result := (create {TM_SYSTEM_CLOCK}.make).monotonic_ticks
		end

	ms (a_ticks: INTEGER_64): STRING_8
			-- "123 ms".
		do
			Result := (a_ticks // 10_000).out + " ms"
		end

	bench (a_line: STRING_8)
			-- Print a measurement line into the test log.
		do
			io.put_string ("    bench: " + a_line + "%N")
			io.output.flush
		end

end
