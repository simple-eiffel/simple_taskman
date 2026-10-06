note
	description: "[
		The background recorder (taskman_recorder.exe) from the window's side:
		register it to start at logon (a value in your Run key, no admin
		rights), start it now, ask it to stop (a named event it waits on), and
		tell whether one is running (a named mutex it holds while alive).
	]"
	author: "Larry Rix"

class
	TM_RECORDER_CONTROL

feature -- Access

	Run_value_name: STRING_32 = "simple_taskman recorder"

	recorder_path: STRING_32
			-- taskman_recorder.exe beside this program.
		local
			l_buffer: MANAGED_POINTER
			l_count, l_cut, i: INTEGER
			l_self: STRING_32
		do
			create l_buffer.make (2048)
			l_count := c_module_path (l_buffer.item, 1023)
			create l_self.make (l_count)
			from i := 0 until i = l_count loop
				l_self.append_code (l_buffer.read_natural_16 (i * 2).to_natural_32)
				i := i + 1
			end
			l_cut := l_self.last_index_of ({CHARACTER_32} '\', l_self.count)
			Result := l_self.substring (1, l_cut) + {STRING_32} "taskman_recorder.exe"
		end

feature -- Status report

	is_installed: BOOLEAN
			-- Is taskman_recorder.exe beside this program?
		do
			Result := (create {RAW_FILE}.make_with_name (recorder_path)).exists
		end

	is_registered: BOOLEAN
			-- Does your Run key start the recorder at logon?
		local
			l_name: NATIVE_STRING
		do
			create l_name.make (Run_value_name)
			Result := c_has_run_value (l_name.item)
		end

	is_running: BOOLEAN
			-- Is a background recorder alive in this session?
		do
			Result := c_alive_exists
		end

feature -- Element change

	register: TM_ACTION_RESULT
			-- Start the recorder at logon.
		local
			l_name, l_value: NATIVE_STRING
			l_error: INTEGER
		do
			create l_name.make (Run_value_name)
			create l_value.make ({STRING_32} "%"" + recorder_path + {STRING_32} "%"")
			l_error := c_set_run_value (l_name.item, l_value.item)
			if l_error = 0 then
				create Result.make_done ({STRING_32} "Record from logon", 0)
			else
				create Result.make_refused ({STRING_32} "Record from logon", {STRING_32} "Windows error " + l_error.out.to_string_32)
			end
		end

	unregister: TM_ACTION_RESULT
			-- Stop starting the recorder at logon.
		local
			l_name: NATIVE_STRING
			l_error: INTEGER
		do
			create l_name.make (Run_value_name)
			l_error := c_delete_run_value (l_name.item)
			if l_error = 0 or l_error = 2 then
				create Result.make_done ({STRING_32} "Stop recording from logon", 0)
			else
				create Result.make_refused ({STRING_32} "Stop recording from logon", {STRING_32} "Windows error " + l_error.out.to_string_32)
			end
		end

	start: TM_ACTION_RESULT
			-- Start a background recorder now.
		local
			l_command: NATIVE_STRING
		do
			if not is_installed then
				create Result.make_refused ({STRING_32} "Start the background recorder", {STRING_32} "taskman_recorder.exe is not beside taskman.exe")
			elseif is_running then
				create Result.make_done ({STRING_32} "Start the background recorder (already running)", 0)
			else
				create l_command.make ({STRING_32} "%"" + recorder_path + {STRING_32} "%"")
				if c_spawn (l_command.item) then
					create Result.make_done ({STRING_32} "Start the background recorder", 0)
				else
					create Result.make_refused ({STRING_32} "Start the background recorder", {STRING_32} "Windows could not start it")
				end
			end
		end

	request_stop
			-- Ask a running recorder to finish its frame, commit, and exit.
		do
			c_signal_stop
		end

feature {NONE} -- Externals

	c_module_path (a_buffer: POINTER; a_capacity: INTEGER): INTEGER
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_INTEGER) GetModuleFileNameW (NULL, (LPWSTR) $a_buffer, (DWORD) $a_capacity);"
		end

	c_has_run_value (a_name: POINTER): BOOLEAN
		external
			"C inline use <windows.h>"
		alias
			"[
				DWORD l_size = 0;
				return (EIF_BOOLEAN) (RegGetValueW (HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
					(LPCWSTR) $a_name, RRF_RT_REG_SZ, NULL, NULL, &l_size) == ERROR_SUCCESS);
			]"
		end

	c_set_run_value (a_name, a_value: POINTER): INTEGER
		external
			"C inline use <windows.h>"
		alias
			"[
				HKEY l_key;
				LONG l_status = RegOpenKeyExW (HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_SET_VALUE, &l_key);
				if (l_status != ERROR_SUCCESS) return (EIF_INTEGER) l_status;
				l_status = RegSetValueExW (l_key, (LPCWSTR) $a_name, 0, REG_SZ, (const BYTE *) $a_value,
					(DWORD) ((wcslen ((LPCWSTR) $a_value) + 1) * 2));
				RegCloseKey (l_key);
				return (EIF_INTEGER) l_status;
			]"
		end

	c_delete_run_value (a_name: POINTER): INTEGER
		external
			"C inline use <windows.h>"
		alias
			"[
				HKEY l_key;
				LONG l_status = RegOpenKeyExW (HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_SET_VALUE, &l_key);
				if (l_status != ERROR_SUCCESS) return (EIF_INTEGER) l_status;
				l_status = RegDeleteValueW (l_key, (LPCWSTR) $a_name);
				RegCloseKey (l_key);
				return (EIF_INTEGER) l_status;
			]"
		end

	c_alive_exists: BOOLEAN
		external
			"C inline use <windows.h>"
		alias
			"[
				HANDLE l_mutex = OpenMutexW (SYNCHRONIZE, FALSE, L"Local\\simple_taskman.recorder.alive");
				if (l_mutex == NULL) return EIF_FALSE;
				CloseHandle (l_mutex);
				return EIF_TRUE;
			]"
		end

	c_signal_stop
		external
			"C inline use <windows.h>"
		alias
			"[
				HANDLE l_event = OpenEventW (EVENT_MODIFY_STATE, FALSE, L"Local\\simple_taskman.recorder.stop");
				if (l_event != NULL) { SetEvent (l_event); CloseHandle (l_event); }
			]"
		end

	c_spawn (a_command: POINTER): BOOLEAN
		external
			"C inline use <windows.h>"
		alias
			"[
				STARTUPINFOW l_startup;
				PROCESS_INFORMATION l_info;
				ZeroMemory (&l_startup, sizeof (l_startup));
				l_startup.cb = sizeof (l_startup);
				if (!CreateProcessW (NULL, (LPWSTR) $a_command, NULL, NULL, FALSE, DETACHED_PROCESS, NULL, NULL, &l_startup, &l_info)) return EIF_FALSE;
				CloseHandle (l_info.hThread);
				CloseHandle (l_info.hProcess);
				return EIF_TRUE;
			]"
		end

end
