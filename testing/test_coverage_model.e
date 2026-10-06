note
	description: "[
		Phase 5 coverage for the model: features no earlier test called
		directly, and the boundaries of their preconditions.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_COVERAGE_MODEL

inherit
	TM_TEST_SET

feature -- Tests: metric boundaries

	test_metric_accepts_its_exact_bounds
		note
			testing: "covers/{TM_METRIC}.accepts"
		local
			l_busy: TM_METRIC
		do
			l_busy := metric ({TM_METRICS}.Cpu_busy_pct)
			assert_true ("minimum", l_busy.accepts (0.0))
			assert_true ("maximum", l_busy.accepts (100.0))
			assert_false ("just over", l_busy.accepts (100.000_001))
			assert_false ("just under", l_busy.accepts (-0.000_001))
			assert_true ("negative range allowed where the metric has one", metric ({TM_METRICS}.Temperature_c).accepts (-40.0))
		end

	test_registry_lookups
		note
			testing: "covers/{TM_METRICS}.has_code"
		do
			assert_true ("first", metrics.has_code (1))
			assert_true ("last", metrics.has_code ({TM_METRICS}.Last_code))
			assert_false ("zero", metrics.has_code (0))
			assert_false ("past the end", metrics.has_code ({TM_METRICS}.Last_code + 1))
			assert_true ("by name", metrics.has_name ("cpu.package_watts"))
			assert_false ("unknown name", metrics.has_name ("cpu.package_volts"))
			assert_strings_equal_case_insensitive ("unit", "W", metric ({TM_METRICS}.Cpu_package_watts).unit)
			assert_true ("per core is instanced", metric ({TM_METRICS}.Cpu_core_busy_pct).is_instanced)
			assert_false ("label given", metric ({TM_METRICS}.Cpu_busy_pct).label.is_empty)
		end

feature -- Tests: format

	test_value_text_for_every_unit_kind
		note
			testing: "covers/{TM_FORMAT}.value_text"
		local
			l_format: TM_FORMAT
		do
			create l_format
			assert_strings_equal_case_insensitive ("bytes", "2.0 KB", l_format.value_text (2048.0, "B"))
			assert_strings_equal_case_insensitive ("rate", "1.0 MB/s", l_format.value_text (1_048_576.0, "B/s"))
			assert_strings_equal_case_insensitive ("percent", "23.0%%", l_format.value_text (23.0, "%%"))
			assert_strings_equal_case_insensitive ("per second", "200.0/s", l_format.value_text (200.0, "/s"))
			assert_strings_equal_case_insensitive ("milliseconds", "2.5 ms", l_format.value_text (2.5, "ms"))
			assert_strings_equal_case_insensitive ("negative", "-12.3 W", l_format.value_text (-12.34, "W"))
			assert_strings_equal_case_insensitive ("bytes per second", "512 B/s", l_format.bytes_per_second (512.0))
		end

	test_one_decimal_rounds_half_away_from_zero
		note
			testing: "covers/{TM_FORMAT}.one_decimal"
		local
			l_format: TM_FORMAT
		do
			create l_format
			assert_strings_equal_case_insensitive ("zero", "0.0", l_format.one_decimal (0.0))
			assert_strings_equal_case_insensitive ("half up", "0.3", l_format.one_decimal (0.25))
			assert_strings_equal_case_insensitive ("half up, negative", "-0.3", l_format.one_decimal (-0.25))
			assert_strings_equal_case_insensitive ("tiny negative is zero", "0.0", l_format.one_decimal (-0.01))
			assert_strings_equal_case_insensitive ("large", "1234567.9", l_format.one_decimal (1_234_567.89))
		end

	test_terabytes_cap_the_scale
		note
			testing: "covers/{TM_FORMAT}.bytes"
		local
			l_format: TM_FORMAT
		do
			create l_format
			assert_strings_equal_case_insensitive ("one terabyte", "1.0 TB", l_format.bytes (1_099_511_627_776))
			assert_strings_equal_case_insensitive ("beyond stays in TB", "2048.0 TB", l_format.bytes (2_251_799_813_685_248))
		end

