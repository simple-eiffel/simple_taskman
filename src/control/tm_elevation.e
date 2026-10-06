note
	description: "[
		Administrator rights (intent v3, D-1): whether this process has them,
		restarting with them (ShellExecuteExW "runas": Windows asks the
		owner), and the switch that makes Ctrl+Shift+Esc open simple_taskman
		instead of Task Manager. The switch is the Image File Execution
		Options "Debugger" value of taskmgr.exe (the Process Explorer method):
		it needs administrator rights, and it is only ever removed when it
		points at a simple_taskman, so another tool's setting is left alone.
	]"
	author: "Larry Rix"

class
	TM_ELEVATION

feature -- Access

	program_path: STRING_32
			-- This program's file.
		local
			l_buffer: MANAGED_POINTER
			l_count, i: INTEGER
		do
			create l_buffer.make (2048)
			l_count := c_module_path (l_buffer.item, 1023)
			create Result.make (l_count.max (0))
			from i := 0 until i >= l_count loop
				Result.append_code (l_buffer.read_natural_16 (i * 2).to_natural_32)
				i := i + 1
			end
		end

feature -- Status report

	is_elevated: BOOLEAN
			-- Does this process run with administrator rights?
		do
			Result := c_is_elevated
		end

	ctrl_shift_esc_target: STRING_32
			-- The program Ctrl+Shift+Esc opens instead of Task Manager; empty when Task Manager.
		local
			l_buffer: MANAGED_POINTER
			l_count, i: INTEGER
		do
			create l_buffer.make (2048)
			l_count := c_read_debugger (l_buffer.item, 1023)
			create Result.make (l_count.max (0))
			from i := 0 until i >= l_count loop
				Result.append_code (l_buffer.read_natural_16 (i * 2).to_natural_32)
				i := i + 1
			end
		end

	is_ctrl_shift_esc_ours: BOOLEAN
			-- Does Ctrl+Shift+Esc open a simple_taskman?
		do
			Result := ctrl_shift_esc_target.as_lower.has_substring ({STRING_32} "taskman.exe")
				and not ctrl_shift_esc_target.as_lower.has_substring ({STRING_32} "\taskmgr.exe")
		end

