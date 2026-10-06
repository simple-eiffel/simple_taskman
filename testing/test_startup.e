note
	description: "[
		Phase 3 slice 5: startup apps, measured startup impact, and the
		background recorder's registration. Registry tests use a value named
		simple_taskman_test_item that points at a program that does not
		exist, and remove it (and its StartupApproved value) before and after.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_STARTUP

inherit
	TM_TEST_SET

feature -- Tests: impact

	test_impact_from_recorded_frames
		local
			l_window: TM_WINDOW
			l_impact: TM_STARTUP_IMPACT
			i: INTEGER
		do
			create l_window.make
			from i := 0 until i = 3 loop
				l_window.extend (frame_with_app (Base_utc + i * One_second, 0.5))
				i := i + 1
			end
			create l_impact.make (l_window, {STRING_32} "APP.EXE")
			assert_true ("measured", l_impact.is_measured)
			assert_reals_equal ("1.5 core-seconds", 1.5, l_impact.cpu_seconds, 1.0e-9)
			assert_true ("over 1 s is High", l_impact.band.same_string ({STRING_32} "High"))
		end

	test_impact_without_recording_says_so
		local
			l_impact: TM_STARTUP_IMPACT
		do
			create l_impact.make (create {TM_WINDOW}.make, {STRING_32} "app.exe")
			assert_false ("not measured", l_impact.is_measured)
			assert_true ("worded", l_impact.band.same_string ({STRING_32} "Not measured"))
		end

feature -- Tests: startup list

	test_list_reads_and_toggles_an_entry
		local
			l_list: TM_STARTUP_LIST
			l_result: TM_ACTION_RESULT
		do
			remove_test_entry
			assert_true ("test entry written", c_write_test_run_value)
			create l_list.make
			l_list.refresh
			if attached test_item (l_list) as al_item then
				assert_true ("enabled at first", al_item.is_enabled)
				assert_true ("image parsed", al_item.image_path.same_string ({STRING_32} "C:\simple_taskman_test\none.exe"))
				assert_false ("yours, not machine-wide", al_item.is_machine_wide)
				l_result := l_list.set_enabled (al_item, False)
				assert_true (l_result.summary, l_result.succeeded)
				l_list.refresh
				if attached test_item (l_list) as al_again then
					assert_false ("disabled after toggling", al_again.is_enabled)
					l_result := l_list.set_enabled (al_again, True)
					l_list.refresh
					if attached test_item (l_list) as al_third then
						assert_true ("enabled again", al_third.is_enabled)
					end
				else
					assert_true ("still listed", False)
				end
			else
				assert_true ("test entry listed", False)
			end
			remove_test_entry
		end

	test_every_item_is_named
		local
			l_list: TM_STARTUP_LIST
		do
			create l_list.make
			l_list.refresh
			assert_true ("names and places", across l_list.items as ic all not ic.name.is_empty and not ic.where.is_empty end)
		end

feature -- Tests: background recorder control

	test_recorder_registration_round_trip
		local
			l_control: TM_RECORDER_CONTROL
			l_was: BOOLEAN
			l_result: TM_ACTION_RESULT
		do
			create l_control
			assert_true ("path beside the program", l_control.recorder_path.ends_with ({STRING_32} "taskman_recorder.exe"))
			l_was := l_control.is_registered
			if not l_was then
				l_result := l_control.register
				assert_true (l_result.summary, l_result.succeeded)
				assert_true ("registered", l_control.is_registered)
				l_result := l_control.unregister
				assert_false ("unregistered", l_control.is_registered)
			end
		end

feature {NONE} -- Fixtures

	frame_with_app (a_start: INTEGER_64; a_cores: REAL_64): TM_FRAME
		local
			l_list: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
		do
			create l_list.make (1)
			l_list.extend (create {TM_PROCESS_ACTIVITY}.make_decoded (id (77, 1077), {STRING_32} "app.exe", 4, 1, 4, 10, False, 4,
				{TM_READING_STATUS}.Available, a_cores, {TM_READING_STATUS}.Available, 1_000_000, 1_000_000,
				{TM_READING_STATUS}.Available, 0.0, 0.0))
			create Result.make (a_start, a_start + One_second, One_second, 4, False, create {TM_READINGS}.make, l_list,
				create {ARRAYED_LIST [TM_PROCESS_ID]}.make (0), create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0))
		end

	test_item (a_list: TM_STARTUP_LIST): detachable TM_STARTUP_ITEM
		do
			across a_list.items as ic loop
				if ic.name.same_string ({STRING_32} "simple_taskman_test_item") then
					Result := ic
				end
			end
		end

	remove_test_entry
		do
			c_remove_test_values
		end

	c_write_test_run_value: BOOLEAN
		external
			"C inline use <windows.h>"
		alias
			"[
				HKEY l_key;
				const WCHAR *l_value = L"\"C:\\simple_taskman_test\\none.exe\" --never";
				LONG l_status = RegOpenKeyExW (HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_SET_VALUE, &l_key);
				if (l_status != ERROR_SUCCESS) return EIF_FALSE;
				l_status = RegSetValueExW (l_key, L"simple_taskman_test_item", 0, REG_SZ, (const BYTE *) l_value, (DWORD) ((wcslen (l_value) + 1) * 2));
				RegCloseKey (l_key);
				return (EIF_BOOLEAN) (l_status == ERROR_SUCCESS);
			]"
		end

	c_remove_test_values
		external
			"C inline use <windows.h>"
		alias
			"[
				HKEY l_key;
				if (RegOpenKeyExW (HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_SET_VALUE, &l_key) == ERROR_SUCCESS) {
					RegDeleteValueW (l_key, L"simple_taskman_test_item"); RegCloseKey (l_key);
				}
				if (RegOpenKeyExW (HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run", 0, KEY_SET_VALUE, &l_key) == ERROR_SUCCESS) {
					RegDeleteValueW (l_key, L"simple_taskman_test_item"); RegCloseKey (l_key);
				}
			]"
		end

end
