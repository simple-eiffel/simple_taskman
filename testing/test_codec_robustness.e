note
	description: "[
		Damaged and hostile TMF1/TMC1 text: the codec never raises, refuses
		what is malformed, and names the line. Every refusal leaves no frame.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_CODEC_ROBUSTNESS

inherit
	TM_TEST_SET

feature -- Tests

	test_garbage_never_raises
		note
			testing: "covers/{TM_FRAME_CODEC}.is_well_formed"
		local
			l_codec: TM_FRAME_CODEC
		do
			create l_codec.make
			across <<"", "TMF1", "%N%N%N", "%T%T%T", "TMF1%T1%T2", "R%T1%T%T0%T0", "TMF1%Ta%Tb%Tc%Td%Te%Tf%Tg%Th%N",
					"%U%U%U", "TMF1%T1%T2%T1%T4%T0%T0%T1%T0%N%NR%T1%T%T0%T0000000000000000%N">> as ic loop
					-- Structure alone may pass (input 7 has nine fields); decode must still refuse.
				l_codec.is_well_formed (ic).do_nothing
				l_codec.decode (ic)
				assert_false ({STRING_32} "no frame from garbage " + @ic.cursor_index.out.to_string_32, l_codec.has_frame)
				assert_string_not_empty ("says why", l_codec.last_error)
			end
		end

	test_wrong_field_count_names_its_line
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
		do
			create l_codec.make
			l_codec.decode (header + a_line (100, "4") + "B%T1%N")
			assert_false ("refused", l_codec.has_frame)
			assert_string_starts_with ("line 3", l_codec.last_error, "line 3")
		end

	test_negative_field_refused
			-- Review issue 11: refused, never clamped.
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
		do
			create l_codec.make
			l_codec.decode (header + a_line (100, "-1"))
			assert_false ("refused", l_codec.has_frame)
			assert_string_starts_with ("line 2", l_codec.last_error, "line 2")
		end

	test_repeated_identity_refused
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
		do
			create l_codec.make
			l_codec.decode (header + a_line (100, "4") + a_line (100, "4"))
			assert_false ("refused", l_codec.has_frame)
			assert_string_contains ("why", l_codec.last_error, "repeated")
		end

	test_idle_activity_refused
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
		do
			create l_codec.make
			l_codec.decode (header + a_line (0, "0"))
			assert_false ("refused", l_codec.has_frame)
			assert_string_contains ("why", l_codec.last_error, "idle")
		end

	test_unknown_metric_and_wrong_instance_refused
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
		do
			create l_codec.make
			l_codec.decode (header + "R%T999%T%T1%T0000000000000000%N")
			assert_string_contains ("unknown code", l_codec.last_error, "unknown metric code")
			l_codec.decode (header + "R%T2%T%T1%T0000000000000000%N")
			assert_string_contains ("per-core metric without instance", l_codec.last_error, "instance")
			l_codec.decode (header + "R%T1%Tcore7%T1%T0000000000000000%N")
			assert_string_contains ("total with an instance", l_codec.last_error, "instance")
			assert_false ("no frame", l_codec.has_frame)
		end

	test_bad_escape_refused
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
			l_line: STRING_8
		do
			create l_codec.make
			l_line := a_line (100, "4")
			l_line.replace_substring_all ("p.exe", "p" + Backslash + "x.exe")
			l_codec.decode (header + l_line)
			assert_false ("refused", l_codec.has_frame)
		end

	test_discontinuity_with_processes_refused
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
		do
			create l_codec.make
			l_codec.decode ("TMF1%T" + Base_utc.out + "%T" + (Base_utc + One_second).out + "%T10000000%T4%T1%T0%T1%T0%N" + a_line (100, "4"))
			assert_false ("refused", l_codec.has_frame)
			assert_string_contains ("why", l_codec.last_error, "discontinuity")
		end

	test_valid_lines_decode
			-- The fixtures above are correct when left undamaged.
		note
			testing: "covers/{TM_FRAME_CODEC}.decode"
		local
			l_codec: TM_FRAME_CODEC
		do
			create l_codec.make
			l_codec.decode (header + a_line (100, "4") + a_line (101, "4") + "B%T101%T" + Base_utc.out + "%N")
			assert_true ({STRING_32} "decoded: " + l_codec.last_error, l_codec.has_frame)
			assert_integers_equal ("two", 2, l_codec.last_frame.activity_count)
			assert_false ("decoded frames are incomplete", l_codec.last_frame.is_complete)
		end

	test_capability_errors_are_separate
			-- Review issue 16: a capability failure leaves the frame error alone.
		note
			testing: "covers/{TM_FRAME_CODEC}.decode_capabilities"
		local
			l_codec: TM_FRAME_CODEC
		do
			create l_codec.make
			l_codec.decode ("not a frame")
			l_codec.decode_capabilities ("TMC1%NM%T1%T0%T%N")
			assert_false ("no kind, refused", l_codec.has_capabilities)
			assert_string_contains ("why", l_codec.last_capabilities_error, "kind")
			assert_string_starts_with ("frame error untouched", l_codec.last_error, "line 1")
			l_codec.decode_capabilities ("TMC1%NM%T1%T0%T%NM%T1%T0%T%NS%Tkind%Tnative%N")
			assert_string_contains ("repeated metric", l_codec.last_capabilities_error, "repeated")
			l_codec.decode_capabilities ("TMC9%N")
			assert_string_starts_with ("wrong header", l_codec.last_capabilities_error, "line 1")
		end

feature {NONE} -- Fixtures

	header: STRING_8
			-- A valid live header line, 4 processors.
		do
			Result := "TMF1%T" + Base_utc.out + "%T" + (Base_utc + One_second).out + "%T10000000%T4%T0%T0%T1%T0%N"
		end

	a_line (a_pid: INTEGER; a_parent: STRING_8): STRING_8
			-- An A line for process `a_pid' with parent field `a_parent'; groups available.
		do
			Result := "A%T" + a_pid.out + "%T" + Base_utc.out + "%Tp.exe%T" + a_parent + "%T1%T8%T100%T0%T0%T"
				+ Zero_bits + "%T0%T4096%T8192%T0%T" + Zero_bits + "%T" + Zero_bits + "%N"
		end

	Zero_bits: STRING_8 = "0000000000000000"
			-- IEEE bits of 0.0.

	Backslash: STRING_8
			-- One backslash, built from its code so no escaping is involved.
		once
			create Result.make_filled ((92).to_character_8, 1)
		end

end
