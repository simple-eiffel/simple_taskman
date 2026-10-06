note
	description: "[
		The Windows services (Service Control Manager): `refresh' lists them
		with their process and state (EnumServicesStatusExW) and start type
		(QueryServiceConfigW, read on the first refresh and remembered per
		name: it rarely changes). Start, stop, and restart return a
		TM_ACTION_RESULT; without administrator rights Windows usually
		refuses, and the result says so. Restart is two steps: `restart' asks
		the service to stop, and a later `refresh' starts it once it has
		stopped, so the window never waits on a slow service.
	]"
	author: "Larry Rix"

class
	TM_SERVICE_TABLE

create
	make

feature {NONE} -- Initialization

	make
			-- Empty table; `refresh' fills it.
		do
			create services.make (300)
			create start_types.make (300)
			create pending_restarts.make (4)
			create last_error.make_empty
		ensure
			empty: services.is_empty
		end

feature -- Access

	services: ARRAYED_LIST [TM_SERVICE]
			-- Every service, in the order Windows lists them.

	last_error: STRING_32
			-- Why the last refresh failed; empty after a success.

	service_named (a_name: READABLE_STRING_32): detachable TM_SERVICE
			-- The listed service called `a_name' (any case).
		do
			across services as ic loop
				if Result = Void and then ic.name.is_case_insensitive_equal (a_name) then
					Result := ic
				end
			end
		end

	description (a_name: READABLE_STRING_32): STRING_32
			-- The service's description; empty when there is none, it cannot be read, or it is an unresolved resource reference.
		require
			named: not a_name.is_empty
		local
			l_name: NATIVE_STRING
			l_buffer: MANAGED_POINTER
			l_count: INTEGER
		do
			create Result.make_empty
			create l_name.make (a_name)
			create l_buffer.make (4096)
			l_count := c_description (l_name.item, l_buffer.item, 2047)
			if l_count > 0 then
				Result := wide (l_buffer, 0, l_count)
				if Result.starts_with ({STRING_32} "@") then
					Result.wipe_out
				end
			end
		end

	restart_pending (a_name: READABLE_STRING_32): BOOLEAN
			-- Is a restart of `a_name' waiting for it to stop?
		do
			Result := across pending_restarts as ic some ic.is_case_insensitive_equal (a_name) end
		end

