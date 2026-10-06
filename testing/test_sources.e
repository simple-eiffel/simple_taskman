note
	description: "[
		Tests for the probe: scripted sources, CPU topology, paths, and the live
		Windows sources on this machine. The live tests state what the Phase 1
		acceptance criteria expect on the reference machine (JACKJACK): native
		table trusted, package power available, temperature not supported.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_SOURCES

inherit
	TM_TEST_SET

feature -- Tests: scripted sources

	test_scripted_process_rounds_in_order
		note
			testing: "covers/{TM_SCRIPTED_PROCESS_SOURCE}.read_all"
		local
			l_source: TM_SCRIPTED_PROCESS_SOURCE
		do
			create l_source.make
			l_source.add_round (<<sample (1, Base_utc, {STRING_32} "a.exe", 0, 1, 0)>>)
			l_source.add_failure ({STRING_32} "scripted failure")
			l_source.read_all
			assert_true ("first succeeds", l_source.last_read_succeeded)
			assert_integers_equal ("one sample", 1, l_source.last_samples.count)
			l_source.read_all
			assert_false ("second fails", l_source.last_read_succeeded)
			assert_string_contains ("says why", l_source.last_error, "scripted failure")
			l_source.read_all
			assert_string_contains ("exhausted", l_source.last_error, "exhausted")
		end

	test_scripted_system_reads_as_declared
		note
			testing: "covers/{TM_SCRIPTED_SYSTEM_SOURCE}.refresh"
		local
			l_source: TM_SCRIPTED_SYSTEM_SOURCE
		do
			create l_source.make (4)
			l_source.declare_support ({TM_METRICS}.Cpu_busy_pct, {TM_READING_STATUS}.Available, {STRING_32} "")
			l_source.script_reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "", measured ({TM_METRICS}.Cpu_busy_pct, 12.5))
			l_source.end_round
			l_source.refresh
			assert_reals_equal ("scripted value", 12.5, l_source.last_readings.reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "").value, 0.0)
			assert_true ("undeclared is not supported", l_source.last_readings.reading ({TM_METRICS}.Battery_pct, {STRING_32} "").is_not_supported)
			l_source.refresh
			assert_true ("after the script: unavailable", l_source.last_readings.reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "").is_unavailable)
		end

	test_support_is_fixed_after_first_refresh
		note
			testing: "covers/{TM_SCRIPTED_SYSTEM_SOURCE}.declare_support"
		local
			l_source: TM_SCRIPTED_SYSTEM_SOURCE
		do
			create l_source.make (4)
			l_source.refresh
			assert_true ("declare refused", raises (agent l_source.declare_support ({TM_METRICS}.Cpu_busy_pct, {TM_READING_STATUS}.Available, {STRING_32} "")))
		end

feature -- Tests: TM_CPU_TOPOLOGY

	test_flat_index_across_groups
			-- R-4: 96 processors in two groups of 64 and 32; PDH "1,5" is flat index 69.
		note
			testing: "covers/{TM_CPU_TOPOLOGY}.flat_index"
		local
			l_topology: TM_CPU_TOPOLOGY
		do
			create l_topology.make_from_groups (<<64, 32>>, filled (96, 1))
			assert_integers_equal ("count", 96, l_topology.logical_processor_count)
			assert_integers_equal ("1,5", 69, l_topology.flat_index (1, 5))
			assert_false ("uniform is not hybrid", l_topology.is_hybrid)
		end

	test_hybrid_detected
		note
			testing: "covers/{TM_CPU_TOPOLOGY}.is_hybrid"
		local
			l_topology: TM_CPU_TOPOLOGY
		do
			create l_topology.make_from_groups (<<4>>, <<1, 1, 0, 0>>)
			assert_true ("hybrid", l_topology.is_hybrid)
		end

	test_heatmap_shapes
		note
			testing: "covers/{TM_CPU_TOPOLOGY}.heatmap_rows"
		local
			l_topology: TM_CPU_TOPOLOGY
		do
			create l_topology.make_from_groups (<<32>>, filled (32, 0))
			assert_integers_equal ("32: 4 rows", 4, l_topology.heatmap_rows)
			assert_integers_equal ("32: 8 columns", 8, l_topology.heatmap_columns)
			create l_topology.make_from_groups (<<64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64>>, filled (1024, 0))
			assert_integers_equal ("1024: 32 rows", 32, l_topology.heatmap_rows)
		end

