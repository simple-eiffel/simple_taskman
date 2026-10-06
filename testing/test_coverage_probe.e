note
	description: "[
		Phase 5 coverage for the probe and the handoff texts: features no
		earlier test called directly, state machines, and boundaries.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_COVERAGE_PROBE

inherit
	TM_TEST_SET

feature -- Tests: self-check state machine

	test_self_check_decides_once
		note
			testing: "covers/{TM_SELF_CHECK}.fail_field"
		local
			l_check: TM_SELF_CHECK
			l_passed: TM_SELF_CHECK
		do
			create l_check.make_not_run
			assert_false ("not run", l_check.has_run)
			l_check.fail_field ("handles", 10, 99, 12)
			assert_true ("decided", l_check.has_run and not l_check.passed)
			assert_strings_equal_case_insensitive ("field", "handles", l_check.failing_field)
			assert_true ("bracket", l_check.value_before = 10 and l_check.value_native = 99 and l_check.value_after = 12)
			assert_string_contains ("explains", l_check.failure, "99")
			assert_true ("second decision refused", raises (agent l_check.pass))
			create l_passed.make_not_run
			l_passed.pass
			assert_true ("passed", l_passed.passed and l_passed.failure.is_empty)
			assert_true ("empty reason refused", raises (agent (create {TM_SELF_CHECK}.make_not_run).fail ({STRING_32} "")))
		end

