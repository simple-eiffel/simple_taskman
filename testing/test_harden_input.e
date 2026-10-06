note
	description: "[
		Phase 6 hostile input: names no process should have but some do,
		truncated and corrupted recordings, impossible bit patterns, extreme
		identities, and values at the edge of representation.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_HARDEN_INPUT

inherit
	TM_TEST_SET

feature -- Tests: names

	test_hostile_names_round_trip
			-- Hebrew, an emoji outside the BMP (a surrogate pair in UTF-16), every
			-- escaped character, an empty name, and a 10,000-character name.
		note
			testing: "covers/{TM_FRAME_CODEC}.encode"
		local
			l_names: ARRAYED_LIST [STRING_32]
			l_long: STRING_32
			l_codec: TM_FRAME_CODEC
			l_after: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			l_frame: TM_FRAME
			i: INTEGER
		do
			create l_names.make (5)
			l_names.extend (hebrew + {STRING_32} ".exe")
			l_names.extend ({STRING_32} "rocket-" + create {STRING_32}.make_filled ((0x1F680).to_character_32, 1) + {STRING_32} ".exe")
			l_names.extend ({STRING_32} "a%Tb%Nc%Rd" + backslash + {STRING_32} "e")
			l_names.extend ({STRING_32} "")
			create l_long.make_filled ('x', 10_000)
			l_names.extend (l_long)
			create l_after.make (5)
			across l_names as ic loop
				l_after.extend (sample (@ic.cursor_index + 10, Base_utc, ic, 0, 1, 0))
			end
			l_frame := built (snapshot (Base_utc, 0, no_samples),
				create {TM_SNAPSHOT}.make (Base_utc + One_second, One_second, l_after, sealed_readings), False)
			create l_codec.make
			l_codec.decode (l_codec.encode (l_frame))
			assert_true ({STRING_32} "decoded: " + l_codec.last_error, l_codec.has_frame)
			from i := 1 until i > l_names.count loop
				assert_true ("name " + i.out + " survives",
					l_codec.last_frame.activity (id (i + 10, Base_utc)).name.same_string (l_names [i]))
				i := i + 1
			end
		end

	test_format_never_breaks_on_names
		note
			testing: "covers/{TM_PATHS}.is_plain_name"
		local
			l_paths: TM_PATHS
		do
			create l_paths.make_with_base ({STRING_32} "C:\x")
			assert_false ("only ASCII letters are plain: log file names stay portable", l_paths.is_plain_name (hebrew))
			assert_false ("a path separator is not", l_paths.is_plain_name (backslash))
		end

feature -- Tests: damaged recordings

	test_every_prefix_of_a_frame_is_safe
			-- A recording cut off at any byte decodes or refuses; it never raises.
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
			l_text: STRING_8
			i, l_frames: INTEGER
		do
			create l_codec.make
			l_text := l_codec.encode (small_frame)
			from i := 0 until i > l_text.count loop
				assert_false ("prefix " + i.out + " raises", raises (agent l_codec.decode (l_text.substring (1, i))))
				if l_codec.has_frame then
					l_frames := l_frames + 1
				end
				i := i + 1
			end
			assert_true ("some whole-line prefixes are frames", l_frames > 0)
			assert_true ("the empty prefix is not", not raises (agent l_codec.decode ("")))
		end

	test_every_single_character_corruption_is_safe
			-- Replace each byte in turn with a digit, a letter, a tab, and a newline.
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
			l_text, l_bad: STRING_8
			i: INTEGER
		do
			create l_codec.make
			l_text := l_codec.encode (small_frame)
			from i := 1 until i > l_text.count loop
				across <<'9', 'Z', '%T', '%N', '-'>> as ic loop
					l_bad := l_text.twin
					l_bad [i] := ic
					assert_false ("byte " + i.out + " as " + ic.out + " raises", raises (agent l_codec.decode (l_bad)))
				end
				i := i + 1
			end
		end

	test_impossible_bit_patterns_decode_invalid
			-- NaN, infinities, and a negative percent in a recording become invalid readings.
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
		do
			create l_codec.make
			across <<"7FF8000000000000", "7FF0000000000000", "FFF0000000000000", "BFF0000000000000">> as ic loop
				l_codec.decode (header + "R%T1%T%T0%T" + ic + "%N")
				assert_true ("decodes " + ic, l_codec.has_frame)
				assert_true ("invalid " + ic, l_codec.last_frame.readings.reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "").is_invalid)
			end
		end

	test_extreme_identities
		note
			testing: "covers/{TM_PROCESS_ID}.hash_code"
		local
			l_max: TM_PROCESS_ID
			l_codec: TM_FRAME_CODEC
		do
			create l_max.make ({INTEGER_64}.max_value, {INTEGER_64}.max_value)
			assert_true ("hash of the largest identity", l_max.hash_code >= 0)
			assert_true ("equal to itself", l_max ~ create {TM_PROCESS_ID}.make ({INTEGER_64}.max_value, {INTEGER_64}.max_value))
			create l_codec.make
			l_codec.decode (header + "A%T" + {INTEGER_64}.max_value.out + "%T" + {INTEGER_64}.max_value.out
				+ "%Tbig.exe%T0%T0%T1%T0%T0%T1%T0000000000000000%T1%T0%T0%T1%T0000000000000000%T0000000000000000%N")
			assert_true ({STRING_32} "decoded: " + l_codec.last_error, l_codec.has_frame)
			assert_true ("kept", l_codec.last_frame.has_activity (l_max))
			l_codec.decode (header + "A%T9223372036854775808%T1%Tbig.exe%T0%T0%T1%T0%T0%T1%T0000000000000000%T1%T0%T0%T1%T0000000000000000%T0000000000000000%N")
			assert_false ("one past the largest pid refused", l_codec.has_frame)
		end

