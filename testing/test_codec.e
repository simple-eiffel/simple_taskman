note
	description: "Tests for TM_FRAME_CODEC (TMF1): exact round trip; a damaged file yields invalid, never impossible."
	author: "Larry Rix"
	testing: "covers"

class
	TEST_CODEC

inherit
	TM_TEST_SET

feature -- Tests

	test_round_trip_is_exact
			-- DR-018: reals travel as their 64 bits.
		note
			testing: "covers/{TM_FRAME_CODEC}.encode"
		local
			l_codec: TM_FRAME_CODEC
			l_frame: TM_FRAME
		do
			create l_codec.make
			l_frame := frame_with_cpu (Base_utc, 1, 33.333_333_333_333_3)
			l_codec.decode (l_codec.encode (l_frame))
			assert_true ("decoded", l_codec.has_frame)
			assert_true ("same start", l_codec.last_frame.start_ticks = l_frame.start_ticks)
			assert_true ("bit-exact value", l_codec.last_frame.readings.reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "").value
				= l_frame.readings.reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "").value)
		end

	test_unknown_header_is_refused_with_the_line
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
		do
			create l_codec.make
			l_codec.decode ("TMF9%T1%T2%T1%T4%T0%T1%T0%N")
			assert_false ("refused", l_codec.has_frame)
			assert_string_contains ("names the line", l_codec.last_error, "line 1")
		end

	test_impossible_value_decodes_as_invalid
			-- cpu.busy_pct = 250% in a damaged file: the frame decodes, the reading is invalid.
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
		do
			create l_codec.make
			l_codec.decode ("TMF1%T" + Base_utc.out + "%T" + (Base_utc + One_second).out + "%T10000000%T4%T0%T0%T1%T0%N"
				+ "R%T1%T%T0%T" + Bits_of_250 + "%N")
			assert_true ("decoded", l_codec.has_frame)
			assert_true ("invalid", l_codec.last_frame.readings.reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "").is_invalid)
		end

	test_activity_lines_counted
		note
			testing: "covers/{TM_FRAME_CODEC}.activity_count_in"
		local
			l_codec: TM_FRAME_CODEC
		do
			create l_codec.make
			assert_integers_equal ("two A lines", 2, l_codec.activity_count_in ("TMF1%T1%NA%Tx%NR%T1%NA%Ty%NB%T1%N"))
			assert_integers_equal ("A inside a field does not count", 0, l_codec.activity_count_in ("TMF1%TA%T1%N"))
		end

	test_capabilities_round_trip
		note
			testing: "covers/{TM_FRAME_CODEC}.encode_capabilities"
		local
			l_codec: TM_FRAME_CODEC
			l_system: TM_SCRIPTED_SYSTEM_SOURCE
			l_caps: TM_CAPABILITIES
		do
			create l_system.make (4)
			l_system.declare_support ({TM_METRICS}.Cpu_package_watts, {TM_READING_STATUS}.Available, {STRING_32} "")
			create l_caps.make (l_system, "native", {STRING_32} "")
			create l_codec.make
			l_codec.decode_capabilities (l_codec.encode_capabilities (l_caps))
			assert_true ("decoded", l_codec.has_capabilities)
			assert_true ("power supported", l_codec.last_capabilities.is_supported ({TM_METRICS}.Cpu_package_watts))
			assert_strings_equal_case_insensitive ("reason kept", "not scripted",
				l_codec.last_capabilities.reason_of ({TM_METRICS}.Temperature_c))
		end

	test_round_trip_with_activities
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
			l_frame: TM_FRAME
		do
			create l_codec.make
			l_frame := built (
				snapshot (Base_utc, 0, <<sample (100, Base_utc, {STRING_32} "tab%Tand\slash.exe", 0, 4096, 0),
					sample (200, Base_utc, {STRING_32} "gone.exe", 0, 1, 0)>>),
				snapshot (Base_utc + One_second, One_second, <<sample (100, Base_utc, {STRING_32} "tab%Tand\slash.exe", One_second // 3, 8192, 1000),
					sample (300, Base_utc + 5, {STRING_32} "new.exe", 0, 1, 0)>>), True)
			l_codec.decode (l_codec.encode (l_frame))
			assert_true ({STRING_32} "decoded: " + l_codec.last_error, l_codec.has_frame)
			assert_integers_equal ("activities", 2, l_codec.last_frame.activity_count)
			assert_integers_equal ("born", 1, l_codec.last_frame.born.count)
			assert_integers_equal ("exited", 1, l_codec.last_frame.exited.count)
			assert_true ("clock flag kept", l_codec.last_frame.is_clock_adjusted)
			assert_true ("name with a tab and a backslash survives",
				l_codec.last_frame.activity (id (100, Base_utc)).name.same_string ({STRING_32} "tab%Tand\slash.exe"))
			assert_true ("cores bit-exact", l_codec.last_frame.activity (id (100, Base_utc)).cpu_cores
				= l_frame.activity (id (100, Base_utc)).cpu_cores)
			assert_true ("newcomer has no rate", not l_codec.last_frame.activity (id (300, Base_utc + 5)).has_resource ({TM_RESOURCE}.Cpu))
		end

	test_frame_texts_split
		note
			testing: "covers/{TM_FRAME_CODEC}.frame_texts_in"
		local
			l_codec: TM_FRAME_CODEC
			l_file: STRING_8
			l_texts: ARRAYED_LIST [STRING_8]
		do
			create l_codec.make
			l_file := l_codec.encode (frame_with_cpu (Base_utc, 1, 10.0))
				+ l_codec.encode (frame_with_cpu (Base_utc + One_second, 1, 20.0))
				+ l_codec.encode (frame_with_cpu (Base_utc + 2 * One_second, 1, 30.0))
			l_texts := l_codec.frame_texts_in (l_file)
			assert_integers_equal ("three frames", 3, l_texts.count)
			l_codec.decode (l_texts [3])
			assert_reals_equal ("third in order", 30.0,
				l_codec.last_frame.readings.reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "").value, 0.0)
		end

feature {NONE} -- Fixtures

	Bits_of_250: STRING_8 = "406F400000000000"
			-- IEEE 754 image of 250.0: exponent 1030 (0x406), mantissa 0.953125 (0xF4...).

end