feature -- Element change

	restart_elevated (a_arguments: READABLE_STRING_32): TM_ACTION_RESULT
			-- Start this program again with administrator rights (Windows asks first).
		local
			l_arguments: NATIVE_STRING
			l_error: INTEGER
		do
			create l_arguments.make (a_arguments)
			l_error := c_run_as (l_arguments.item)
			inspect l_error
			when 0 then
				create Result.make_done ({STRING_32} "Restart as administrator", 0)
			when 1223 then
				create Result.make_refused ({STRING_32} "Restart as administrator", {STRING_32} "the administrator prompt was declined")
			else
				create Result.make_refused ({STRING_32} "Restart as administrator", {STRING_32} "Windows error " + l_error.out.to_string_32)
			end
		end

	set_ctrl_shift_esc (a_on: BOOLEAN; a_program: READABLE_STRING_32): TM_ACTION_RESULT
			-- Make Ctrl+Shift+Esc open `a_program' (on) or Task Manager again (off).
		require
			program_given: a_on implies not a_program.is_empty
		local
			l_value: NATIVE_STRING
			l_error: INTEGER
			l_action: STRING_32
		do
			if a_on then
				l_action := {STRING_32} "Open simple_taskman on Ctrl+Shift+Esc"
			else
				l_action := {STRING_32} "Open Task Manager on Ctrl+Shift+Esc"
			end
			if not is_elevated then
				create Result.make_refused (l_action, {STRING_32} "needs administrator rights: use Restart as administrator first")
			elseif not a_on and not is_ctrl_shift_esc_ours then
				create Result.make_done (l_action + {STRING_32} " (already)", 0)
			else
				create l_value.make ({STRING_32} "%"" + a_program + {STRING_32} "%"")
				l_error := c_write_debugger (l_value.item, a_on)
				if l_error = 0 then
					create Result.make_done (l_action, 0)
				elseif l_error = 5 then
					create Result.make_refused (l_action, {STRING_32} "access denied")
				else
					create Result.make_refused (l_action, {STRING_32} "Windows error " + l_error.out.to_string_32)
				end
			end
		end

feature {NONE} -- Externals

	c_module_path (a_buffer: POINTER; a_capacity: INTEGER): INTEGER
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_INTEGER) GetModuleFileNameW (NULL, (LPWSTR) $a_buffer, (DWORD) $a_capacity);"
		end

	c_is_elevated: BOOLEAN
		external
			"C inline use <windows.h>"
		alias
			"[
				HANDLE l_token;
				TOKEN_ELEVATION l_elevation;
				DWORD l_size = 0;
				BOOL l_result = FALSE;
				if (OpenProcessToken (GetCurrentProcess (), TOKEN_QUERY, &l_token)) {
					if (GetTokenInformation (l_token, TokenElevation, &l_elevation, sizeof (l_elevation), &l_size)) {
						l_result = l_elevation.TokenIsElevated != 0;
					}
					CloseHandle (l_token);
				}
				return (EIF_BOOLEAN) l_result;
			]"
		end

	c_run_as (a_arguments: POINTER): INTEGER
			-- ShellExecuteExW "runas" on this program; 0 or the Windows error (1223 declined).
		external
			"C inline use <windows.h>, <shellapi.h>"
		alias
			"[
				WCHAR l_path [1024];
				SHELLEXECUTEINFOW l_info;
				if (GetModuleFileNameW (NULL, l_path, 1024) == 0) return (EIF_INTEGER) GetLastError ();
				ZeroMemory (&l_info, sizeof (l_info));
				l_info.cbSize = sizeof (l_info);
				l_info.lpVerb = L"runas";
				l_info.lpFile = l_path;
				l_info.lpParameters = (LPCWSTR) $a_arguments;
				l_info.nShow = SW_SHOWNORMAL;
				if (!ShellExecuteExW (&l_info)) return (EIF_INTEGER) GetLastError ();
				return 0;
			]"
		end

	c_read_debugger (a_buffer: POINTER; a_capacity: INTEGER): INTEGER
		external
			"C inline use <windows.h>"
		alias
			"[
				DWORD l_size = (DWORD) ($a_capacity * 2);
				if (RegGetValueW (HKEY_LOCAL_MACHINE,
						L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution Options\\taskmgr.exe",
						L"Debugger", RRF_RT_REG_SZ, NULL, (PVOID) $a_buffer, &l_size) != ERROR_SUCCESS) return 0;
				return (EIF_INTEGER) ((l_size / 2) > 0 ? (l_size / 2) - 1 : 0);
			]"
		end

	c_write_debugger (a_value: POINTER; a_on: BOOLEAN): INTEGER
			-- Set (on) or delete (off) the taskmgr.exe Debugger value; 0 or the Windows error.
		external
			"C inline use <windows.h>"
		alias
			"[
				HKEY l_key;
				LONG l_status = RegCreateKeyExW (HKEY_LOCAL_MACHINE,
					L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution Options\\taskmgr.exe",
					0, NULL, 0, KEY_SET_VALUE | KEY_WOW64_64KEY, NULL, &l_key, NULL);
				if (l_status != ERROR_SUCCESS) return (EIF_INTEGER) l_status;
				if ($a_on) {
					l_status = RegSetValueExW (l_key, L"Debugger", 0, REG_SZ, (const BYTE *) $a_value,
						(DWORD) ((wcslen ((LPCWSTR) $a_value) + 1) * 2));
				} else {
					l_status = RegDeleteValueW (l_key, L"Debugger");
					if (l_status == ERROR_FILE_NOT_FOUND) l_status = ERROR_SUCCESS;
				}
				RegCloseKey (l_key);
				return (EIF_INTEGER) l_status;
			]"
		end

end
