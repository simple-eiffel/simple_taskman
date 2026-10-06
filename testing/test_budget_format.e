note
	description: "Tests for TM_SELF_BUDGET (sampling cost only, R-1) and TM_FORMAT (never a number for a missing value, DR-017)."
	author: "Larry Rix"
	testing: "covers"

class
	TEST_BUDGET_FORMAT

inherit
	TM_TEST_SET

feature -- Tests: TM_SELF_BUDGET

	test_budget_starts_fast
		note
			testing: "covers/{TM_SELF_BUDGET}.make"
		local
			l_budget: TM_SELF_BUDGET
		do
			create l_budget.make (1.0, 1000, 10_000)
			assert_integers_equal ("minimum interval", 1000, l_budget.interval_ms)
		end

	test_share_is_cost_over_interval
		note
			testing: "covers/{TM_SELF_BUDGET}.assess"
		local
			l_budget: TM_SELF_BUDGET
		do
			create l_budget.make (1.0, 1000, 10_000)
			l_budget.assess (50_000, One_second)
			assert_reals_equal ("0.5 percent", 0.5, l_budget.last_share_pct, 0.000_001)
			assert_integers_equal ("unchanged", 1000, l_budget.interval_ms)
		end

	test_backs_off_after_three_ticks_over
		note
			testing: "covers/{TM_SELF_BUDGET}.assess"
		local
			l_budget: TM_SELF_BUDGET
		do
			create l_budget.make (1.0, 1000, 10_000)
			l_budget.assess (200_000, One_second)
			l_budget.assess (200_000, One_second)
			assert_integers_equal ("not yet", 1000, l_budget.interval_ms)
			l_budget.assess (200_000, One_second)
			assert_true ("backed off", l_budget.interval_ms > 1000)
			assert_integers_equal ("one change", 1, l_budget.changes)
		end

	test_never_exceeds_the_maximum
		note
			testing: "covers/{TM_SELF_BUDGET}.assess"
		local
			l_budget: TM_SELF_BUDGET
			i: INTEGER
		do
			create l_budget.make (1.0, 1000, 4000)
			from
				i := 1
			until
				i > 50
			loop
				l_budget.assess (One_second, One_second)
				i := i + 1
			end
			assert_integers_equal ("capped", 4000, l_budget.interval_ms)
		end

	test_speeds_up_after_a_quiet_spell
		note
			testing: "covers/{TM_SELF_BUDGET}.assess"
		local
			l_budget: TM_SELF_BUDGET
			l_backed_off, i: INTEGER
		do
			create l_budget.make (1.0, 1000, 10_000)
			from i := 1 until i > 3 loop
				l_budget.assess (200_000, One_second)
				i := i + 1
			end
			l_backed_off := l_budget.interval_ms
			from i := 1 until i > {TM_SELF_BUDGET}.Under_limit loop
				l_budget.assess (1_000, One_second)
				i := i + 1
			end
			assert_true ("faster again", l_budget.interval_ms < l_backed_off)
		end

feature -- Tests: TM_FORMAT

	test_missing_reading_is_words_for_every_status
		note
			testing: "covers/{TM_FORMAT}.reading_text"
		local
			l_format: TM_FORMAT
			l_watts: TM_METRIC
		do
			create l_format
			l_watts := metric ({TM_METRICS}.Cpu_package_watts)
			assert_strings_equal_case_insensitive ("unavailable", "unavailable", l_format.reading_text (create {TM_READING}.make_unavailable, l_watts))
			assert_strings_equal_case_insensitive ("not supported", "not supported", l_format.reading_text (create {TM_READING}.make_not_supported, l_watts))
			assert_strings_equal_case_insensitive ("denied", "access denied", l_format.reading_text (create {TM_READING}.make_access_denied, l_watts))
			assert_strings_equal_case_insensitive ("invalid", "invalid", l_format.reading_text (create {TM_READING}.make_invalid, l_watts))
		end

	test_watts
		note
			testing: "covers/{TM_FORMAT}.reading_text"
		local
			l_format: TM_FORMAT
		do
			create l_format
			assert_strings_equal_case_insensitive ("watts", "61.2 W",
				l_format.reading_text (measured ({TM_METRICS}.Cpu_package_watts, 61.2), metric ({TM_METRICS}.Cpu_package_watts)))
		end

	test_bytes_are_scaled
		note
			testing: "covers/{TM_FORMAT}.bytes"
		local
			l_format: TM_FORMAT
		do
			create l_format
			assert_strings_equal_case_insensitive ("gigabytes", "1.2 GB", l_format.bytes (1_288_490_189))
			assert_strings_equal_case_insensitive ("bytes", "512 B", l_format.bytes (512))
		end

	test_percent_and_cores
		note
			testing: "covers/{TM_FORMAT}.percent"
		local
			l_format: TM_FORMAT
		do
			create l_format
			assert_strings_equal_case_insensitive ("percent", "4.1%%", l_format.percent (4.1))
			assert_strings_equal_case_insensitive ("cores", "2.4 cores", l_format.cores (2.4))
		end

	test_status_words_are_not_numbers
		note
			testing: "covers/{TM_FORMAT}.status_word"
		local
			l_format: TM_FORMAT
		do
			create l_format
			assert_strings_equal_case_insensitive ("denied", "denied", l_format.status_word ({TM_READING_STATUS}.Access_denied))
			assert_strings_equal_case_insensitive ("n/a", "n/a", l_format.status_word ({TM_READING_STATUS}.Unavailable))
		end

end