feature -- Tests: sources

	test_kinds_and_nativeness
		note
			testing: "covers/{TM_PROCESS_SOURCE}.kind_name"
		do
			assert_strings_equal_case_insensitive ("documented", "documented", (create {TM_DOCUMENTED_PROCESS_SOURCE}.make).kind_name)
			assert_false ("documented is not native", (create {TM_DOCUMENTED_PROCESS_SOURCE}.make).is_native)
			assert_strings_equal_case_insensitive ("scripted", "scripted", (create {TM_SCRIPTED_PROCESS_SOURCE}.make).kind_name)
			assert_true ("native-like script", (create {TM_SCRIPTED_PROCESS_SOURCE}.make_native_like).is_native)
		end

	test_native_like_script_must_list_idle
		note
			testing: "covers/{TM_SCRIPTED_PROCESS_SOURCE}.add_round"
		local
			l_source: TM_SCRIPTED_PROCESS_SOURCE
		do
			create l_source.make_native_like
			assert_true ("round without idle refused",
				raises (agent l_source.add_round (<<sample (100, Base_utc, {STRING_32} "a.exe", 0, 1, 0)>>)))
			l_source.add_round (<<idle_sample (0), sample (100, Base_utc, {STRING_32} "a.exe", 0, 1, 0)>>)
			assert_integers_equal ("accepted", 1, l_source.rounds_remaining)
			l_source.read_all
			assert_true ("idle listed", l_source.has_idle_entry)
			assert_true ("unique", l_source.has_unique_identities)
		end

	test_duplicate_identities_break_the_read_contract
			-- A source that returns one identity twice violates read_all's
			-- `unique_identities'; the contract catches it.
		note
			testing: "covers/{TM_PROCESS_SOURCE}.has_unique_identities"
		local
			l_source: TM_SCRIPTED_PROCESS_SOURCE
		do
			create l_source.make
			l_source.add_round (<<sample (100, Base_utc, {STRING_32} "a.exe", 0, 1, 0),
				sample (100, Base_utc, {STRING_32} "a.exe", 5, 1, 0)>>)
			assert_true ("postcondition fires", raises (agent l_source.read_all))
		end

	test_scripted_support_reasons_and_codes
		note
			testing: "covers/{TM_SYSTEM_SOURCE}.support_reason"
		local
			l_source: TM_SCRIPTED_SYSTEM_SOURCE
		do
			create l_source.make (8)
			l_source.declare_support ({TM_METRICS}.Cpu_busy_pct, {TM_READING_STATUS}.Available, {STRING_32} "")
			l_source.declare_support ({TM_METRICS}.Lag_max_ms, {TM_READING_STATUS}.Access_denied, {STRING_32} "needs admin")
			assert_true ("supported codes", l_source.supported_codes.has ({TM_METRICS}.Cpu_busy_pct)
				and l_source.supported_codes.count = 1)
			assert_strings_equal_case_insensitive ("declared reason", "needs admin", l_source.support_reason ({TM_METRICS}.Lag_max_ms))
			assert_string_empty ("supported has no reason", l_source.support_reason ({TM_METRICS}.Cpu_busy_pct))
			assert_strings_equal_case_insensitive ("undeclared", "not scripted", l_source.support_reason ({TM_METRICS}.Battery_pct))
			assert_true ("a reason with support refused",
				raises (agent l_source.declare_support ({TM_METRICS}.Mem_commit_pct, {TM_READING_STATUS}.Available, {STRING_32} "why")))
			assert_true ("a value for an unsupported metric refused",
				raises (agent l_source.script_reading ({TM_METRICS}.Battery_pct, {STRING_32} "", create {TM_READING}.make_unavailable)))
			l_source.script_reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "", measured ({TM_METRICS}.Cpu_busy_pct, 1.0))
			assert_integers_equal ("pending", 1, l_source.pending_count)
			l_source.end_round
			l_source.refresh
			assert_true ("refreshed", l_source.has_refreshed)
			assert_true ("denied reads as declared", l_source.last_readings.reading ({TM_METRICS}.Lag_max_ms, {STRING_32} "").is_access_denied)
			assert_true ("undeclared reads not supported", l_source.last_readings.reading ({TM_METRICS}.Battery_pct, {STRING_32} "").is_not_supported)
		end

	test_win_source_explains_every_refusal
			-- Machine-neutral: whatever this machine lacks, it says why.
		note
			testing: "covers/{TM_WIN_SYSTEM_SOURCE}.support_reason"
		local
			l_system: TM_WIN_SYSTEM_SOURCE
		do
			create l_system.make
			across metrics.codes as ic loop
				if l_system.support_of (ic) = {TM_READING_STATUS}.Available then
					assert_string_empty ("no reason when supported: " + metric (ic).name, l_system.support_reason (ic))
				else
					assert_string_not_empty ("reason when not: " + metric (ic).name, l_system.support_reason (ic))
				end
			end
			assert_integers_equal ("memory always", {TM_READING_STATUS}.Available, l_system.support_of ({TM_METRICS}.Mem_commit_pct))
			l_system.close
		end

feature -- Tests: counters and topology

	test_uncapped_counter
		note
			testing: "covers/{TM_COUNTER_QUERY}.add_english_uncapped"
		local
			l_query: TM_COUNTER_QUERY
			l_clock: TM_SYSTEM_CLOCK
		do
			create l_query.make
			create l_clock.make
			assert_integers_equal ("index", 1, l_query.add_english_uncapped ("\Processor Information(_Total)\%% Processor Utility"))
			l_query.collect
			l_clock.sleep_ms (100)
			l_query.collect
			assert_integers_equal ("two collections", 2, l_query.collections)
			assert_true ("valid", l_query.values (1).first.is_valid)
			assert_true ("status zero means valid", l_query.values (1).first.pdh_status = {TM_COUNTER_VALUE}.Pdh_cstatus_valid_data
				or l_query.values (1).first.pdh_status = {TM_COUNTER_VALUE}.Pdh_cstatus_new_data)
			assert_true ("values need a collection", raises (agent (create {TM_COUNTER_QUERY}.make).values (1)))
			l_query.close
		end

	test_topology_accessors_and_bounds
		note
			testing: "covers/{TM_CPU_TOPOLOGY}.efficiency_class"
		local
			l_topology: TM_CPU_TOPOLOGY
		do
			create l_topology.make_from_groups (<<2, 3>>, <<1, 1, 0, 0, 0>>)
			assert_integers_equal ("group 1 size", 3, l_topology.group_size (1))
			assert_integers_equal ("P-core", 1, l_topology.efficiency_class (0))
			assert_integers_equal ("E-core", 0, l_topology.efficiency_class (4))
			assert_integers_equal ("sum", 5, l_topology.sum_of (<<2, 3>>))
			assert_true ("number past its group refused", raises (agent l_topology.flat_index (0, 2)))
			assert_true ("group past the end refused", raises (agent l_topology.group_size (2)))
			assert_true ("too many classes refused", raises (agent new_topology (<<2>>, <<0, 0, 0>>)))
			assert_true ("group over 64 refused", raises (agent new_topology (<<65>>, filled (65))))
		end

feature -- Tests: paths

	test_plain_names_and_folders
		note
			testing: "covers/{TM_PATHS}.is_plain_name"
		local
			l_paths: TM_PATHS
		do
			create l_paths.make_with_base ({STRING_32} "C:\base\")
			assert_strings_equal_diff ("trailing separator not doubled", {STRING_32} "C:\base\simple_taskman", l_paths.root)
			assert_strings_equal_diff ("logs", {STRING_32} "C:\base\simple_taskman\logs", l_paths.logs_folder)
			assert_string_empty ("no missing reason", l_paths.missing_reason)
			assert_true ("plain", l_paths.is_plain_name ({STRING_32} "taskman_recorder-2"))
			assert_false ("space", l_paths.is_plain_name ({STRING_32} "task man"))
			assert_false ("dot", l_paths.is_plain_name ({STRING_32} "a.b"))
			assert_false ("empty", l_paths.is_plain_name ({STRING_32} ""))
		end

feature -- Tests: slot texts

	test_capabilities_and_failure_texts
		note
			testing: "covers/{TM_FRAME_SLOT}.put_failure"
		local
			l_slot: TM_FRAME_SLOT
		do
			create l_slot.make
			l_slot.put_capabilities ("TMC1%NS%Tkind%Tnative%N")
			assert_true ("capabilities ready", l_slot.has_capabilities)
			assert_string_starts_with ("copied", l_slot.capabilities_text, "TMC1")
			l_slot.put_failure ({STRING_32} "NtQuerySystemInformation failed three times")
			assert_true ("failed", l_slot.has_failure)
			assert_string_contains ("why", l_slot.failure_text, "three times")
			assert_false ("failure is not a stop", l_slot.has_stopped)
			assert_true ("empty failure refused", raises (agent l_slot.put_failure ({STRING_32} "")))
		end

feature {NONE} -- Fixtures

	new_topology (a_sizes, a_classes: ARRAY [INTEGER])
			-- Create a topology (for precondition tests).
		local
			l_topology: TM_CPU_TOPOLOGY
		do
			create l_topology.make_from_groups (a_sizes, a_classes)
		end

	filled (a_count: INTEGER): ARRAY [INTEGER]
			-- `a_count' zeros.
		do
			create Result.make_filled (0, 1, a_count)
		end

end