feature -- Tests: process sample and activity

	test_sample_groups_and_values
		note
			testing: "covers/{TM_PROCESS_SAMPLE}.deny_memory"
		local
			l_sample: TM_PROCESS_SAMPLE
		do
			create l_sample.make (id (77, Base_utc), {STRING_32} "x.exe", 12, 2, 9)
			l_sample.set_cpu (3, 4)
			l_sample.deny_memory ({TM_READING_STATUS}.Not_supported)
			l_sample.set_io (10, 20)
			assert_true ("kernel kept", l_sample.kernel_ticks = 4)
			assert_true ("writes kept", l_sample.write_bytes = 20)
			assert_integers_equal ("memory denied", {TM_READING_STATUS}.Not_supported, l_sample.memory_status)
			assert_true ("parent, session, threads", l_sample.parent_pid = 12 and l_sample.session = 2 and l_sample.threads = 9)
			assert_true ("handles refused", raises (agent l_sample.handles))
			assert_true ("available is not a reason", raises (agent l_sample.deny_cpu ({TM_READING_STATUS}.Available)))
		end

	test_amount_of_each_resource
		note
			testing: "covers/{TM_PROCESS_ACTIVITY}.amount_of"
		local
			l_before, l_after: TM_PROCESS_SAMPLE
			l_activity: TM_PROCESS_ACTIVITY
		do
			create l_before.make (id (5, Base_utc), {STRING_32} "io.exe", 1, 1, 3)
			l_before.set_cpu (0, 0)
			l_before.set_memory (100, 200, 7)
			l_before.set_io (1_000, 2_000)
			create l_after.make (id (5, Base_utc), {STRING_32} "io.exe", 1, 1, 3)
			l_after.set_cpu (One_second // 2, 0)
			l_after.set_memory (300, 400, 8)
			l_after.set_io (3_000, 6_000)
			create l_activity.make_from_pair (l_before, l_after, 2.0, 4)
			assert_reals_equal ("cpu cores", 0.25, l_activity.amount_of ({TM_RESOURCE}.Cpu), 0.000_001)
			assert_reals_equal ("memory is private bytes now", 400.0, l_activity.amount_of ({TM_RESOURCE}.Memory), 0.0)
			assert_reals_equal ("read", 1_000.0, l_activity.amount_of ({TM_RESOURCE}.Io_read), 0.000_001)
			assert_reals_equal ("write", 2_000.0, l_activity.amount_of ({TM_RESOURCE}.Io_write), 0.000_001)
			assert_reals_equal ("total", 3_000.0, l_activity.amount_of ({TM_RESOURCE}.Io_total), 0.000_001)
			assert_true ("gauges copied", l_activity.working_set = 300 and l_activity.handles = 8)
			assert_true ("identity fields", l_activity.parent_pid = 1 and l_activity.session = 1 and l_activity.threads = 3)
		end

	test_decoded_newcomer_with_a_rate_is_invalid
			-- Review issue 13: a newcomer never carries a rate, even from a file.
		note
			testing: "covers/{TM_PROCESS_ACTIVITY}.make_decoded"
		local
			l_activity: TM_PROCESS_ACTIVITY
		do
			create l_activity.make_decoded (id (5, Base_utc), {STRING_32} "n.exe", 1, 1, 1, 1, True, 4,
				{TM_READING_STATUS}.Available, 0.5, {TM_READING_STATUS}.Available, 10, 20,
				{TM_READING_STATUS}.Available, 1.0, 1.0)
			assert_integers_equal ("cpu invalid", {TM_READING_STATUS}.Invalid, l_activity.cpu_status)
			assert_integers_equal ("io invalid", {TM_READING_STATUS}.Invalid, l_activity.io_status)
			assert_integers_equal ("memory is a gauge, kept", {TM_READING_STATUS}.Available, l_activity.memory_status)
		end

feature -- Tests: frame

	test_self_activity_and_counts
		note
			testing: "covers/{TM_FRAME}.self_activity"
		local
			l_frame: TM_FRAME
		do
			l_frame := built (
				snapshot (Base_utc, 0, <<sample (100, Base_utc, {STRING_32} "a.exe", 0, 1, 0)>>),
				snapshot (Base_utc + One_second, One_second, <<sample (100, Base_utc, {STRING_32} "a.exe", One_second, 1, 0),
					sample (200, Base_utc, {STRING_32} "b.exe", 0, 1, 0)>>), False)
			assert_attached ("present", l_frame.self_activity (id (100, Base_utc)))
			assert_void ("absent", l_frame.self_activity (id (999, Base_utc)))
			assert_integers_equal ("one with CPU measured", 1, l_frame.measured_count ({TM_RESOURCE}.Cpu))
			assert_true ("duration", l_frame.duration = One_second)
			assert_integers_equal ("identities model", 2, l_frame.identities_model.count)
			assert_true ("born model", l_frame.born_model.has (id (200, Base_utc)))
		end

	test_top_by_asks_for_more_than_exist
		note
			testing: "covers/{TM_FRAME}.top_by"
		local
			l_frame: TM_FRAME
		do
			l_frame := built (
				snapshot (Base_utc, 0, <<sample (100, Base_utc, {STRING_32} "a.exe", 0, 1, 0)>>),
				snapshot (Base_utc + One_second, One_second, <<sample (100, Base_utc, {STRING_32} "a.exe", One_second, 1, 0)>>), False)
			assert_integers_equal ("only one", 1, l_frame.top_by ({TM_RESOURCE}.Cpu, 50).count)
			assert_true ("zero refused", raises (agent l_frame.top_by ({TM_RESOURCE}.Cpu, 0)))
			assert_true ("unknown resource refused", raises (agent l_frame.top_by (99, 1)))
		end

feature -- Tests: series

	test_ring_wraps_many_times
		note
			testing: "covers/{TM_SERIES}.status_at"
		local
			l_series: TM_SERIES
			i: INTEGER
		do
			create l_series.make (3)
			from i := 1 until i > 10 loop
				if i \\ 4 = 0 then
					l_series.extend (Base_utc + i, create {TM_READING}.make_unavailable)
				else
					l_series.extend (Base_utc + i, measured ({TM_METRICS}.Cpu_busy_pct, i.to_double))
				end
				i := i + 1
			end
				-- holds entries 8, 9, 10; entry 8 is a gap
			assert_integers_equal ("full", 3, l_series.count)
			assert_true ("oldest tick", l_series.ticks_at (1) = Base_utc + 8)
			assert_true ("newest tick", l_series.last_ticks = Base_utc + 10)
			assert_integers_equal ("gap kept", {TM_READING_STATUS}.Unavailable, l_series.status_at (1))
			assert_reals_equal ("value", 9.0, l_series.value_at (2), 0.0)
			assert_integers_equal ("model", 3, l_series.statuses_model.count)
			assert_integers_equal ("list", 3, l_series.statuses_list.count)
			assert_true ("out of order refused", raises (agent l_series.extend (Base_utc, create {TM_READING}.make_unavailable)))
		end

	test_zero_capacity_refused
		note
			testing: "covers/{TM_SERIES}.make"
		do
			assert_false ("one is the smallest capacity", raises (agent new_series (1)))
			assert_true ("zero refused", raises (agent new_series (0)))
		end

feature -- Tests: window

	test_contains_span_and_empty_window
		note
			testing: "covers/{TM_WINDOW}.contains_span"
		local
			l_window: TM_WINDOW
		do
			create l_window.make
			assert_true ("empty", l_window.is_empty)
			assert_false ("empty contains nothing", l_window.contains_span (Base_utc, Base_utc))
			assert_true ("aggregate needs frames", raises (agent l_window.aggregate ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "")))
			l_window.extend (empty_frame (Base_utc, 10))
			assert_true ("inside", l_window.contains_span (Base_utc + One_second, Base_utc + 2 * One_second))
			assert_true ("whole", l_window.contains_span (Base_utc, Base_utc + 10 * One_second))
			assert_false ("past the end", l_window.contains_span (Base_utc, Base_utc + 11 * One_second))
			assert_false ("reversed", l_window.contains_span (Base_utc + 2, Base_utc + 1))
			assert_reals_equal ("span", 10.0, l_window.span_seconds, 0.0)
		end

	test_aggregate_per_instance
		note
			testing: "covers/{TM_WINDOW}.aggregate"
		local
			l_window: TM_WINDOW
			l_readings: TM_READINGS
		do
			create l_window.make
			create l_readings.make
			l_readings.put ({TM_METRICS}.Cpu_core_busy_pct, {STRING_32} "0", measured ({TM_METRICS}.Cpu_core_busy_pct, 80.0))
			l_readings.put ({TM_METRICS}.Cpu_core_busy_pct, {STRING_32} "1", measured ({TM_METRICS}.Cpu_core_busy_pct, 20.0))
			l_window.extend (create {TM_FRAME}.make (Base_utc, Base_utc + One_second, One_second, 4, False, l_readings,
				create {ARRAYED_LIST [TM_PROCESS_ACTIVITY]}.make (0), create {ARRAYED_LIST [TM_PROCESS_ID]}.make (0),
				create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0)))
			assert_reals_equal ("core 0", 80.0, l_window.aggregate ({TM_METRICS}.Cpu_core_busy_pct, {STRING_32} "0").reading.value, 0.0)
			assert_reals_equal ("core 1", 20.0, l_window.aggregate ({TM_METRICS}.Cpu_core_busy_pct, {STRING_32} "1").reading.value, 0.0)
			assert_true ("a core without its instance refused",
				raises (agent l_window.aggregate ({TM_METRICS}.Cpu_core_busy_pct, {STRING_32} "")))
		end

