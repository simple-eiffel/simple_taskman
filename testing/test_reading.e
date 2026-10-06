note
	description: "Tests for TM_READING and TM_METRIC: a value enters only through its metric's range check."
	author: "Larry Rix"
	testing: "covers"

class
	TEST_READING

inherit
	TM_TEST_SET

feature -- Tests: TM_READING

	test_measured_inside_range_is_available
		note
			testing: "covers/{TM_READING}.make_measured"
		local
			l_reading: TM_READING
		do
			l_reading := measured ({TM_METRICS}.Cpu_package_watts, 61.2)
			assert_true ("available", l_reading.is_available)
			assert_reals_equal ("value", 61.2, l_reading.value, 0.0)
			assert_strings_equal_case_insensitive ("name", "available", l_reading.status_name)
		end

	test_measured_outside_range_is_invalid
			-- DR-002: a percent of 140 cannot be true; it is stored as invalid, never clamped.
		note
			testing: "covers/{TM_READING}.make_measured"
		do
			assert_true ("over range", measured ({TM_METRICS}.Cpu_busy_pct, 140.0).is_invalid)
			assert_true ("under range", measured ({TM_METRICS}.Cpu_busy_pct, -0.5).is_invalid)
		end

	test_non_finite_is_invalid
		note
			testing: "covers/{TM_READING}.make_measured"
		local
			l_zero: REAL_64
		do
			assert_true ("nan", measured ({TM_METRICS}.Cpu_busy_pct, l_zero / l_zero).is_invalid)
			assert_true ("infinity", measured ({TM_METRICS}.Cpu_busy_pct, 1.0 / l_zero).is_invalid)
		end

	test_status_names_are_words
		note
			testing: "covers/{TM_READING}.status_name"
		do
			assert_strings_equal_case_insensitive ("unavailable", "unavailable", (create {TM_READING}.make_unavailable).status_name)
			assert_strings_equal_case_insensitive ("not supported", "not supported", (create {TM_READING}.make_not_supported).status_name)
			assert_strings_equal_case_insensitive ("denied", "access denied", (create {TM_READING}.make_access_denied).status_name)
			assert_strings_equal_case_insensitive ("invalid", "invalid", (create {TM_READING}.make_invalid).status_name)
		end

	test_value_of_missing_reading_is_refused
			-- I-007: there is no number to read from a missing reading.
		note
			testing: "covers/{TM_READING}.value"
		local
			l_reading: TM_READING
		do
			create l_reading.make_not_supported
			assert_true ("precondition fires", raises (agent l_reading.value))
		end

feature -- Tests: TM_METRIC and TM_METRICS

	test_catalog_is_dense
		note
			testing: "covers/{TM_METRICS}.metric"
		do
			assert_integers_equal ("count", {TM_METRICS}.Last_code, metrics.count)
			across metrics.codes as ic loop
				assert_integers_equal ("code " + ic.out, ic, metrics.metric (ic).code)
			end
		end

	test_names_are_valid_and_unique
		note
			testing: "covers/{TM_METRICS}.metric_named"
		do
			across metrics.all_metrics as ic loop
				assert_true ("valid " + ic.name, ic.is_valid_name (ic.name))
				assert_integers_equal ("unique " + ic.name, ic.code, metrics.metric_named (ic.name).code)
			end
		end

	test_valid_name_rules
		note
			testing: "covers/{TM_METRIC}.is_valid_name"
		local
			l_metric: TM_METRIC
		do
			l_metric := metric ({TM_METRICS}.Cpu_busy_pct)
			assert_true ("dotted", l_metric.is_valid_name ("cpu.core.busy_pct"))
			assert_false ("empty", l_metric.is_valid_name (""))
			assert_false ("leading dot", l_metric.is_valid_name (".cpu"))
			assert_false ("trailing dot", l_metric.is_valid_name ("cpu."))
			assert_false ("double dot", l_metric.is_valid_name ("cpu..busy"))
			assert_false ("upper case", l_metric.is_valid_name ("CPU.busy"))
			assert_false ("space", l_metric.is_valid_name ("cpu busy"))
		end

	test_only_peak_metrics_aggregate_by_maximum
		note
			testing: "covers/{TM_METRIC}.is_peak"
		do
			across metrics.all_metrics as ic loop
				assert_equal ("peak " + ic.name,
					ic.code = {TM_METRICS}.Lag_max_ms or ic.code = {TM_METRICS}.Sample_cost_ms, ic.is_peak)
			end
		end

end