feature -- Tests: TM_PATHS

	test_paths_under_a_base
		note
			testing: "covers/{TM_PATHS}.make_with_base"
		local
			l_paths: TM_PATHS
		do
			create l_paths.make_with_base ({STRING_32} "C:\Users\me\AppData\Local")
			assert_strings_equal_diff ("trace", {STRING_32} "C:\Users\me\AppData\Local\simple_taskman\trace.db", l_paths.trace_path)
			assert_strings_equal_diff ("log", {STRING_32} "C:\Users\me\AppData\Local\simple_taskman\logs\taskman-worker.log",
				l_paths.log_path ({STRING_32} "taskman", {STRING_32} "worker"))
		end

	test_unsafe_log_name_refused
		note
			testing: "covers/{TM_PATHS}.log_path"
		local
			l_paths: TM_PATHS
		do
			create l_paths.make_with_base ({STRING_32} "C:\x")
			assert_true ("path separator refused", raises (agent l_paths.log_path ({STRING_32} "..\evil", {STRING_32} "gui")))
		end

	test_live_root_is_under_localappdata
		note
			testing: "covers/{TM_PATHS}.make"
		local
			l_paths: TM_PATHS
		do
			create l_paths.make
			assert_true ("rooted", l_paths.has_root)
			assert_string_ends_with ("named", l_paths.root, "\simple_taskman")
		end

