note
	description: "Tests for TM_SAMPLER on scripted sources and a manual clock: frames from the second sample, gaps become discontinuities."
	author: "Larry Rix"
	testing: "covers"

class
	TEST_SAMPLER

inherit
	TM_TEST_SET

feature -- Tests

	test_first_sample_makes_no_frame
		note
			testing: "covers/{TM_SAMPLER}.sample"
		local
			l_sampler: TM_SAMPLER
		do
			l_sampler := scripted_sampler (2)
			l_sampler.sample
			assert_true ("snapshot", l_sampler.has_snapshot)
			assert_false ("no frame yet", l_sampler.has_frame)
		end

	test_second_sample_makes_a_frame
		note
			testing: "covers/{TM_SAMPLER}.sample"
		local
			l_sampler: TM_SAMPLER
		do
			l_sampler := scripted_sampler (2)
			l_sampler.sample
			clock.advance (One_second)
			l_sampler.sample
			assert_true ("frame", l_sampler.has_frame)
			assert_integers_equal ("frames made", 1, l_sampler.frames_made)
			assert_false ("live", l_sampler.last_frame.is_discontinuity)
		end

	test_gap_makes_a_discontinuity
			-- A-110: a laptop slept for a minute; no rate is formed across the gap.
		note
			testing: "covers/{TM_SAMPLER}.sample"
		local
			l_sampler: TM_SAMPLER
		do
			l_sampler := scripted_sampler (2)
			l_sampler.sample
			clock.advance (60 * One_second)
			l_sampler.sample
			assert_true ("discontinuity", l_sampler.last_frame.is_discontinuity)
			assert_integers_equal ("counted", 1, l_sampler.discontinuities)
		end

	test_failed_process_read_keeps_going
		note
			testing: "covers/{TM_SAMPLER}.sample"
		local
			l_processes: TM_SCRIPTED_PROCESS_SOURCE
			l_sampler: TM_SAMPLER
		do
			create l_processes.make
			l_processes.add_round (<<sample (100, Base_utc, {STRING_32} "a.exe", 0, 1, 0)>>)
			l_processes.add_failure ({STRING_32} "NtQuerySystemInformation returned 0xC0000017")
			create clock.make (Base_utc, 0)
			create l_sampler.make (l_processes, create {TM_SCRIPTED_SYSTEM_SOURCE}.make (4), clock)
			l_sampler.sample
			clock.advance (One_second)
			l_sampler.sample
			assert_true ("still a frame", l_sampler.has_frame)
			assert_integers_equal ("no activities from a failed read", 0, l_sampler.last_frame.activity_count)
		end

	test_interval_outside_bounds_refused
		note
			testing: "covers/{TM_SAMPLER}.set_nominal_interval"
		local
			l_sampler: TM_SAMPLER
		do
			l_sampler := scripted_sampler (1)
			assert_true ("100 ms refused", raises (agent l_sampler.set_nominal_interval (1_000_000)))
			assert_true ("2 min refused", raises (agent l_sampler.set_nominal_interval (1_200_000_000)))
		end

	test_cost_is_measured_on_the_clock
		note
			testing: "covers/{TM_SAMPLER}.last_tick_cost"
		local
			l_sampler: TM_SAMPLER
		do
			l_sampler := scripted_sampler (1)
			l_sampler.sample
			assert_true ("non-negative", l_sampler.last_tick_cost >= 0)
		end

feature -- Tests: timeline (review issue 2)

	test_clock_change_rule
		note
			testing: "covers/{TM_SAMPLER}.clock_change"
		local
			l_sampler: TM_SAMPLER
			l_start: TM_SNAPSHOT
		do
			l_sampler := scripted_sampler (1)
			l_start := snapshot (Base_utc, 0, no_samples)
			assert_true ("in step", l_sampler.clock_change (l_start, snapshot (Base_utc + One_second, One_second, no_samples)) = 0)
			assert_true ("half a second of drift is not a change",
				l_sampler.clock_change (l_start, snapshot (Base_utc + 15_000_000, One_second, no_samples)) = 0)
			assert_true ("set back an hour",
				l_sampler.clock_change (l_start, snapshot (Base_utc - 3_600 * One_second, One_second, no_samples)) = -3_601 * One_second)
			assert_true ("set forward an hour",
				l_sampler.clock_change (l_start, snapshot (Base_utc + 3_600 * One_second, One_second, no_samples)) = 3_599 * One_second)
			assert_true ("a wall clock standing still is a change",
				l_sampler.clock_change (l_start, snapshot (Base_utc, One_second, no_samples)) /= 0)
		end

	test_clock_set_back_keeps_frames_ordered
			-- The defect review issue 2 found: after the wall clock is set back,
			-- the next frame must still follow the last one, so a window accepts both.
		note
			testing: "covers/{TM_SAMPLER}.sample"
		local
			l_sampler: TM_SAMPLER
			l_window: TM_WINDOW
			l_first_end: INTEGER_64
		do
			l_sampler := scripted_sampler (3)
			create l_window.make
			l_sampler.sample
			clock.advance (One_second)
			l_sampler.sample
			l_first_end := l_sampler.last_frame.end_ticks
			l_window.extend (l_sampler.last_frame)
			clock.set_utc (clock.utc_ticks - 3_600 * One_second)
			clock.advance (One_second)
			l_sampler.sample
			assert_true ("flagged", l_sampler.last_frame.is_clock_adjusted)
			assert_true ("continuous", l_sampler.last_frame.start_ticks = l_first_end)
			assert_true ("offset absorbs the change", l_sampler.utc_offset = 3_600 * One_second)
			l_window.extend (l_sampler.last_frame)
			assert_integers_equal ("window took both", 2, l_window.count)
		end

	test_clock_set_forward_returns_to_wall_time
		note
			testing: "covers/{TM_SAMPLER}.sample"
		local
			l_sampler: TM_SAMPLER
		do
			l_sampler := scripted_sampler (4)
			l_sampler.sample
			clock.advance (One_second)
			l_sampler.sample
			clock.set_utc (clock.utc_ticks - 600 * One_second)
			clock.advance (One_second)
			l_sampler.sample
			clock.set_utc (clock.utc_ticks + 3_600 * One_second)
			clock.advance (One_second)
			l_sampler.sample
			assert_true ("flagged", l_sampler.last_frame.is_clock_adjusted)
			assert_true ("offset paid back", l_sampler.utc_offset = 0)
			assert_true ("labels on wall time", l_sampler.last_frame.end_ticks = clock.utc_ticks)
		end

feature {NONE} -- Fixtures

	clock: TM_MANUAL_CLOCK
			-- The clock of the last scripted sampler.
		attribute
			create Result.make (Base_utc, 0)
		end

	scripted_sampler (a_rounds: INTEGER): TM_SAMPLER
			-- Sampler over `a_rounds' identical scripted rounds of one process.
		local
			l_processes: TM_SCRIPTED_PROCESS_SOURCE
			i: INTEGER
		do
			create l_processes.make
			from
				i := 1
			until
				i > a_rounds
			loop
				l_processes.add_round (<<sample (100, Base_utc, {STRING_32} "a.exe", i * One_second, 1, 0)>>)
				i := i + 1
			end
			create clock.make (Base_utc, 0)
			create Result.make (l_processes, create {TM_SCRIPTED_SYSTEM_SOURCE}.make (4), clock)
		end

end
