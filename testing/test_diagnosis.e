note
	description: "[
		Phase 4: the three rules on scripted windows - each bottleneck found
		with its culprit, precedence (memory before disk before CPU, the rest
		as "also"), calm windows, and missing readings giving "can't tell".
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_DIAGNOSIS

inherit
	TM_TEST_SET

feature -- Tests

	test_cpu_saturation_names_the_culprit
		local
			l_verdict: TM_VERDICT
		do
			l_verdict := diagnostician.diagnose (window (95.0, 60.0, 50.0, 10.0, <<busy ("hog.exe", 3.5), busy ("other.exe", 0.2)>>))
			assert_integers_equal ("cpu", {TM_VERDICT}.Cpu_saturation, l_verdict.kind)
			assert_true ("culprit", l_verdict.culprit.same_string ({STRING_32} "hog.exe"))
			assert_string_contains ("sentence", l_verdict.sentence, "CPU is saturated")
			assert_false ("evidence", l_verdict.evidence.is_empty)
		end

	test_memory_pressure_ranks_first
		local
			l_verdict: TM_VERDICT
		do
			l_verdict := diagnostician.diagnose (window (95.0, 97.0, 900.0, 92.0, <<busy ("hog.exe", 3.5)>>))
			assert_integers_equal ("memory first", {TM_VERDICT}.Memory_pressure, l_verdict.kind)
			assert_integers_equal ("disk and cpu as also", 2, l_verdict.also.count)
			assert_string_contains ("sentence", l_verdict.sentence, "memory is full")
		end

	test_disk_saturation
		local
			l_verdict: TM_VERDICT
		do
			l_verdict := diagnostician.diagnose (window (20.0, 60.0, 10.0, 95.0, <<mover ("copy.exe", 80_000_000.0)>>))
			assert_integers_equal ("disk", {TM_VERDICT}.Disk_saturation, l_verdict.kind)
			assert_true ("culprit", l_verdict.culprit.same_string ({STRING_32} "copy.exe"))
		end

	test_calm_window_says_no_bottleneck
		local
			l_verdict: TM_VERDICT
		do
			l_verdict := diagnostician.diagnose (window (10.0, 60.0, 5.0, 3.0, <<busy ("idle.exe", 0.1)>>))
			assert_integers_equal ("none", {TM_VERDICT}.None, l_verdict.kind)
			assert_string_contains ("numbers", l_verdict.sentence, "No bottleneck")
		end

	test_missing_readings_cannot_be_told
		local
			l_window: TM_WINDOW
			l_verdict: TM_VERDICT
			i: INTEGER
		do
			create l_window.make
			from i := 0 until i = 20 loop
				l_window.extend (empty_frame (Base_utc + i * One_second, 1))
				i := i + 1
			end
			l_verdict := diagnostician.diagnose (l_window)
			assert_integers_equal ("inconclusive", {TM_VERDICT}.Inconclusive, l_verdict.kind)
			assert_string_contains ("names what is missing", l_verdict.sentence, "memory")
		end

feature {NONE} -- Fixtures

	diagnostician: TM_DIAGNOSTICIAN
		do
			create Result.make
		end

	window (a_cpu, a_commit, a_faults, a_disk: REAL_64; a_activities: ARRAY [TM_PROCESS_ACTIVITY]): TM_WINDOW
			-- 20 one-second frames with these readings and processes.
		local
			i: INTEGER
			l_readings: TM_READINGS
		do
			create Result.make
			from i := 0 until i = 20 loop
				create l_readings.make
				l_readings.put ({TM_METRICS}.Cpu_utility_pct, {STRING_32} "", measured ({TM_METRICS}.Cpu_utility_pct, a_cpu))
				l_readings.put ({TM_METRICS}.Mem_commit_pct, {STRING_32} "", measured ({TM_METRICS}.Mem_commit_pct, a_commit))
				l_readings.put ({TM_METRICS}.Mem_hard_faults_per_s, {STRING_32} "", measured ({TM_METRICS}.Mem_hard_faults_per_s, a_faults))
				l_readings.put ({TM_METRICS}.Disk_busy_pct, {STRING_32} "1 D:", measured ({TM_METRICS}.Disk_busy_pct, a_disk))
				Result.extend (create {TM_FRAME}.make (Base_utc + i * One_second, Base_utc + (i + 1) * One_second, One_second, 4, False,
					l_readings, create {ARRAYED_LIST [TM_PROCESS_ACTIVITY]}.make_from_array (a_activities),
					create {ARRAYED_LIST [TM_PROCESS_ID]}.make (0), create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0)))
				i := i + 1
			end
		end

	busy (a_name: STRING_32; a_cores: REAL_64): TM_PROCESS_ACTIVITY
		do
			create Result.make_decoded (id (a_name.count + 100, 5000 + a_name.count), a_name, 4, 1, 4, 10, False, 4,
				{TM_READING_STATUS}.Available, a_cores, {TM_READING_STATUS}.Available, 100_000_000, 100_000_000,
				{TM_READING_STATUS}.Available, 0.0, 0.0)
		end

	mover (a_name: STRING_32; a_bps: REAL_64): TM_PROCESS_ACTIVITY
		do
			create Result.make_decoded (id (300, 6000), a_name, 4, 1, 4, 10, False, 4,
				{TM_READING_STATUS}.Available, 0.1, {TM_READING_STATUS}.Available, 10_000_000, 10_000_000,
				{TM_READING_STATUS}.Available, a_bps, 0.0)
		end

end
