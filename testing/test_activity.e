note
	description: "Tests for TM_PROCESS_ACTIVITY: rates between two samples of one identity, never clamped."
	author: "Larry Rix"
	testing: "covers"

class
	TEST_ACTIVITY

inherit
	TM_TEST_SET

feature -- Tests

	test_born_has_no_rates
		note
			testing: "covers/{TM_PROCESS_ACTIVITY}.make_born"
		local
			l_activity: TM_PROCESS_ACTIVITY
		do
			create l_activity.make_born (sample (900, Base_utc, {STRING_32} "new.exe", 5, 4096, 0), 4)
			assert_true ("new", l_activity.is_new)
			assert_false ("no cpu rate", l_activity.has_resource ({TM_RESOURCE}.Cpu))
			assert_false ("no io rate", l_activity.has_resource ({TM_RESOURCE}.Io_total))
			assert_true ("memory is a gauge", l_activity.private_bytes = 4096)
		end

	test_one_core_for_two_seconds
		note
			testing: "covers/{TM_PROCESS_ACTIVITY}.make_from_pair"
		local
			l_activity: TM_PROCESS_ACTIVITY
		do
			create l_activity.make_from_pair (
				sample (900, Base_utc, {STRING_32} "spin.exe", 0, 1000, 0),
				sample (900, Base_utc, {STRING_32} "spin.exe", 2 * One_second, 1000, 4_000_000), 2.0, 4)
			assert_integers_equal ("cpu available", {TM_READING_STATUS}.Available, l_activity.cpu_status)
			assert_reals_equal ("one core", 1.0, l_activity.cpu_cores, 0.000_001)
			assert_reals_equal ("quarter of machine", 25.0, l_activity.cpu_percent, 0.000_001)
			assert_reals_equal ("2 MB/s read", 2_000_000.0, l_activity.io_read_bps, 0.001)
		end

	test_counter_running_backward_is_invalid
		note
			testing: "covers/{TM_PROCESS_ACTIVITY}.make_from_pair"
		local
			l_activity: TM_PROCESS_ACTIVITY
		do
			create l_activity.make_from_pair (
				sample (900, Base_utc, {STRING_32} "odd.exe", 5 * One_second, 1000, 100),
				sample (900, Base_utc, {STRING_32} "odd.exe", One_second, 1000, 50), 1.0, 4)
			assert_integers_equal ("cpu invalid", {TM_READING_STATUS}.Invalid, l_activity.cpu_status)
			assert_integers_equal ("io invalid", {TM_READING_STATUS}.Invalid, l_activity.io_status)
		end

	test_impossible_rate_is_invalid_not_clamped
			-- DR-008: 9 cores on a 4-processor machine is not "100%".
		note
			testing: "covers/{TM_PROCESS_ACTIVITY}.make_from_pair"
		local
			l_activity: TM_PROCESS_ACTIVITY
		do
			create l_activity.make_from_pair (
				sample (900, Base_utc, {STRING_32} "odd.exe", 0, 1000, 0),
				sample (900, Base_utc, {STRING_32} "odd.exe", 9 * One_second, 1000, 0), 1.0, 4)
			assert_integers_equal ("cpu invalid", {TM_READING_STATUS}.Invalid, l_activity.cpu_status)
		end

	test_missing_group_keeps_the_more_useful_reason
		note
			testing: "covers/{TM_PROCESS_ACTIVITY}.make_from_pair"
		local
			l_before, l_after: TM_PROCESS_SAMPLE
			l_activity: TM_PROCESS_ACTIVITY
		do
			create l_before.make (id (4, Base_utc), {STRING_32} "System", 0, 0, 200)
			l_before.deny_cpu ({TM_READING_STATUS}.Access_denied)
			create l_after.make (id (4, Base_utc), {STRING_32} "System", 0, 0, 200)
			l_after.set_cpu (10, 10)
			create l_activity.make_from_pair (l_before, l_after, 1.0, 4)
			assert_integers_equal ("denied wins", {TM_READING_STATUS}.Access_denied, l_activity.cpu_status)
		end

	test_rate_across_identities_refused
		note
			testing: "covers/{TM_PROCESS_ACTIVITY}.make_from_pair"
		local
			l_before, l_after: TM_PROCESS_SAMPLE
		do
			l_before := sample (900, Base_utc, {STRING_32} "a.exe", 0, 1, 0)
			l_after := sample (900, Base_utc + 1, {STRING_32} "b.exe", 0, 1, 0)
			assert_true ("precondition fires", raises (agent (a_before, a_after: TM_PROCESS_SAMPLE)
				local
					l_activity: TM_PROCESS_ACTIVITY
				do
					create l_activity.make_from_pair (a_before, a_after, 1.0, 4)
				end (l_before, l_after)))
		end

	test_worse_of_order
		note
			testing: "covers/{TM_PROCESS_ACTIVITY}.worse_of"
		local
			l_activity: TM_PROCESS_ACTIVITY
		do
			create l_activity.make_born (sample (900, Base_utc, {STRING_32} "x.exe", 0, 1, 0), 4)
			assert_integers_equal ("denied over not supported", {TM_READING_STATUS}.Access_denied,
				l_activity.worse_of ({TM_READING_STATUS}.Not_supported, {TM_READING_STATUS}.Access_denied))
			assert_integers_equal ("not supported over unavailable", {TM_READING_STATUS}.Not_supported,
				l_activity.worse_of ({TM_READING_STATUS}.Unavailable, {TM_READING_STATUS}.Not_supported))
			assert_integers_equal ("anything over available", {TM_READING_STATUS}.Unavailable,
				l_activity.worse_of ({TM_READING_STATUS}.Available, {TM_READING_STATUS}.Unavailable))
		end

end
