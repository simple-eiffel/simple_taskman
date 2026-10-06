note
	description: "Phase 5: forecasts from scripted frames - memory runway, steady memory, leak suspects, and 'watching' until there is enough."
	author: "Larry Rix"
	testing: "covers"

class
	TEST_FORECAST

inherit
	TM_TEST_SET

feature -- Tests

	test_runway_when_commit_rises_toward_the_limit
		local
			l_book: TM_TREND_BOOK
			i: INTEGER
		do
			create l_book.make
			from i := 0 until i = 300 loop
				l_book.add (frame (i, 10.0e9 + i * 8.0e6, 20.0e9, 500))
				i := i + 1
			end
			assert_string_contains ("runs out", l_book.memory_text, "memory runs out in about")
			assert_true ("about 16 to 17 minutes left: " + l_book.runway_minutes.out, l_book.runway_minutes > 15.0 and l_book.runway_minutes < 18.0)
		end

	test_alarm_when_runway_is_short
		local
			l_book: TM_TREND_BOOK
			i: INTEGER
		do
			create l_book.make
			from i := 0 until i = 300 loop
				l_book.add (frame (i, 17.0e9 + i * 8.0e6, 20.0e9, 500))
				i := i + 1
			end
			assert_true ("alarming", l_book.is_alarming)
		end

	test_steady_memory
		local
			l_book: TM_TREND_BOOK
			i: INTEGER
		do
			create l_book.make
			from i := 0 until i = 300 loop
				l_book.add (frame (i, 10.0e9, 20.0e9, 500))
				i := i + 1
			end
			assert_string_contains ("steady", l_book.memory_text, "steady")
			assert_false ("no alarm", l_book.is_alarming)
		end

	test_watching_until_enough
		local
			l_book: TM_TREND_BOOK
		do
			create l_book.make
			l_book.add (frame (0, 10.0e9, 20.0e9, 500))
			assert_string_contains ("watching", l_book.memory_text, "watching")
		end

	test_leak_suspect_named
		local
			l_book: TM_TREND_BOOK
			i: INTEGER
		do
			create l_book.make
			from i := 0 until i = 1500 loop
				l_book.add (frame (i, 10.0e9, 20.0e9, (500.0 + i * 120.0 / 3600.0).truncated_to_integer))
				i := i + 1
			end
			assert_true ("one suspect", l_book.leak_texts.count = 1)
			assert_string_contains ("named", l_book.leak_texts.first, "grower.exe")
		end

feature {NONE} -- Fixtures

	frame (a_second: INTEGER; a_commit, a_limit: REAL_64; a_private_mb: INTEGER): TM_FRAME
			-- One-second frame at `a_second' with commit readings and one process holding `a_private_mb'.
		local
			l_readings: TM_READINGS
			l_list: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
		do
			create l_readings.make
			l_readings.put ({TM_METRICS}.Mem_commit_bytes, {STRING_32} "", measured ({TM_METRICS}.Mem_commit_bytes, a_commit))
			l_readings.put ({TM_METRICS}.Mem_commit_limit_bytes, {STRING_32} "", measured ({TM_METRICS}.Mem_commit_limit_bytes, a_limit))
			create l_list.make (1)
			l_list.extend (create {TM_PROCESS_ACTIVITY}.make_decoded (id (42, 4200), {STRING_32} "grower.exe", 4, 1, 4, 10, False, 4,
				{TM_READING_STATUS}.Available, 0.1, {TM_READING_STATUS}.Available,
				a_private_mb.to_integer_64 * 1_048_576, a_private_mb.to_integer_64 * 1_048_576,
				{TM_READING_STATUS}.Available, 0.0, 0.0))
			create Result.make (Base_utc + a_second * One_second, Base_utc + (a_second + 1) * One_second, One_second, 4, False,
				l_readings, l_list, create {ARRAYED_LIST [TM_PROCESS_ID]}.make (0), create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0))
		end

end
