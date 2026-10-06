note
	description: "[
		Reads TM_PROCESS_DETAILS for a process identity. Every open checks the
		process's creation time against the identity first, so a pid that
		passed to another process reads as gone, never as the newcomer.

		Windows 10 APIs (IsWow64Process2, GetProcessInformation for power
		throttling, IsProcessCritical, NtQueryInformationProcess for the
		command line) are found with GetProcAddress and local declarations:
		F_code big files can see simple_shell.h's lower _WIN32_WINNT, under
		which those declarations disappear (spike O-2 finding). A missing
		entry point reads as "not supported", never as a value.
	]"
	author: "Larry Rix"

class
	TM_PROCESS_INSPECTOR

inherit
	TM_HANDLE_ACCESS

create
	make

feature {NONE} -- Initialization

	make
			-- Inspector with an empty path cache.
		do
			create path_cache.make (512)
		ensure
			empty_cache: path_cache.is_empty
		end

feature -- Access

	details (a_id: TM_PROCESS_ID): TM_PROCESS_DETAILS
			-- What can be read about `a_id' now.
		require
			not_idle: not a_id.is_idle_pseudo_process
		local
			l_handle: POINTER
			l_error: MANAGED_POINTER
			l_buffer: MANAGED_POINTER
			l_flags: MANAGED_POINTER
			l_count: INTEGER
		do
			create Result.make (a_id)
			create l_error.make (4)
			l_handle := c_open_checked (a_id.pid, a_id.creation_ticks, Process_query_limited, l_error.item)
			if l_handle = default_pointer then
				inspect l_error.read_integer_32 (0)
				when Error_access_denied then
					Result.deny_all ({TM_READING_STATUS}.Access_denied)
				when Error_identity_mismatch, Error_invalid_parameter then
					Result.set_gone
				else
					Result.deny_all ({TM_READING_STATUS}.Unavailable)
				end
			else
				create l_buffer.make (Text_capacity * 2)
				create l_flags.make (8)
				l_count := c_image_path (l_handle, l_buffer.item, Text_capacity)
				if l_count > 0 then
					Result.set_image_path (wide_text (l_buffer, l_count))
				else
					Result.deny_field (1, {TM_READING_STATUS}.Unavailable)
				end
				l_count := c_command_line (l_handle, l_buffer.item, Text_capacity)
				if l_count >= 0 then
					Result.set_command_line (wide_text (l_buffer, l_count))
				else
					Result.deny_field (2, status_of (l_count))
				end
				l_count := c_user_and_elevation (l_handle, l_buffer.item, Text_capacity, l_flags.item)
				if l_count > 0 then
					Result.set_user_name (wide_text (l_buffer, l_count))
					Result.set_elevated (l_flags.read_integer_32 (0) /= 0)
				else
					Result.deny_field (3, status_of (l_count))
					Result.deny_field (4, status_of (l_count))
				end
				l_count := c_architecture (l_handle)
				if l_count > 0 then
					Result.set_architecture (architecture_name (l_count))
				else
					Result.deny_field (5, status_of (l_count))
				end
				l_count := c_priority_class (l_handle)
				if (create {TM_PRIORITY}).is_known (l_count) then
					Result.set_priority_class (l_count)
				else
					Result.deny_field (6, {TM_READING_STATUS}.Unavailable)
				end
				l_count := c_efficiency_mode (l_handle)
				if l_count >= 0 then
					Result.set_efficiency_mode (l_count = 1)
				else
					Result.deny_field (7, status_of (l_count))
				end
				l_count := c_critical (l_handle)
				if l_count >= 0 then
					Result.set_critical (l_count = 1)
				else
					Result.deny_field (8, status_of (l_count))
				end
				c_close (l_handle)
			end
		ensure
			same_identity: Result.id ~ a_id
		end

	image_path (a_id: TM_PROCESS_ID): STRING_32
			-- `a_id''s image path, remembered per identity (it cannot change); empty when unreadable.
		require
			not_idle: not a_id.is_idle_pseudo_process
		local
			l_handle: POINTER
			l_error, l_buffer: MANAGED_POINTER
			l_count: INTEGER
		do
			if attached path_cache.item (a_id) as al_path then
				Result := al_path
			else
				create Result.make_empty
				create l_error.make (4)
				l_handle := c_open_checked (a_id.pid, a_id.creation_ticks, Process_query_limited, l_error.item)
				if l_handle /= default_pointer then
					create l_buffer.make (Text_capacity * 2)
					l_count := c_image_path (l_handle, l_buffer.item, Text_capacity)
					if l_count > 0 then
						Result := wide_text (l_buffer, l_count)
					end
					c_close (l_handle)
				end
				if path_cache.count >= Cache_limit then
					path_cache.wipe_out
				end
				path_cache.force (Result, a_id)
			end
		ensure
			remembered: path_cache.has (a_id)
		end