feature -- Tests: readings and capabilities

	test_includes
		note
			testing: "covers/{TM_READINGS}.includes"
		local
			l_small, l_large: TM_READINGS
		do
			create l_small.make
			l_small.put ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "", measured ({TM_METRICS}.Cpu_busy_pct, 5.0))
			create l_large.make_from (l_small)
			l_large.put ({TM_METRICS}.Mem_commit_pct, {STRING_32} "", measured ({TM_METRICS}.Mem_commit_pct, 5.0))
			assert_true ("superset", l_large.includes (l_small))
			assert_false ("subset does not include", l_small.includes (l_large))
			l_large.put ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "", measured ({TM_METRICS}.Cpu_busy_pct, 5.0))
			assert_false ("a different reading object is not included", l_large.includes (l_small))
		end

	test_capabilities_by_hand
		note
			testing: "covers/{TM_CAPABILITIES}.put"
		local
			l_caps: TM_CAPABILITIES
		do
			create l_caps.make_empty
			l_caps.put ({TM_METRICS}.Cpu_busy_pct, {TM_READING_STATUS}.Available, {STRING_32} "")
			l_caps.put ({TM_METRICS}.Temperature_c, {TM_READING_STATUS}.Not_supported, {STRING_32} "no sensor")
			l_caps.set_process_source ("documented", {STRING_32} "layout changed")
			assert_integers_equal ("two", 2, l_caps.count)
			assert_integers_equal ("model", 2, l_caps.support_model.count)
			assert_strings_equal_case_insensitive ("reason", "no sensor", l_caps.reason_of ({TM_METRICS}.Temperature_c))
			assert_strings_equal_case_insensitive ("fallback", "layout changed", l_caps.fallback_reason)
			assert_true ("twice refused", raises (agent l_caps.put ({TM_METRICS}.Cpu_busy_pct, {TM_READING_STATUS}.Available, {STRING_32} "")))
		end

