note
	description: "Tests for TM_PROCESS_ID and TM_PROCESS_SAMPLE: identity is pid plus creation time; groups are set once."
	author: "Larry Rix"
	testing: "covers"

class
	TEST_PROCESS_ID

inherit
	TM_TEST_SET

feature -- Tests: TM_PROCESS_ID

	test_recycled_pid_is_another_process
			-- FR-003: the same pid with another creation time is not the same process.
		note
			testing: "covers/{TM_PROCESS_ID}.is_equal"
		do
			assert_true ("same", id (4120, Base_utc) ~ id (4120, Base_utc))
			assert_false ("recycled", id (4120, Base_utc) ~ id (4120, Base_utc + 1))
			assert_false ("other pid", id (4120, Base_utc) ~ id (4121, Base_utc))
		end

	test_equal_identities_hash_equal
		note
			testing: "covers/{TM_PROCESS_ID}.hash_code"
		do
			assert_integers_equal ("hash", id (4120, Base_utc).hash_code, id (4120, Base_utc).hash_code)
			assert_true ("non-negative at extremes", id (4_294_967_295, 9_000_000_000_000_000_000).hash_code >= 0)
		end

	test_idle_pseudo_process
		note
			testing: "covers/{TM_PROCESS_ID}.is_idle_pseudo_process"
		do
			assert_true ("pid 0", id (0, 0).is_idle_pseudo_process)
			assert_false ("system", id (4, Base_utc).is_idle_pseudo_process)
		end

	test_identity_works_as_table_key
		note
			testing: "covers/{TM_PROCESS_ID}.hash_code"
		local
			l_table: HASH_TABLE [STRING_32, TM_PROCESS_ID]
		do
			create l_table.make (4)
			l_table.force ({STRING_32} "first", id (4120, Base_utc))
			l_table.force ({STRING_32} "second", id (4120, Base_utc + 1))
			assert_integers_equal ("two identities", 2, l_table.count)
			assert_attached ("found by value", l_table.item (id (4120, Base_utc)))
		end

feature -- Tests: TM_PROCESS_SAMPLE

	test_groups_start_unset
		note
			testing: "covers/{TM_PROCESS_SAMPLE}.make"
		local
			l_sample: TM_PROCESS_SAMPLE
		do
			create l_sample.make (id (77, Base_utc), {STRING_32} "msedge.exe", 4, 1, 30)
			assert_integers_equal ("cpu unset", {TM_READING_STATUS}.Unavailable, l_sample.cpu_status)
			assert_integers_equal ("memory unset", {TM_READING_STATUS}.Unavailable, l_sample.memory_status)
			assert_integers_equal ("io unset", {TM_READING_STATUS}.Unavailable, l_sample.io_status)
		end

	test_setting_one_group_leaves_the_others
		note
			testing: "covers/{TM_PROCESS_SAMPLE}.set_cpu"
		local
			l_sample: TM_PROCESS_SAMPLE
		do
			create l_sample.make (id (77, Base_utc), {STRING_32} "msedge.exe", 4, 1, 30)
			l_sample.set_cpu (500, 200)
			l_sample.deny_io ({TM_READING_STATUS}.Access_denied)
			assert_integers_equal ("cpu", {TM_READING_STATUS}.Available, l_sample.cpu_status)
			assert_true ("user kept", l_sample.user_ticks = 500)
			assert_integers_equal ("memory still unset", {TM_READING_STATUS}.Unavailable, l_sample.memory_status)
			assert_integers_equal ("io denied", {TM_READING_STATUS}.Access_denied, l_sample.io_status)
		end

	test_a_group_is_set_once
		note
			testing: "covers/{TM_PROCESS_SAMPLE}.set_cpu"
		local
			l_sample: TM_PROCESS_SAMPLE
		do
			l_sample := sample (77, Base_utc, {STRING_32} "msedge.exe", 1, 1, 1)
			assert_true ("second set refused", raises (agent l_sample.set_cpu (2, 2)))
		end

	test_denied_group_has_no_number
		note
			testing: "covers/{TM_PROCESS_SAMPLE}.read_bytes"
		local
			l_sample: TM_PROCESS_SAMPLE
		do
			create l_sample.make (id (77, Base_utc), {STRING_32} "svchost.exe", 4, 0, 3)
			l_sample.deny_io ({TM_READING_STATUS}.Access_denied)
			assert_true ("read refused", raises (agent l_sample.read_bytes))
		end

end
