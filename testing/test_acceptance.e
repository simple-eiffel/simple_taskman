note
	description: "[
		Acceptance tests that state facts about the reference machine, JACKJACK
		(Phase 1 acceptance criteria): the native table passes its self-check,
		CPU package power is available, temperature and battery are not
		supported. Run only on that machine; anywhere else these facts may
		differ without any defect (review issue 10).
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_ACCEPTANCE

inherit
	TM_TEST_SET

feature -- Tests: reference machine

	test_native_table_trusted_here
			-- Acceptance: the native table passes its self-check on this machine.
		note
			testing: "covers/{TM_NATIVE_PROCESS_SOURCE}.make"
		local
			l_native: TM_NATIVE_PROCESS_SOURCE
		do
			create l_native.make
			assert_true ({STRING_32} "trusted: " + l_native.last_self_check.failure, l_native.is_trusted)
		end

	test_native_read_lists_idle_and_self
		note
			testing: "covers/{TM_NATIVE_PROCESS_SOURCE}.read_all"
		local
			l_native: TM_NATIVE_PROCESS_SOURCE
			l_self: TM_SELF_PROCESS
		do
			create l_native.make
			create l_self.make
			assert_true ("trusted", l_native.is_trusted)
			l_native.read_all
			assert_true ({STRING_32} "read: " + l_native.last_error, l_native.last_read_succeeded)
			assert_true ("idle listed", l_native.has_idle_entry)
			assert_true ("self listed", l_native.has_sample (l_self.id))
		end

	test_win_capabilities_here
			-- Acceptance: package power available; temperature and battery not supported.
		note
			testing: "covers/{TM_WIN_SYSTEM_SOURCE}.support_of"
		local
			l_system: TM_WIN_SYSTEM_SOURCE
		do
			create l_system.make
			assert_integers_equal ("package power", {TM_READING_STATUS}.Available, l_system.support_of ({TM_METRICS}.Cpu_package_watts))
			assert_integers_equal ("temperature", {TM_READING_STATUS}.Not_supported, l_system.support_of ({TM_METRICS}.Temperature_c))
			assert_integers_equal ("battery", {TM_READING_STATUS}.Not_supported, l_system.support_of ({TM_METRICS}.Battery_pct))
			l_system.close
		end

	test_live_facade_uses_the_native_table
			-- What the capability panel will say here: "Process table: native, self-check passed".
		note
			testing: "covers/{SIMPLE_TASKMAN}.native_self_check_passed"
		local
			l_tm: SIMPLE_TASKMAN
		do
			create l_tm.make
			assert_strings_equal_case_insensitive ("native", "native", l_tm.process_source_kind)
			assert_true ("self-check passed", l_tm.native_self_check_passed)
			assert_string_empty ("no fallback reason", l_tm.fallback_reason)
			l_tm.close
		end

	test_package_power_reads_a_plausible_value
			-- The RAPL package meter on this machine draws watts, not zero. The energy
			-- meter's "_Total" instance reads 0; reading it instead was a real defect
			-- caught by the CLI smoke test (2026-10-05).
		note
			testing: "covers/{TM_WIN_SYSTEM_SOURCE}.refresh"
		local
			l_system: TM_WIN_SYSTEM_SOURCE
			l_power: TM_READING
			l_clock: TM_SYSTEM_CLOCK
		do
			create l_system.make
			create l_clock.make
			l_clock.sleep_ms (500)
			l_system.refresh
			l_power := l_system.last_readings.reading ({TM_METRICS}.Cpu_package_watts, {STRING_32} "")
			assert_true ("available", l_power.is_available)
			assert_real_in_range ("a running package draws 1 to 500 W", l_power.value, 1.0, 500.0)
			l_system.close
		end

	test_documented_denies_rather_than_zeroes
			-- Unelevated on the reference machine, some protected process refuses a
			-- group; it must say "access denied", never report zeros.
		note
			testing: "covers/{TM_DOCUMENTED_PROCESS_SOURCE}.read_all"
		local
			l_source: TM_DOCUMENTED_PROCESS_SOURCE
		do
			create l_source.make
			l_source.read_all
			assert_true ("read", l_source.last_read_succeeded)
			assert_true ("some group denied", across l_source.last_samples as ic some
				ic.memory_status = {TM_READING_STATUS}.Access_denied or ic.cpu_status = {TM_READING_STATUS}.Access_denied end)
		end

end
