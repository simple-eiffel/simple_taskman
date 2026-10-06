note
	description: "[
		Facade tests for SIMPLE_TASKMAN: the live machine and injected
		sources. What a client of the library sees first.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	LIB_TESTS

inherit
	TM_TEST_SET

feature -- Tests: live machine

	test_live_facade_opens_and_says_which_source
		note
			testing: "covers/{SIMPLE_TASKMAN}.make"
		local
			l_tm: SIMPLE_TASKMAN
		do
			create l_tm.make
			assert_false ("nothing sampled", l_tm.has_frame)
			assert_true ("known source", l_tm.process_source_kind.same_string ("native") or l_tm.process_source_kind.same_string ("documented"))
			if l_tm.process_source_kind.same_string ("documented") then
				assert_string_not_empty ("fallback says why", l_tm.fallback_reason)
			end
			assert_true ("knows itself", attached l_tm.self_id as al_self and then al_self.pid > 0)
			l_tm.close
			assert_true ("closed", l_tm.is_closed)
		end

	test_capabilities_cover_every_metric
		note
			testing: "covers/{SIMPLE_TASKMAN}.capabilities"
		local
			l_tm: SIMPLE_TASKMAN
		do
			create l_tm.make
			assert_integers_equal ("every metric", metrics.count, l_tm.capabilities.count)
			assert_strings_equal_case_insensitive ("source recorded", l_tm.process_source_kind, l_tm.capabilities.process_source_kind)
			l_tm.close
		end

	test_live_two_samples_make_a_frame_with_self
		note
			testing: "covers/{SIMPLE_TASKMAN}.sample"
		local
			l_tm: SIMPLE_TASKMAN
			l_clock: TM_SYSTEM_CLOCK
		do
			create l_tm.make
			create l_clock.make
			l_tm.sample
			l_clock.sleep_ms (300)
			l_tm.sample
			assert_true ("frame", l_tm.has_frame)
			assert_true ("own row present", attached l_tm.self_id as al_self and then l_tm.last_frame.has_activity (al_self))
			l_tm.close
		end

feature -- Tests: injected sources

	test_interval_round_trip
		note
			testing: "covers/{SIMPLE_TASKMAN}.set_nominal_interval"
		local
			l_tm: SIMPLE_TASKMAN
		do
			l_tm := scripted_facade
			assert_same_reference ("fluent", l_tm, l_tm.set_nominal_interval (2500))
			assert_integers_equal ("ms", 2500, l_tm.nominal_interval_ms)
			assert_true ("ticks", l_tm.nominal_interval_ticks = 25_000_000)
		end

	test_scripted_facade_makes_frames
		note
			testing: "covers/{SIMPLE_TASKMAN}.sample"
		local
			l_tm: SIMPLE_TASKMAN
		do
			l_tm := scripted_facade
			l_tm.sample
			clock.advance (One_second)
			l_tm.sample
			assert_true ("frame", l_tm.has_frame)
			assert_integers_equal ("one process", 1, l_tm.last_frame.activity_count)
		end

	test_injected_sources_have_no_self
			-- Review issue 5: "no self" is Void, never the idle identity.
		note
			testing: "covers/{SIMPLE_TASKMAN}.make_with_sources"
		local
			l_tm: SIMPLE_TASKMAN
		do
			l_tm := scripted_facade
			assert_void ("no self", l_tm.self_id)
			assert_true ("idle refused as self", raises (agent l_tm.set_self_id (id (0, 0))))
		end

	test_logger_records_decisions
		note
			testing: "covers/{SIMPLE_TASKMAN}.set_logger"
		local
			l_processes: TM_SCRIPTED_PROCESS_SOURCE
			l_tm: SIMPLE_TASKMAN
			l_logger: SIMPLE_LOGGER
			l_path: STRING_32
			l_log: STRING_8
		do
			l_path := scratch_path ({STRING_32} "taskman_logger_test.log")
			delete_file (l_path)
			create l_processes.make
			l_processes.add_round (<<sample (100, Base_utc, {STRING_32} "a.exe", 0, 1, 0)>>)
			l_processes.add_failure ({STRING_32} "scripted read failure")
			l_processes.add_round (<<sample (100, Base_utc, {STRING_32} "a.exe", One_second, 1, 0)>>)
			create clock.make (Base_utc, 0)
			create l_tm.make_with_sources (l_processes, create {TM_SCRIPTED_SYSTEM_SOURCE}.make (4), clock)
			create l_logger.make_to_file (l_path.to_string_8)
			l_tm.set_logger (l_logger).do_nothing
			l_tm.sample
			clock.advance (One_second)
			l_tm.sample
			clock.advance (60 * One_second)
			l_tm.sample
			l_log := file_text (l_path)
			assert_string_contains ("source", l_log, "process source scripted")
			assert_string_contains ("failed read", l_log, "scripted read failure")
			assert_string_contains ("gap", l_log, "discontinuity")
				-- Not deleted here: simple_logger keeps its file handle open (W-7), so
				-- Windows refuses the delete until this process exits.
		end

	test_close_closes_the_sources
		note
			testing: "covers/{SIMPLE_TASKMAN}.close"
		local
			l_tm: SIMPLE_TASKMAN
		do
			l_tm := scripted_facade
			l_tm.close
			assert_true ("closed", l_tm.is_closed)
			assert_true ("sample refused", raises (agent l_tm.sample))
		end

feature {NONE} -- Fixtures

	clock: TM_MANUAL_CLOCK
			-- Clock of the last scripted facade.
		attribute
			create Result.make (Base_utc, 0)
		end

	scripted_facade: SIMPLE_TASKMAN
			-- Facade over two rounds of one scripted process.
		local
			l_processes: TM_SCRIPTED_PROCESS_SOURCE
		do
			create l_processes.make
			l_processes.add_round (<<sample (100, Base_utc, {STRING_32} "a.exe", 0, 1, 0)>>)
			l_processes.add_round (<<sample (100, Base_utc, {STRING_32} "a.exe", One_second, 1, 0)>>)
			create clock.make (Base_utc, 0)
			create Result.make_with_sources (l_processes, create {TM_SCRIPTED_SYSTEM_SOURCE}.make (4), clock)
		end

end
