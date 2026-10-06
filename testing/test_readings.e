note
	description: "Tests for TM_READINGS: keyed by metric and instance, absent reads as not supported, sealed is immutable."
	author: "Larry Rix"
	testing: "covers"

class
	TEST_READINGS

inherit
	TM_TEST_SET

feature -- Tests

	test_absent_reads_not_supported
		note
			testing: "covers/{TM_READINGS}.reading"
		local
			l_readings: TM_READINGS
		do
			create l_readings.make
			assert_true ("not supported", l_readings.reading ({TM_METRICS}.Temperature_c, {STRING_32} "zone0").is_not_supported)
		end

	test_put_then_read
		note
			testing: "covers/{TM_READINGS}.put"
		local
			l_readings: TM_READINGS
			l_watts: TM_READING
		do
			create l_readings.make
			l_watts := measured ({TM_METRICS}.Cpu_package_watts, 42.0)
			l_readings.put ({TM_METRICS}.Cpu_package_watts, {STRING_32} "", l_watts)
			assert_same_reference ("stored", l_watts, l_readings.reading ({TM_METRICS}.Cpu_package_watts, {STRING_32} ""))
			assert_integers_equal ("one", 1, l_readings.count)
		end

	test_instances_in_insertion_order
		note
			testing: "covers/{TM_READINGS}.instances"
		local
			l_readings: TM_READINGS
			l_names: ARRAYED_LIST [STRING_32]
		do
			create l_readings.make
			l_readings.put ({TM_METRICS}.Cpu_core_busy_pct, {STRING_32} "0,1", measured ({TM_METRICS}.Cpu_core_busy_pct, 10.0))
			l_readings.put ({TM_METRICS}.Cpu_core_busy_pct, {STRING_32} "0,0", measured ({TM_METRICS}.Cpu_core_busy_pct, 20.0))
			l_readings.put ({TM_METRICS}.Cpu_core_busy_pct, {STRING_32} "0,1", measured ({TM_METRICS}.Cpu_core_busy_pct, 30.0))
			l_names := l_readings.instances ({TM_METRICS}.Cpu_core_busy_pct)
			assert_integers_equal ("two instances", 2, l_names.count)
			assert_strings_equal_case_insensitive ("first seen first", "0,1", l_names [1])
		end

	test_sealed_refuses_put
		note
			testing: "covers/{TM_READINGS}.seal"
		local
			l_readings: TM_READINGS
		do
			l_readings := sealed_readings
			assert_true ("put refused", raises (agent l_readings.put ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "", create {TM_READING}.make_unavailable)))
		end

	test_instance_rule
			-- A system-wide metric takes no instance; a per-core metric needs one.
		note
			testing: "covers/{TM_READINGS}.put"
		local
			l_readings: TM_READINGS
		do
			create l_readings.make
			assert_true ("instance on a total refused", raises (agent l_readings.put ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "0,0", create {TM_READING}.make_unavailable)))
			assert_true ("no instance on a core refused", raises (agent l_readings.put ({TM_METRICS}.Cpu_core_busy_pct, {STRING_32} "", create {TM_READING}.make_unavailable)))
		end

	test_value_filed_under_the_wrong_metric_refused
			-- Review issue 3: 1,500 W is a fine power reading and an impossible percent.
		note
			testing: "covers/{TM_READINGS}.put"
		local
			l_readings: TM_READINGS
			l_watts: TM_READING
		do
			create l_readings.make
			l_watts := measured ({TM_METRICS}.Cpu_package_watts, 1500.0)
			assert_true ("available as watts", l_watts.is_available)
			assert_true ("refused as a percent", raises (agent l_readings.put ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "", l_watts)))
		end

	test_reading_with_wrong_instance_form_refused
			-- Review issue 7.
		note
			testing: "covers/{TM_READINGS}.reading"
		local
			l_readings: TM_READINGS
		do
			create l_readings.make
			assert_true ("core metric without an instance", raises (agent l_readings.reading ({TM_METRICS}.Cpu_core_busy_pct, {STRING_32} "")))
		end

	test_put_frame_condition_in_mml
			-- The MML form of put's frame condition (review issues 1, 9).
		note
			testing: "covers/{TM_READINGS}.put"
		local
			l_readings: TM_READINGS
			l_before: MML_MAP [STRING_8, TM_READING]
			l_commit: TM_READING
		do
			create l_readings.make
			l_readings.put ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "", measured ({TM_METRICS}.Cpu_busy_pct, 10.0))
			l_readings.put ({TM_METRICS}.Mem_commit_pct, {STRING_32} "", measured ({TM_METRICS}.Mem_commit_pct, 50.0))
			l_before := l_readings.readings_model
			l_commit := measured ({TM_METRICS}.Mem_commit_pct, 51.0)
			l_readings.put ({TM_METRICS}.Mem_commit_pct, {STRING_32} "", l_commit)
			assert_true ("one key replaced", l_readings.readings_model |=|
				l_before.updated (l_readings.key ({TM_METRICS}.Mem_commit_pct, {STRING_32} ""), l_commit))
		end

	test_make_from_copies_and_reopens
		note
			testing: "covers/{TM_READINGS}.make_from"
		local
			l_sealed, l_copy: TM_READINGS
		do
			create l_sealed.make
			l_sealed.put ({TM_METRICS}.Mem_commit_pct, {STRING_32} "", measured ({TM_METRICS}.Mem_commit_pct, 61.0))
			l_sealed.seal
			create l_copy.make_from (l_sealed)
			assert_false ("open", l_copy.is_sealed)
			assert_true ("entry copied", l_copy.has ({TM_METRICS}.Mem_commit_pct, {STRING_32} ""))
			l_copy.put ({TM_METRICS}.Sample_cost_ms, {STRING_32} "", measured ({TM_METRICS}.Sample_cost_ms, 2.5))
			assert_integers_equal ("original untouched", 1, l_sealed.count)
		end

end