feature -- Tests: edge values

	test_negative_zero_and_tiny_values
		note
			testing: "covers/{TM_READING}.make_measured"
		local
			l_format: TM_FORMAT
			l_zero: TM_READING
		do
			create l_format
			l_zero := measured ({TM_METRICS}.Cpu_busy_pct, -0.0)
			assert_true ("negative zero is a real zero", l_zero.is_available)
			assert_strings_equal_case_insensitive ("shown as zero", "0.0%%", l_format.reading_text (l_zero, metric ({TM_METRICS}.Cpu_busy_pct)))
			assert_strings_equal_case_insensitive ("tiny", "0.0 W", l_format.value_text (1.0e-300, "W"))
			assert_strings_equal_case_insensitive ("huge bytes", "1024.0 TB", l_format.bytes ({INTEGER_64} 1_125_899_906_842_624))
		end

	test_top_by_all_ties
		note
			testing: "covers/{TM_FRAME}.top_by"
		local
			l_before, l_after: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			l_frame: TM_FRAME
			l_top: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			i: INTEGER
		do
			create l_before.make (50)
			create l_after.make (50)
			from i := 1 until i > 50 loop
				l_before.extend (sample (i, Base_utc, {STRING_32} "same.exe", 0, 1, 0))
				l_after.extend (sample (i, Base_utc, {STRING_32} "same.exe", 1_000_000, 1, 0))
				i := i + 1
			end
			l_frame := built (create {TM_SNAPSHOT}.make (Base_utc, 0, l_before, sealed_readings),
				create {TM_SNAPSHOT}.make (Base_utc + One_second, One_second, l_after, sealed_readings), False)
			l_top := l_frame.top_by ({TM_RESOURCE}.Cpu, 10)
			assert_integers_equal ("ten of fifty equal", 10, l_top.count)
			assert_integers_equal ("all fifty when asked", 50, l_frame.top_by ({TM_RESOURCE}.Cpu, 50).count)
		end

	test_slot_operations_in_any_order
		note
			testing: "covers/{TM_FRAME_SLOT}.clear"
		local
			l_slot: TM_FRAME_SLOT
		do
			create l_slot.make
			l_slot.clear
			assert_false ("clearing an empty slot is harmless", l_slot.has_frame)
			l_slot.request_stop
			l_slot.request_stop
			l_slot.put_frame ("TMF1%T1")
			assert_true ("a late frame is still kept", l_slot.has_frame)
			l_slot.put_stopped
			l_slot.put_stopped
			assert_integers_equal ("counts", 1, l_slot.deposited)
			assert_integers_equal ("nothing dropped", 0, l_slot.dropped)
		end

	test_facade_closes_twice
		note
			testing: "covers/{SIMPLE_TASKMAN}.close"
		local
			l_tm: SIMPLE_TASKMAN
		do
			create l_tm.make
			l_tm.close
			l_tm.close
			assert_true ("closed", l_tm.is_closed)
		end

feature {NONE} -- Fixtures

	small_frame: TM_FRAME
			-- A frame with readings, a survivor, a newcomer, and an exited process.
		local
			l_readings: TM_READINGS
		do
			create l_readings.make
			l_readings.put ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "", measured ({TM_METRICS}.Cpu_busy_pct, 42.5))
			l_readings.put ({TM_METRICS}.Cpu_core_busy_pct, {STRING_32} "0", measured ({TM_METRICS}.Cpu_core_busy_pct, 7.0))
			l_readings.seal
			Result := built (
				create {TM_SNAPSHOT}.make (Base_utc, 0, <<sample (1, Base_utc, {STRING_32} "a.exe", 0, 10, 0),
					sample (2, Base_utc, {STRING_32} "b.exe", 0, 10, 0)>>, l_readings),
				create {TM_SNAPSHOT}.make (Base_utc + One_second, One_second, <<sample (1, Base_utc, {STRING_32} "a.exe", 100, 20, 30),
					sample (3, Base_utc, {STRING_32} "c.exe", 0, 10, 0)>>, l_readings), True)
		end

	header: STRING_8
			-- A valid live header line.
		do
			Result := "TMF1%T" + Base_utc.out + "%T" + (Base_utc + One_second).out + "%T10000000%T4%T0%T0%T1%T0%N"
		end

	hebrew: STRING_32
			-- The Hebrew word for "process", built from its code points.
		once
			create Result.make (5)
			across <<0x05EA, 0x05D4, 0x05DC, 0x05D9, 0x05DA>> as ic loop
				Result.append_character (ic.to_character_32)
			end
		end

	backslash: STRING_32
			-- One backslash, from its code.
		once
			create Result.make_filled ((92).to_character_32, 1)
		end

end