feature -- Tests: live Windows sources (this machine)

	test_native_self_check_is_decided
		note
			testing: "covers/{TM_NATIVE_PROCESS_SOURCE}.make"
		local
			l_native: TM_NATIVE_PROCESS_SOURCE
		do
			create l_native.make
			assert_true ("decided", l_native.last_self_check.has_run)
			if not l_native.is_trusted then
				assert_string_not_empty ("untrusted says why", l_native.last_self_check.failure)
			end
		end

	test_documented_read_lists_self
		note
			testing: "covers/{TM_DOCUMENTED_PROCESS_SOURCE}.read_all"
		local
			l_source: TM_DOCUMENTED_PROCESS_SOURCE
			l_self: TM_SELF_PROCESS
		do
			create l_source.make
			create l_self.make
			l_source.read_all
			assert_true ({STRING_32} "read: " + l_source.last_error, l_source.last_read_succeeded)
			assert_true ("self listed", l_source.has_sample (l_self.id))
		end

	test_win_processor_count_matches_windows
		note
			testing: "covers/{TM_WIN_SYSTEM_SOURCE}.logical_processors"
		local
			l_system: TM_WIN_SYSTEM_SOURCE
			l_env: SIMPLE_ENV
		do
			create l_system.make
			create l_env
			if attached l_env.item ("NUMBER_OF_PROCESSORS") as al_count and then al_count.is_integer then
				assert_integers_equal ("processors", al_count.to_integer, l_system.logical_processors)
			else
				assert_true ("NUMBER_OF_PROCESSORS is set", False)
			end
			l_system.close
		end

	test_live_topology_counts_all_groups
		note
			testing: "covers/{TM_CPU_TOPOLOGY}.make"
		local
			l_topology: TM_CPU_TOPOLOGY
			l_env: SIMPLE_ENV
		do
			create l_topology.make
			create l_env
			assert_true ("at least one group", l_topology.group_count >= 1)
			if attached l_env.item ("NUMBER_OF_PROCESSORS") as al_count and then al_count.is_integer then
				assert_integers_equal ("processors", al_count.to_integer, l_topology.logical_processor_count)
			else
				assert_true ("NUMBER_OF_PROCESSORS is set", False)
			end
		end

	test_pdh_adds_a_real_counter
		note
			testing: "covers/{TM_COUNTER_QUERY}.add_english"
		local
			l_query: TM_COUNTER_QUERY
		do
			create l_query.make
			assert_integers_equal ("first index", 1, l_query.add_english ("\Processor Information(_Total)\%% Processor Time"))
			assert_integers_equal ("counted", 1, l_query.counter_count)
			l_query.close
		end

	test_pdh_refuses_a_bad_path
		note
			testing: "covers/{TM_COUNTER_QUERY}.add_english"
		local
			l_query: TM_COUNTER_QUERY
		do
			create l_query.make
			assert_integers_equal ("refused", 0, l_query.add_english ("\No Such Object(*)\Nothing"))
			assert_true ("status says why", l_query.last_status /= l_query.Pdh_ok)
			assert_integers_equal ("not counted", 0, l_query.counter_count)
			l_query.close
		end

	test_pdh_two_collections_give_values
		note
			testing: "covers/{TM_COUNTER_QUERY}.values"
		local
			l_query: TM_COUNTER_QUERY
			l_clock: TM_SYSTEM_CLOCK
			l_values: ARRAYED_LIST [TM_COUNTER_VALUE]
		do
			create l_query.make
			create l_clock.make
			l_query.add_english ("\Processor Information(_Total)\%% Processor Time").do_nothing
			l_query.collect
			l_clock.sleep_ms (100)
			l_query.collect
			l_values := l_query.values (1)
			assert_integers_equal ("one instance", 1, l_values.count)
			assert_true ("valid", l_values.first.is_valid)
			assert_real_in_range ("a percent", l_values.first.value, 0.0, 100.0)
			l_query.close
		end

	test_pdh_close_twice_is_safe
		note
			testing: "covers/{TM_COUNTER_QUERY}.close"
		local
			l_query: TM_COUNTER_QUERY
		do
			create l_query.make
			l_query.close
			l_query.close
			assert_true ("closed", l_query.is_closed)
		end

	test_second_refresh_reads_cpu_and_memory
		note
			testing: "covers/{TM_WIN_SYSTEM_SOURCE}.refresh"
		local
			l_system: TM_WIN_SYSTEM_SOURCE
			l_clock: TM_SYSTEM_CLOCK
		do
			create l_system.make
			create l_clock.make
			l_system.refresh
			assert_true ("memory on the first refresh", l_system.last_readings.reading ({TM_METRICS}.Mem_available_bytes, {STRING_32} "").is_available)
			l_clock.sleep_ms (200)
			l_system.refresh
			assert_true ("cpu after two", l_system.last_readings.reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "").is_available)
			assert_integers_equal ("one reading per core", l_system.logical_processors,
				l_system.last_readings.instances ({TM_METRICS}.Cpu_core_busy_pct).count)
			l_system.close
		end

	test_forced_layout_fault_is_refused
			-- The self-check must refuse a layout that reads the wrong field.
		note
			testing: "covers/{TM_NATIVE_PROCESS_SOURCE}.make_with_layout_fault"
		local
			l_native: TM_NATIVE_PROCESS_SOURCE
		do
			create l_native.make_with_layout_fault
			assert_false ("untrusted", l_native.is_trusted)
			assert_string_contains ("names the field", l_native.last_self_check.failure, "create_time")
		end

	test_system_clock_moves_forward
		note
			testing: "covers/{TM_SYSTEM_CLOCK}.monotonic_ticks"
		local
			l_clock: TM_SYSTEM_CLOCK
			l_first, l_second: INTEGER_64
			i: INTEGER
		do
			create l_clock.make
			l_first := l_clock.monotonic_ticks
			from i := 1 until i > 10_000 loop
				l_second := l_clock.monotonic_ticks
				assert_true ("never backward", l_second >= l_first)
				l_first := l_second
				i := i + 1
			end
			l_clock.sleep_ms (20)
			assert_true ("slept", l_clock.monotonic_ticks - l_second >= 150_000)
		end

feature {NONE} -- Fixtures

	filled (a_count, a_value: INTEGER): ARRAY [INTEGER]
			-- `a_count' copies of `a_value'.
		do
			create Result.make_filled (a_value, 1, a_count)
		end

end
