note
	description: "[
		The signed-in sessions for the Users tab: id, user, state
		(WTSEnumerateSessionsW and WTSQuerySessionInformationW from
		wtsapi32.dll, loaded on use), plus each session's totals from a
		frame: processes, CPU, private memory, disk. Disconnect and sign out
		return a TM_ACTION_RESULT; Windows refuses other users' sessions
		without administrator rights, and the result says so.
	]"
	author: "Larry Rix"

class
	TM_SESSION_LIST

create
	make

feature {NONE} -- Initialization

	make
		do
			create sessions.make (4)
		ensure
			empty: sessions.is_empty
		end

feature -- Access

	sessions: ARRAYED_LIST [TM_SESSION]

	current_session: INTEGER
			-- This program's session.
		do
			Result := c_current_session
		end

feature -- Element change

	refresh (a_frame: detachable TM_FRAME)
			-- List the sessions again, with totals from `a_frame' when given.
		local
			l_buffer: MANAGED_POINTER
			l_count, i, l_base: INTEGER
			l_session: TM_SESSION
		do
			sessions.wipe_out
			create l_buffer.make (Entry_size * Max_sessions)
			l_count := c_sessions (l_buffer.item, Max_sessions)
			from i := 0 until i >= l_count loop
				l_base := i * Entry_size
				create l_session.make (l_buffer.read_integer_32 (l_base), l_buffer.read_integer_32 (l_base + 4),
					wide (l_buffer, l_base + 16, l_buffer.read_integer_32 (l_base + 8).max (0).min (255)))
				if attached a_frame as al_frame then
					across al_frame.activities as ic loop
						if ic.session = l_session.id then
							l_session.add_activity (ic)
						end
					end
				end
				if not l_session.user.is_empty or l_session.process_count > 0 then
					sessions.extend (l_session)
				end
				i := i + 1
			end
		end

	disconnect (a_session: TM_SESSION): TM_ACTION_RESULT
		do
			Result := worded ({STRING_32} "Disconnect " + a_session.user, c_act (a_session.id, 1))
		end

	sign_out (a_session: TM_SESSION): TM_ACTION_RESULT
		do
			Result := worded ({STRING_32} "Sign out " + a_session.user, c_act (a_session.id, 2))
		end

feature {NONE} -- Implementation

	Max_sessions: INTEGER = 64
	Entry_size: INTEGER = 528
			-- id + state + name length + pad + 256 UTF-16 units of DOMAIN\user.

	worded (a_action: STRING_32; a_error: INTEGER): TM_ACTION_RESULT
		do
			inspect a_error
			when 0 then
				create Result.make_done (a_action, 0)
			when 5 then
				create Result.make_refused (a_action, {STRING_32} "access denied (run as administrator to act on other users)")
			when -2 then
				create Result.make_refused (a_action, {STRING_32} "Remote Desktop services are not available here")
			else
				create Result.make_refused (a_action, {STRING_32} "Windows error " + a_error.out.to_string_32)
			end
		end

	wide (a_buffer: MANAGED_POINTER; a_offset, a_count: INTEGER): STRING_32
		local
			i: INTEGER
		do
			create Result.make (a_count)
			from i := 0 until i = a_count loop
				Result.append_code (a_buffer.read_natural_16 (a_offset + i * 2).to_natural_32)
				i := i + 1
			end
		end

	c_current_session: INTEGER
		external
			"C inline use <windows.h>"
		alias
			"[
				DWORD l_session = 0;
				ProcessIdToSessionId (GetCurrentProcessId (), &l_session);
				return (EIF_INTEGER) l_session;
			]"
		end

	c_sessions (a_buffer: POINTER; a_max: INTEGER): INTEGER
			-- Sessions into 528-byte entries; their number (0 when wtsapi32 is missing).
		external
			"C inline use <windows.h>"
		alias
			"[
				typedef struct { DWORD SessionId; LPWSTR pWinStationName; int State; } tm_session_info;
				typedef BOOL (WINAPI *tm_enum) (HANDLE, DWORD, DWORD, tm_session_info **, DWORD *);
				typedef BOOL (WINAPI *tm_query) (HANDLE, DWORD, int, LPWSTR *, DWORD *);
				typedef void (WINAPI *tm_free) (PVOID);
				static HMODULE l_module = NULL;
				tm_enum l_enum; tm_query l_query; tm_free l_free;
				tm_session_info *l_list = NULL;
				DWORD l_count = 0, i;
				int l_out = 0;
				if (l_module == NULL) l_module = LoadLibraryW (L"wtsapi32.dll");
				if (l_module == NULL) return 0;
				l_enum = (tm_enum) GetProcAddress (l_module, "WTSEnumerateSessionsW");
				l_query = (tm_query) GetProcAddress (l_module, "WTSQuerySessionInformationW");
				l_free = (tm_free) GetProcAddress (l_module, "WTSFreeMemory");
				if (l_enum == NULL || l_query == NULL || l_free == NULL) return 0;
				if (!l_enum (NULL, 0, 1, &l_list, &l_count)) return 0;
				for (i = 0; i < l_count && l_out < $a_max; i++) {
					BYTE *l_entry = ((BYTE *) $a_buffer) + l_out * 528;
					LPWSTR l_user = NULL, l_domain = NULL;
					DWORD l_bytes = 0;
					int l_length = 0;
					*((int *) l_entry) = (int) l_list [i].SessionId;
					*((int *) (l_entry + 4)) = l_list [i].State;
					if (l_query (NULL, l_list [i].SessionId, 5, &l_user, &l_bytes) && l_user != NULL && l_user [0] != 0) {
						WCHAR *l_name = (WCHAR *) (l_entry + 16);
						if (l_query (NULL, l_list [i].SessionId, 7, &l_domain, &l_bytes) && l_domain != NULL && l_domain [0] != 0) {
							int l_d = (int) wcslen (l_domain);
							if (l_d > 120) l_d = 120;
							memcpy (l_name, l_domain, l_d * 2);
							l_name [l_d] = L'\\';
							l_length = l_d + 1;
						}
						{
							int l_u = (int) wcslen (l_user);
							if (l_length + l_u > 255) l_u = 255 - l_length;
							memcpy (l_name + l_length, l_user, l_u * 2);
							l_length += l_u;
						}
					}
					if (l_user != NULL) l_free (l_user);
					if (l_domain != NULL) l_free (l_domain);
					*((int *) (l_entry + 8)) = l_length;
					l_out++;
				}
				l_free (l_list);
				return (EIF_INTEGER) l_out;
			]"
		end

	c_act (a_session, a_verb: INTEGER): INTEGER
			-- Disconnect (1) or sign out (2) session `a_session'; 0, -2 when unavailable, or the Windows error.
		external
			"C inline use <windows.h>"
		alias
			"[
				typedef BOOL (WINAPI *tm_act) (HANDLE, DWORD, BOOL);
				HMODULE l_module = LoadLibraryW (L"wtsapi32.dll");
				tm_act l_act;
				if (l_module == NULL) return -2;
				l_act = (tm_act) GetProcAddress (l_module, ($a_verb == 1) ? "WTSDisconnectSession" : "WTSLogoffSession");
				if (l_act == NULL) return -2;
				if (!l_act (NULL, (DWORD) $a_session, FALSE)) return (EIF_INTEGER) GetLastError ();
				return 0;
			]"
		end

end