feature -- Element change

	refresh
			-- List the services again; start any whose restart is pending and that has stopped.
		local
			l_buffer: MANAGED_POINTER
			l_count, i, l_base, l_type: INTEGER
			l_name: STRING_32
			l_done: ARRAYED_LIST [STRING_32]
			l_result: TM_ACTION_RESULT
		do
			last_error.wipe_out
			create l_buffer.make (Entry_size * Max_services)
			l_count := c_enumerate (l_buffer.item, Max_services, start_types.is_empty)
			if l_count < 0 then
				last_error.append ({STRING_32} "the service list could not be read (Windows error " + (- l_count).out.to_string_32 + {STRING_32} ")")
			else
				services.wipe_out
				from i := 0 until i = l_count loop
					l_base := i * Entry_size
					l_name := wide (l_buffer, l_base, l_buffer.read_integer_32 (l_base + 780).max (0).min (127))
					if not l_name.is_empty then
						l_type := l_buffer.read_integer_32 (l_base + 776)
						if l_type >= 0 then
							start_types.force (l_type, l_name.as_lower)
						elseif start_types.has (l_name.as_lower) then
							l_type := start_types.item (l_name.as_lower)
						end
						services.extend (create {TM_SERVICE}.make (l_name,
							wide (l_buffer, l_base + 256, l_buffer.read_integer_32 (l_base + 784).max (0).min (255)),
							l_buffer.read_natural_32 (l_base + 768).to_integer_64, l_buffer.read_integer_32 (l_base + 772), l_type))
					end
					i := i + 1
				end
				create l_done.make (2)
				across pending_restarts as ic loop
					if attached service_named (ic) as al_service and then al_service.is_stopped then
						l_result := start (ic)
						l_done.extend (ic)
					end
				end
				across l_done as ic loop
					pending_restarts.prune_all (ic)
				end
			end
		end

	start (a_name: READABLE_STRING_32): TM_ACTION_RESULT
			-- Ask Windows to start service `a_name'.
		require
			named: not a_name.is_empty
		do
			Result := control_result ({STRING_32} "Start " + a_name, a_name, 1)
		end

	stop (a_name: READABLE_STRING_32): TM_ACTION_RESULT
			-- Ask Windows to stop service `a_name'.
		require
			named: not a_name.is_empty
		do
			Result := control_result ({STRING_32} "Stop " + a_name, a_name, 2)
		end

	restart (a_name: READABLE_STRING_32): TM_ACTION_RESULT
			-- Stop `a_name' now and start it once a refresh sees it stopped.
		require
			named: not a_name.is_empty
		do
			Result := control_result ({STRING_32} "Restart " + a_name, a_name, 2)
			if Result.succeeded and not restart_pending (a_name) then
				pending_restarts.extend (create {STRING_32}.make_from_string (a_name))
			end
		ensure
			pending_when_stopping: Result.succeeded implies restart_pending (a_name)
		end

feature {NONE} -- Implementation

	start_types: HASH_TABLE [INTEGER, STRING_32]
			-- Start type by lower-case name; read once.

	pending_restarts: ARRAYED_LIST [STRING_32]

	Max_services: INTEGER = 1024
	Entry_size: INTEGER = 800
			-- name (128 UTF-16 units) + display name (256) + pid + state + start type + name length + display length.

	control_result (a_action, a_name: READABLE_STRING_32; a_verb: INTEGER): TM_ACTION_RESULT
			-- Run start (1) or stop (2) on `a_name' and word the outcome.
		local
			l_name: NATIVE_STRING
			l_error: INTEGER
		do
			create l_name.make (a_name)
			l_error := c_control (l_name.item, a_verb)
			inspect l_error
			when 0 then
				create Result.make_done (a_action, 0)
			when 5 then
				create Result.make_refused (a_action, {STRING_32} "access denied (run as administrator to control services)")
			when 1060 then
				create Result.make_refused (a_action, {STRING_32} "there is no such service")
			when 1056 then
				create Result.make_refused (a_action, {STRING_32} "it is already running")
			when 1062 then
				create Result.make_refused (a_action, {STRING_32} "it is not running")
			when 1052 then
				create Result.make_refused (a_action, {STRING_32} "this service cannot be stopped")
			when 1051 then
				create Result.make_refused (a_action, {STRING_32} "other running services depend on it")
			when 1058 then
				create Result.make_refused (a_action, {STRING_32} "it is disabled")
			else
				create Result.make_refused (a_action, {STRING_32} "Windows error " + l_error.out.to_string_32)
			end
		end

	wide (a_buffer: MANAGED_POINTER; a_offset, a_count: INTEGER): STRING_32
			-- `a_count' UTF-16 units of `a_buffer' from byte `a_offset'.
		require
			fits: a_offset >= 0 and a_count >= 0 and a_offset + a_count * 2 <= a_buffer.count
		local
			i: INTEGER
		do
			create Result.make (a_count)
			from i := 0 until i = a_count loop
				Result.append_code (a_buffer.read_natural_16 (a_offset + i * 2).to_natural_32)
				i := i + 1
			end
		end

	c_enumerate (a_buffer: POINTER; a_max: INTEGER; a_with_config: BOOLEAN): INTEGER
			-- Fill `a_buffer' with up to `a_max' 800-byte entries; their number, or minus the Windows error.
		external
			"C inline use <windows.h>"
		alias
			"[
				SC_HANDLE l_scm = OpenSCManagerW (NULL, NULL, SC_MANAGER_CONNECT | SC_MANAGER_ENUMERATE_SERVICE);
				DWORD l_needed = 0, l_returned = 0, l_resume = 0, i;
				BYTE *l_raw;
				ENUM_SERVICE_STATUS_PROCESSW *l_entries;
				if (l_scm == NULL) return - (int) GetLastError ();
				EnumServicesStatusExW (l_scm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_STATE_ALL, NULL, 0, &l_needed, &l_returned, &l_resume, NULL);
				l_raw = (BYTE *) HeapAlloc (GetProcessHeap (), 0, l_needed + 8192);
				if (l_raw == NULL) { CloseServiceHandle (l_scm); return -8; }
				l_resume = 0;
				if (!EnumServicesStatusExW (l_scm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_STATE_ALL, l_raw, l_needed + 8192,
						&l_needed, &l_returned, &l_resume, NULL)) {
					DWORD l_error = GetLastError ();
					HeapFree (GetProcessHeap (), 0, l_raw); CloseServiceHandle (l_scm); return - (int) l_error;
				}
				l_entries = (ENUM_SERVICE_STATUS_PROCESSW *) l_raw;
				for (i = 0; i < l_returned && (int) i < $a_max; i++) {
					BYTE *l_entry = ((BYTE *) $a_buffer) + i * 800;
					int l_name_length = (int) wcslen (l_entries [i].lpServiceName);
					int l_display_length = (int) wcslen (l_entries [i].lpDisplayName);
					if (l_name_length > 127) l_name_length = 127;
					if (l_display_length > 255) l_display_length = 255;
					memcpy (l_entry, l_entries [i].lpServiceName, l_name_length * 2);
					memcpy (l_entry + 256, l_entries [i].lpDisplayName, l_display_length * 2);
					*((DWORD *) (l_entry + 768)) = l_entries [i].ServiceStatusProcess.dwProcessId;
					*((int *) (l_entry + 772)) = (int) l_entries [i].ServiceStatusProcess.dwCurrentState;
					*((int *) (l_entry + 776)) = -1;
					*((int *) (l_entry + 780)) = l_name_length;
					*((int *) (l_entry + 784)) = l_display_length;
					if ($a_with_config) {
						SC_HANDLE l_service = OpenServiceW (l_scm, l_entries [i].lpServiceName, SERVICE_QUERY_CONFIG);
						if (l_service != NULL) {
							DWORD l_config_needed = 0;
							QueryServiceConfigW (l_service, NULL, 0, &l_config_needed);
							if (l_config_needed > 0 && l_config_needed <= 8192) {
								BYTE l_config [8192];
								if (QueryServiceConfigW (l_service, (LPQUERY_SERVICE_CONFIGW) l_config, sizeof (l_config), &l_config_needed)) {
									*((int *) (l_entry + 776)) = (int) ((LPQUERY_SERVICE_CONFIGW) l_config)->dwStartType;
								}
							}
							CloseServiceHandle (l_service);
						}
					}
				}
				HeapFree (GetProcessHeap (), 0, l_raw);
				CloseServiceHandle (l_scm);
				return (EIF_INTEGER) ((int) l_returned < $a_max ? (int) l_returned : $a_max);
			]"
		end

	c_description (a_name, a_buffer: POINTER; a_capacity: INTEGER): INTEGER
			-- Description of service `a_name' into `a_buffer'; its length, 0 when none.
		external
			"C inline use <windows.h>"
		alias
			"[
				SC_HANDLE l_scm = OpenSCManagerW (NULL, NULL, SC_MANAGER_CONNECT);
				SC_HANDLE l_service;
				BYTE l_raw [8192];
				DWORD l_needed = 0;
				int l_length = 0;
				if (l_scm == NULL) return 0;
				l_service = OpenServiceW (l_scm, (LPCWSTR) $a_name, SERVICE_QUERY_CONFIG);
				if (l_service != NULL) {
					if (QueryServiceConfig2W (l_service, SERVICE_CONFIG_DESCRIPTION, l_raw, sizeof (l_raw), &l_needed)) {
						LPWSTR l_text = ((SERVICE_DESCRIPTIONW *) l_raw)->lpDescription;
						if (l_text != NULL) {
							l_length = (int) wcslen (l_text);
							if (l_length > $a_capacity) l_length = $a_capacity;
							memcpy ((void *) $a_buffer, l_text, l_length * 2);
						}
					}
					CloseServiceHandle (l_service);
				}
				CloseServiceHandle (l_scm);
				return (EIF_INTEGER) l_length;
			]"
		end

	c_control (a_name: POINTER; a_verb: INTEGER): INTEGER
			-- Start (1) or stop (2) service `a_name'; 0 or the Windows error.
		external
			"C inline use <windows.h>"
		alias
			"[
				SC_HANDLE l_scm = OpenSCManagerW (NULL, NULL, SC_MANAGER_CONNECT);
				SC_HANDLE l_service;
				SERVICE_STATUS l_status;
				DWORD l_error = 0;
				if (l_scm == NULL) return (EIF_INTEGER) GetLastError ();
				l_service = OpenServiceW (l_scm, (LPCWSTR) $a_name, ($a_verb == 1) ? SERVICE_START : (SERVICE_STOP | SERVICE_QUERY_STATUS));
				if (l_service == NULL) {
					l_error = GetLastError ();
				} else {
					if ($a_verb == 1) {
						if (!StartServiceW (l_service, 0, NULL)) l_error = GetLastError ();
					} else {
						if (!ControlService (l_service, SERVICE_CONTROL_STOP, &l_status)) l_error = GetLastError ();
					}
					CloseServiceHandle (l_service);
				}
				CloseServiceHandle (l_scm);
				return (EIF_INTEGER) l_error;
			]"
		end

invariant
	error_text_exists: last_error /= Void

end
