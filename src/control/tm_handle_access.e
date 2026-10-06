note
	description: "[
		Opening a process by identity, not by pid: OpenProcess, then the
		creation time must match the identity, or the handle is closed and
		the open fails with Error_identity_mismatch. Shared by the inspector
		and the controls, so no action ever lands on a reused pid.
	]"
	author: "Larry Rix"

class
	TM_HANDLE_ACCESS

feature -- Constants

	Process_terminate: INTEGER = 0x0001
	Process_set_information: INTEGER = 0x0200
	Process_query_limited: INTEGER = 0x1000
	Error_access_denied: INTEGER = 5
	Error_invalid_parameter: INTEGER = 87
	Error_identity_mismatch: INTEGER = 0x20000001
			-- Our code: the pid now belongs to a process with another creation time.

feature {NONE} -- Externals

	c_open_checked (a_pid, a_creation: INTEGER_64; a_access: INTEGER; a_error: POINTER): POINTER
			-- OpenProcess with `a_access' (plus query-limited), then confirm the creation time; NULL with the reason in `a_error' otherwise.
		external
			"C inline use <windows.h>"
		alias
			"[
				FILETIME l_creation, l_exit, l_kernel, l_user;
				ULARGE_INTEGER l_value;
				HANDLE l_handle = OpenProcess ((DWORD) $a_access | 0x1000, FALSE, (DWORD) $a_pid);
				if (l_handle == NULL) { *((DWORD *) $a_error) = GetLastError (); return NULL; }
				if (!GetProcessTimes (l_handle, &l_creation, &l_exit, &l_kernel, &l_user)) {
					*((DWORD *) $a_error) = GetLastError (); CloseHandle (l_handle); return NULL;
				}
				l_value.LowPart = l_creation.dwLowDateTime; l_value.HighPart = l_creation.dwHighDateTime;
				if ((EIF_INTEGER_64) l_value.QuadPart != $a_creation) {
					*((DWORD *) $a_error) = 0x20000001; CloseHandle (l_handle); return NULL;
				}
				*((DWORD *) $a_error) = 0;
				return (EIF_POINTER) l_handle;
			]"
		end

	c_close (a_handle: POINTER)
			-- CloseHandle.
		external
			"C inline use <windows.h>"
		alias
			"CloseHandle ((HANDLE) $a_handle);"
		end

	open_failure_reason (a_error: INTEGER): STRING_32
			-- Words for an open failure.
		do
			inspect a_error
			when Error_access_denied then
				Result := {STRING_32} "access denied (run as administrator to act on this process)"
			when Error_identity_mismatch, Error_invalid_parameter then
				Result := {STRING_32} "the process has already ended"
			else
				Result := {STRING_32} "Windows error " + a_error.out.to_string_32
			end
		ensure
			worded: not Result.is_empty
		end

end