feature -- Constants

	Text_capacity: INTEGER = 32_768
			-- Characters read at most (Windows' command-line limit).

	Cache_limit: INTEGER = 4096
			-- Identities remembered before the path cache is cleared.

feature {NONE} -- Implementation

	path_cache: HASH_TABLE [STRING_32, TM_PROCESS_ID]
			-- Image paths by identity; memoization only.

	wide_text (a_buffer: MANAGED_POINTER; a_count: INTEGER): STRING_32
			-- The first `a_count' UTF-16 units of `a_buffer'.
		require
			fits: a_count >= 0 and a_count * 2 <= a_buffer.count
		local
			l_unit, l_next: NATURAL_32
			i: INTEGER
		do
			create Result.make (a_count)
			from i := 0 until i = a_count loop
				l_unit := a_buffer.read_natural_16 (i * 2).to_natural_32
				if l_unit >= 0xD800 and l_unit <= 0xDBFF and i + 1 < a_count then
					l_next := a_buffer.read_natural_16 ((i + 1) * 2).to_natural_32
					if l_next >= 0xDC00 and l_next <= 0xDFFF then
						Result.append_code (0x10000 + ((l_unit - 0xD800) |<< 10) + (l_next - 0xDC00))
						i := i + 1
					else
						Result.append_code (0xFFFD)
					end
				elseif l_unit >= 0xD800 and l_unit <= 0xDFFF then
					Result.append_code (0xFFFD)
				else
					Result.append_code (l_unit)
				end
				i := i + 1
			end
		end

	status_of (a_code: INTEGER): INTEGER
			-- Reading status for a negative result code: -2 not supported, -5 access denied, else unavailable.
		do
			inspect a_code
			when -2 then
				Result := {TM_READING_STATUS}.Not_supported
			when -5 then
				Result := {TM_READING_STATUS}.Access_denied
			else
				Result := {TM_READING_STATUS}.Unavailable
			end
		ensure
			not_available: Result /= {TM_READING_STATUS}.Available
		end

	architecture_name (a_machine: INTEGER): STRING_32
			-- Name of IMAGE_FILE_MACHINE value `a_machine'.
		do
			inspect a_machine
			when 0x8664 then
				Result := {STRING_32} "x64"
			when 0x014C then
				Result := {STRING_32} "x86"
			when 0xAA64 then
				Result := {STRING_32} "ARM64"
			when 0x01C4 then
				Result := {STRING_32} "ARM"
			else
				Result := {STRING_32} "machine " + a_machine.out.to_string_32
			end
		ensure
			named: not Result.is_empty
		end

feature {NONE} -- Externals

	c_image_path (a_handle, a_buffer: POINTER; a_capacity: INTEGER): INTEGER
			-- QueryFullProcessImageNameW into `a_buffer'; its length, or 0.
		external
			"C inline use <windows.h>"
		alias
			"[
				DWORD l_size = (DWORD) $a_capacity;
				if (!QueryFullProcessImageNameW ((HANDLE) $a_handle, 0, (LPWSTR) $a_buffer, &l_size)) return 0;
				return (EIF_INTEGER) l_size;
			]"
		end

	c_command_line (a_handle, a_buffer: POINTER; a_capacity: INTEGER): INTEGER
			-- Command line via NtQueryInformationProcess (class 60); its length, -2 when unsupported, -5 denied, -1 otherwise.
		external
			"C inline use <windows.h>"
		alias
			"[
				typedef LONG (NTAPI *tm_nqip) (HANDLE, ULONG, PVOID, ULONG, PULONG);
				typedef struct { USHORT Length; USHORT MaximumLength; PWSTR Buffer; } tm_ustr;
				static tm_nqip l_query = NULL;
				ULONG l_size = 0;
				LONG l_status;
				BYTE *l_raw;
				tm_ustr *l_text;
				int l_count;
				if (l_query == NULL) l_query = (tm_nqip) GetProcAddress (GetModuleHandleW (L"ntdll.dll"), "NtQueryInformationProcess");
				if (l_query == NULL) return -2;
				l_status = l_query ((HANDLE) $a_handle, 60, NULL, 0, &l_size);
				if (l_size == 0) return (l_status == (LONG) 0xC0000022) ? -5 : -1;
				l_raw = (BYTE *) HeapAlloc (GetProcessHeap (), 0, l_size);
				if (l_raw == NULL) return -1;
				l_status = l_query ((HANDLE) $a_handle, 60, l_raw, l_size, &l_size);
				if (l_status < 0) { HeapFree (GetProcessHeap (), 0, l_raw); return (l_status == (LONG) 0xC0000022) ? -5 : -1; }
				l_text = (tm_ustr *) l_raw;
				l_count = l_text->Length / 2;
				if (l_count > $a_capacity) l_count = $a_capacity;
				memcpy ((void *) $a_buffer, l_text->Buffer, l_count * 2);
				HeapFree (GetProcessHeap (), 0, l_raw);
				return (EIF_INTEGER) l_count;
			]"
		end

	c_user_and_elevation (a_handle, a_buffer: POINTER; a_capacity: INTEGER; a_flags: POINTER): INTEGER
			-- DOMAIN\user of the process token into `a_buffer' and its elevation into `a_flags'; length, -5 denied, -1 otherwise.
			-- Names are resolved on this machine only (LookupAccountSidLocalW: LookupAccountSidW can wait
			-- seconds on the network, which froze the window once, 2026-10-06) and remembered per SID.
			-- Called on one processor only (the window's), so the cache needs no lock.
		external
			"C inline use <windows.h>"
		alias
			"[
				typedef BOOL (WINAPI *tm_lookup) (PSID, LPWSTR, LPDWORD, LPWSTR, LPDWORD, PSID_NAME_USE);
				static tm_lookup l_local = NULL;
				static int l_tried = 0;
				static BYTE l_sids [64][68];
				static WCHAR l_names [64][160];
				static int l_lengths [64];
				static int l_used = 0;
				HANDLE l_token;
				BYTE l_info [256];
				DWORD l_size = 0;
				TOKEN_ELEVATION l_elevation;
				WCHAR l_name [256], l_domain [256];
				DWORD l_name_size = 256, l_domain_size = 256;
				SID_NAME_USE l_use;
				PSID l_sid;
				BOOL l_found;
				int l_count, i;
				if (!OpenProcessToken ((HANDLE) $a_handle, TOKEN_QUERY, &l_token)) return (GetLastError () == ERROR_ACCESS_DENIED) ? -5 : -1;
				if (!GetTokenInformation (l_token, TokenUser, l_info, sizeof (l_info), &l_size)) { CloseHandle (l_token); return -1; }
				*((int *) $a_flags) = 0;
				if (GetTokenInformation (l_token, TokenElevation, &l_elevation, sizeof (l_elevation), &l_size)) {
					*((int *) $a_flags) = (int) l_elevation.TokenIsElevated;
				}
				CloseHandle (l_token);
				l_sid = ((TOKEN_USER *) l_info)->User.Sid;
				for (i = 0; i < l_used; i++) {
					if (EqualSid (l_sid, (PSID) l_sids [i])) {
						if (l_lengths [i] > $a_capacity) return -1;
						memcpy ((void *) $a_buffer, l_names [i], l_lengths [i] * 2);
						return (EIF_INTEGER) l_lengths [i];
					}
				}
				if (!l_tried) {
					l_local = (tm_lookup) GetProcAddress (GetModuleHandleW (L"advapi32.dll"), "LookupAccountSidLocalW");
					l_tried = 1;
				}
				if (l_local != NULL) {
					l_found = l_local (l_sid, l_name, &l_name_size, l_domain, &l_domain_size, &l_use);
				} else {
					l_found = LookupAccountSidW (NULL, l_sid, l_name, &l_name_size, l_domain, &l_domain_size, &l_use);
				}
				if (!l_found) return -1;
				l_count = (int) (l_domain_size + 1 + l_name_size);
				if (l_count > $a_capacity) return -1;
				memcpy ((void *) $a_buffer, l_domain, l_domain_size * 2);
				((WCHAR *) $a_buffer) [l_domain_size] = L'\\';
				memcpy (((WCHAR *) $a_buffer) + l_domain_size + 1, l_name, l_name_size * 2);
				if (l_used < 64 && l_count <= 160 && GetLengthSid (l_sid) <= 68) {
					CopySid (68, (PSID) l_sids [l_used], l_sid);
					memcpy (l_names [l_used], (void *) $a_buffer, l_count * 2);
					l_lengths [l_used] = l_count;
					l_used++;
				}
				return (EIF_INTEGER) l_count;
			]"
		end

	c_architecture (a_handle: POINTER): INTEGER
			-- IMAGE_FILE_MACHINE of the process image (IsWow64Process2); -2 when unsupported, -1 on failure.
		external
			"C inline use <windows.h>"
		alias
			"[
				typedef BOOL (WINAPI *tm_iwp2) (HANDLE, USHORT *, USHORT *);
				static tm_iwp2 l_query = NULL;
				USHORT l_process = 0, l_native = 0;
				if (l_query == NULL) l_query = (tm_iwp2) GetProcAddress (GetModuleHandleW (L"kernel32.dll"), "IsWow64Process2");
				if (l_query == NULL) return -2;
				if (!l_query ((HANDLE) $a_handle, &l_process, &l_native)) return -1;
				return (EIF_INTEGER) ((l_process == 0) ? l_native : l_process);
			]"
		end

	c_priority_class (a_handle: POINTER): INTEGER
			-- GetPriorityClass; 0 on failure.
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_INTEGER) GetPriorityClass ((HANDLE) $a_handle);"
		end

	c_efficiency_mode (a_handle: POINTER): INTEGER
			-- 1 when execution-speed throttling is on, 0 when off; -2 unsupported, -1 on failure.
		external
			"C inline use <windows.h>"
		alias
			"[
				typedef struct { ULONG Version; ULONG ControlMask; ULONG StateMask; } tm_throttle;
				typedef BOOL (WINAPI *tm_gpi) (HANDLE, int, LPVOID, DWORD);
				static tm_gpi l_query = NULL;
				tm_throttle l_state;
				if (l_query == NULL) l_query = (tm_gpi) GetProcAddress (GetModuleHandleW (L"kernel32.dll"), "GetProcessInformation");
				if (l_query == NULL) return -2;
				ZeroMemory (&l_state, sizeof (l_state));
				l_state.Version = 1;
				if (!l_query ((HANDLE) $a_handle, 4, &l_state, sizeof (l_state))) return -1;
				return ((l_state.ControlMask & 1) && (l_state.StateMask & 1)) ? 1 : 0;
			]"
		end

	c_critical (a_handle: POINTER): INTEGER
			-- IsProcessCritical: 1 or 0; -2 unsupported, -1 on failure.
		external
			"C inline use <windows.h>"
		alias
			"[
				typedef BOOL (WINAPI *tm_ipc) (HANDLE, PBOOL);
				static tm_ipc l_query = NULL;
				BOOL l_critical = FALSE;
				if (l_query == NULL) l_query = (tm_ipc) GetProcAddress (GetModuleHandleW (L"kernel32.dll"), "IsProcessCritical");
				if (l_query == NULL) return -2;
				if (!l_query ((HANDLE) $a_handle, &l_critical)) return -1;
				return l_critical ? 1 : 0;
			]"
		end

invariant
	cache_bounded: path_cache.count <= Cache_limit

end