feature -- Tests: sampler state

	test_sampler_keeps_previous_snapshot
		note
			testing: "covers/{TM_SAMPLER}.previous_snapshot"
		local
			l_processes: TM_SCRIPTED_PROCESS_SOURCE
			l_clock: TM_MANUAL_CLOCK
			l_sampler: TM_SAMPLER
		do
			create l_processes.make
			l_processes.add_round (<<sample (100, Base_utc, {STRING_32} "a.exe", 0, 1, 0)>>)
			l_processes.add_round (<<sample (100, Base_utc, {STRING_32} "a.exe", One_second, 1, 0)>>)
			create l_clock.make (Base_utc, 0)
			create l_sampler.make (l_processes, create {TM_SCRIPTED_SYSTEM_SOURCE}.make (4), l_clock)
			l_sampler.sample
			assert_false ("no previous yet", l_sampler.has_previous_snapshot)
			l_clock.advance (One_second)
			l_sampler.sample
			assert_integers_equal ("two snapshots", 2, l_sampler.snapshots_taken)
			assert_true ("previous is the first", l_sampler.previous_snapshot.monotonic_ticks = 0)
			assert_true ("last is the second", l_sampler.last_snapshot.monotonic_ticks = One_second)
			assert_true ("timeline end recorded", l_sampler.last_end_ticks = Base_utc + One_second)
			assert_false ("one second is not a gap", l_sampler.is_gap (l_sampler.previous_snapshot, l_sampler.last_snapshot))
		end

	test_budget_streaks_reset_on_change
			-- Review issue 12.
		note
			testing: "covers/{TM_SELF_BUDGET}.assess"
		local
			l_budget: TM_SELF_BUDGET
		do
			create l_budget.make (1.0, 1000, 8000)
			l_budget.assess (200_000, One_second)
			l_budget.assess (200_000, One_second)
			assert_integers_equal ("two over", 2, l_budget.over_streak)
			l_budget.assess (200_000, One_second)
			assert_integers_equal ("reset after backing off", 0, l_budget.over_streak)
			l_budget.assess (200_000, One_second)
			assert_integers_equal ("counting again", 1, l_budget.over_streak)
			assert_integers_equal ("still one change", 1, l_budget.changes)
			assert_integers_equal ("under streak zero while over", 0, l_budget.under_streak)
		end

feature {NONE} -- Fixtures

	new_series (a_capacity: INTEGER)
			-- Create a series of `a_capacity' (for precondition tests).
		local
			l_series: TM_SERIES
		do
			create l_series.make (a_capacity)
		end

end
