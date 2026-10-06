note
	description: "Phase 3 slice 3: the owner's settings round-trip through TOML, and bad files keep the defaults."
	author: "Larry Rix"
	testing: "covers"

class
	TEST_SETTINGS

inherit
	TM_TEST_SET

feature -- Tests

	test_settings_round_trip
		local
			l_path: STRING_32
			l_out, l_in: TM_SETTINGS
		do
			l_path := scratch_path ({STRING_32} "taskman_settings_test.toml")
			delete_file (l_path)
			create l_out.make
			l_out.set_update_ms (l_out.Low_ms)
			l_out.set_paused (True)
			l_out.set_always_on_top (True)
			l_out.set_start_page ({STRING_32} "Performance")
			l_out.set_records (False)
			l_out.save (l_path)
			assert_string_empty ({STRING_32} "saved: " + l_out.last_error, l_out.last_error)
			create l_in.make
			l_in.load (l_path)
			assert_string_empty ({STRING_32} "loaded: " + l_in.last_error, l_in.last_error)
			assert_integers_equal ("low speed", l_in.Low_ms, l_in.update_ms)
			assert_true ("paused, on top, not recording", l_in.is_paused and l_in.is_always_on_top and not l_in.records)
			assert_true ("start page", l_in.start_page.same_string ({STRING_32} "performance"))
			delete_file (l_path)
		end

	test_missing_file_keeps_defaults
		local
			l_settings: TM_SETTINGS
		do
			create l_settings.make
			l_settings.load (scratch_path ({STRING_32} "taskman_no_such_settings.toml"))
			assert_string_contains ("says why", l_settings.last_error, "no settings file")
			assert_integers_equal ("normal speed", l_settings.Normal_ms, l_settings.update_ms)
			assert_true ("records", l_settings.records)
		end

	test_bad_file_keeps_defaults
		local
			l_path: STRING_32
			l_settings: TM_SETTINGS
		do
			l_path := scratch_path ({STRING_32} "taskman_bad_settings.toml")
			write_file (l_path, "update_ms = 1234567%Nthis is = = not toml [[[%N")
			create l_settings.make
			l_settings.load (l_path)
			assert_integers_equal ("normal speed kept", l_settings.Normal_ms, l_settings.update_ms)
			delete_file (l_path)
		end

end
