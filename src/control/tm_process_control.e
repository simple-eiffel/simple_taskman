note
	description: "[
		Task Manager's process actions, by identity: end task (ask its
		windows to close), end process, end process tree, set priority, and
		efficiency mode. Every action opens the process by identity
		(TM_HANDLE_ACCESS), so a reused pid is never touched, and refuses
		protected system processes: the ones Windows marks critical and the
		core set named in `Protected_names'. A refusal says why; nothing is
		raised. Priority and efficiency changes keep the prior class for undo.
	]"
	author: "Larry Rix"

class
	TM_PROCESS_CONTROL

inherit
	TM_HANDLE_ACCESS

create
	make

feature {NONE} -- Initialization

	make (a_inspector: TM_PROCESS_INSPECTOR)
			-- Controls that read process details through `a_inspector'.
		do
			inspector := a_inspector
		ensure
			kept: inspector = a_inspector
		end

feature -- Access

	inspector: TM_PROCESS_INSPECTOR

	Protected_names: ARRAY [STRING_32]
			-- Processes never acted on, whatever the rights (compared without case).
		once
			Result := <<{STRING_32} "System", {STRING_32} "Registry", {STRING_32} "smss.exe", {STRING_32} "csrss.exe",
				{STRING_32} "wininit.exe", {STRING_32} "services.exe", {STRING_32} "lsass.exe", {STRING_32} "winlogon.exe",
				{STRING_32} "Memory Compression", {STRING_32} "Secure System", {STRING_32} "LsaIso.exe">>
		end

feature -- Status report

	is_protected (a_id: TM_PROCESS_ID; a_name: READABLE_STRING_32): BOOLEAN
			-- Is `a_id' (named `a_name') a process simple_taskman never acts on?
		local
			l_details: TM_PROCESS_DETAILS
		do
			if a_id.pid = 0 or a_id.pid = 4 then
				Result := True
			elseif across Protected_names as ic some ic.is_case_insensitive_equal (a_name) end then
				Result := True
			elseif not a_id.is_idle_pseudo_process then
				l_details := inspector.details (a_id)
				Result := l_details.critical_status = {TM_READING_STATUS}.Available and then l_details.is_critical
			end
		ensure
			system_pids: (a_id.pid = 0 or a_id.pid = 4) implies Result
		end

feature -- Actions

	end_process (a_id: TM_PROCESS_ID; a_name: READABLE_STRING_32): TM_ACTION_RESULT
			-- Terminate `a_id' now (exit code 1).
		require
			not_idle: not a_id.is_idle_pseudo_process
		local
			l_handle: POINTER
			l_error: MANAGED_POINTER
		do
			if is_protected (a_id, a_name) then
				create Result.make_refused ({STRING_32} "End process", Protected_reason)
			else
				create l_error.make (4)
				l_handle := c_open_checked (a_id.pid, a_id.creation_ticks, Process_terminate, l_error.item)
				if l_handle = default_pointer then
					create Result.make_refused ({STRING_32} "End process", open_failure_reason (l_error.read_integer_32 (0)))
				elseif c_terminate (l_handle) then
					c_close (l_handle)
					create Result.make_done ({STRING_32} "End process", 0)
				else
					c_close (l_handle)
					create Result.make_refused ({STRING_32} "End process", {STRING_32} "Windows refused to end it")
				end
			end
		ensure
			protected_refused: is_protected (a_id, a_name) implies not Result.succeeded
		end

	end_task (a_id: TM_PROCESS_ID; a_name: READABLE_STRING_32; a_windows: TM_WINDOW_INDEX): TM_ACTION_RESULT
			-- Ask `a_id''s windows to close (WM_CLOSE), as Task Manager's End task does for an app.
		require
			not_idle: not a_id.is_idle_pseudo_process
		local
			l_handle: POINTER
			l_error: MANAGED_POINTER
			l_asked: INTEGER
		do
			if is_protected (a_id, a_name) then
				create Result.make_refused ({STRING_32} "End task", Protected_reason)
			elseif not a_windows.has_window (a_id.pid) then
				create Result.make_refused ({STRING_32} "End task", {STRING_32} "it has no window to close; use End process")
			else
				create l_error.make (4)
				l_handle := c_open_checked (a_id.pid, a_id.creation_ticks, 0, l_error.item)
				if l_handle = default_pointer then
					create Result.make_refused ({STRING_32} "End task", open_failure_reason (l_error.read_integer_32 (0)))
				else
					c_close (l_handle)
					across a_windows.handles (a_id.pid) as ic loop
						if c_post_close (ic, a_id.pid) then
							l_asked := l_asked + 1
						end
					end
					if l_asked > 0 then
						create Result.make_done ({STRING_32} "End task (asked " + l_asked.out.to_string_32 + {STRING_32} " window(s) to close)", 0)
					else
						create Result.make_refused ({STRING_32} "End task", {STRING_32} "its windows did not accept the request")
					end
				end
			end
		ensure
			protected_refused: is_protected (a_id, a_name) implies not Result.succeeded
		end

	end_tree (a_id: TM_PROCESS_ID; a_name: READABLE_STRING_32; a_frame: TM_FRAME): TM_ACTION_RESULT
			-- End `a_id' and every descendant in `a_frame', deepest first. A child is a process whose parent
			-- pid is its parent's and that started after it, so a reused parent pid adopts nobody.
		require
			not_idle: not a_id.is_idle_pseudo_process
		local
			l_tree: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			l_ended, l_refused: INTEGER
			l_first_reason: STRING_32
			l_one: TM_ACTION_RESULT
			i: INTEGER
		do
			if is_protected (a_id, a_name) then
				create Result.make_refused ({STRING_32} "End process tree", Protected_reason)
			else
				l_tree := descendants (a_id, a_frame)
				create l_first_reason.make_empty
				from i := l_tree.count until i < 1 loop
					l_one := end_process (l_tree [i].id, l_tree [i].name)
					if l_one.succeeded then
						l_ended := l_ended + 1
					else
						l_refused := l_refused + 1
						if l_first_reason.is_empty then
							l_first_reason := l_tree [i].name + {STRING_32} ": " + l_one.reason
						end
					end
					i := i - 1
				end
				l_one := end_process (a_id, a_name)
				if l_one.succeeded then
					l_ended := l_ended + 1
				elseif l_first_reason.is_empty then
					l_first_reason := l_one.reason
				end
				if l_refused = 0 and l_one.succeeded then
					create Result.make_done ({STRING_32} "End process tree (" + l_ended.out.to_string_32 + {STRING_32} " processes)", 0)
				else
					create Result.make_refused ({STRING_32} "End process tree", l_ended.out.to_string_32 + {STRING_32} " ended; "
						+ l_first_reason)
				end
			end
		ensure
			protected_refused: is_protected (a_id, a_name) implies not Result.succeeded
		end

	set_priority (a_id: TM_PROCESS_ID; a_name: READABLE_STRING_32; a_class: INTEGER): TM_ACTION_RESULT
			-- Set `a_id''s priority class to `a_class'; the result keeps the class it had.
		require
			not_idle: not a_id.is_idle_pseudo_process
			settable: (create {TM_PRIORITY}).is_settable (a_class)
		local
			l_handle: POINTER
			l_error: MANAGED_POINTER
			l_prior: INTEGER
			l_action: STRING_32
		do
			l_action := {STRING_32} "Set priority to " + (create {TM_PRIORITY}).name (a_class)
			if is_protected (a_id, a_name) then
				create Result.make_refused (l_action, Protected_reason)
			else
				create l_error.make (4)
				l_handle := c_open_checked (a_id.pid, a_id.creation_ticks, Process_set_information, l_error.item)
				if l_handle = default_pointer then
					create Result.make_refused (l_action, open_failure_reason (l_error.read_integer_32 (0)))
				else
					l_prior := c_priority_class (l_handle)
					if c_set_priority (l_handle, a_class) then
						if (create {TM_PRIORITY}).is_known (l_prior) then
							create Result.make_done (l_action, l_prior)
						else
							create Result.make_done (l_action, 0)
						end
					else
						create Result.make_refused (l_action, {STRING_32} "Windows refused the change")
					end
					c_close (l_handle)
				end
			end
		ensure
			protected_refused: is_protected (a_id, a_name) implies not Result.succeeded
		end

	set_efficiency_mode (a_id: TM_PROCESS_ID; a_name: READABLE_STRING_32; a_on: BOOLEAN; a_restore_class: INTEGER): TM_ACTION_RESULT
			-- Turn execution-speed throttling (EcoQoS) on with Low priority, as Task Manager does; or off,
			-- restoring `a_restore_class' (Normal when 0). The result keeps the class it had.
		require
			not_idle: not a_id.is_idle_pseudo_process
			restore_settable: a_restore_class = 0 or else (create {TM_PRIORITY}).is_settable (a_restore_class)
		local
			l_handle: POINTER
			l_error: MANAGED_POINTER
			l_prior, l_class: INTEGER
			l_action: STRING_32
		do
			if a_on then
				l_action := {STRING_32} "Efficiency mode on"
				l_class := {TM_PRIORITY}.Idle
			else
				l_action := {STRING_32} "Efficiency mode off"
				if a_restore_class = 0 then
					l_class := {TM_PRIORITY}.Normal
				else
					l_class := a_restore_class
				end
			end
			if is_protected (a_id, a_name) then
				create Result.make_refused (l_action, Protected_reason)
			else
				create l_error.make (4)
				l_handle := c_open_checked (a_id.pid, a_id.creation_ticks, Process_set_information, l_error.item)
				if l_handle = default_pointer then
					create Result.make_refused (l_action, open_failure_reason (l_error.read_integer_32 (0)))
				else
					l_prior := c_priority_class (l_handle)
					inspect c_set_throttling (l_handle, a_on)
					when 1 then
						if c_set_priority (l_handle, l_class) and then (create {TM_PRIORITY}).is_known (l_prior) then
							create Result.make_done (l_action, l_prior)
						else
							create Result.make_done (l_action, 0)
						end
					when -2 then
						create Result.make_refused (l_action, {STRING_32} "this version of Windows has no efficiency mode")
					else
						create Result.make_refused (l_action, {STRING_32} "Windows refused the change")
					end
					c_close (l_handle)
				end
			end
		ensure
			protected_refused: is_protected (a_id, a_name) implies not Result.succeeded
		end

feature -- Contract support

	descendants (a_id: TM_PROCESS_ID; a_frame: TM_FRAME): ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			-- Processes of `a_frame' descended from `a_id', parents before their children.
		local
			l_queue: ARRAYED_LIST [TM_PROCESS_ID]
			l_seen: HASH_TABLE [BOOLEAN, TM_PROCESS_ID]
			i: INTEGER
		do
			create Result.make (8)
			create l_queue.make (8)
			create l_seen.make (8)
			l_queue.extend (a_id)
			l_seen.force (True, a_id)
			from i := 1 until i > l_queue.count loop
				across a_frame.activities as ic loop
					if ic.parent_pid = l_queue [i].pid and then ic.id.creation_ticks > l_queue [i].creation_ticks
							and then not l_seen.has (ic.id) then
						l_seen.force (True, ic.id)
						l_queue.extend (ic.id)
						Result.extend (ic)
					end
				end
				i := i + 1
			end
		ensure
			not_itself: across Result as ic all not (ic.id ~ a_id) end
			distinct: across Result as ic all Result.occurrences (ic) = 1 end
		end

	Protected_reason: STRING_32 = "a protected Windows process; ending or slowing it can stop Windows"

feature {NONE} -- Externals

	c_terminate (a_handle: POINTER): BOOLEAN
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_BOOLEAN) (TerminateProcess ((HANDLE) $a_handle, 1) != 0);"
		end

	c_post_close (a_window: POINTER; a_pid: INTEGER_64): BOOLEAN
			-- Post WM_CLOSE to `a_window' if it still belongs to `a_pid'.
		external
			"C inline use <windows.h>"
		alias
			"[
				DWORD l_pid = 0;
				if (!IsWindow ((HWND) $a_window)) return EIF_FALSE;
				GetWindowThreadProcessId ((HWND) $a_window, &l_pid);
				if ((EIF_INTEGER_64) l_pid != $a_pid) return EIF_FALSE;
				return (EIF_BOOLEAN) (PostMessageW ((HWND) $a_window, WM_CLOSE, 0, 0) != 0);
			]"
		end

	c_priority_class (a_handle: POINTER): INTEGER
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_INTEGER) GetPriorityClass ((HANDLE) $a_handle);"
		end

	c_set_priority (a_handle: POINTER; a_class: INTEGER): BOOLEAN
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_BOOLEAN) (SetPriorityClass ((HANDLE) $a_handle, (DWORD) $a_class) != 0);"
		end

	c_set_throttling (a_handle: POINTER; a_on: BOOLEAN): INTEGER
			-- SetProcessInformation (ProcessPowerThrottling, execution speed): 1 done, 0 refused, -2 unsupported.
		external
			"C inline use <windows.h>"
		alias
			"[
				typedef struct { ULONG Version; ULONG ControlMask; ULONG StateMask; } tm_throttle;
				typedef BOOL (WINAPI *tm_spi) (HANDLE, int, LPVOID, DWORD);
				static tm_spi l_set = NULL;
				tm_throttle l_state;
				if (l_set == NULL) l_set = (tm_spi) GetProcAddress (GetModuleHandleW (L"kernel32.dll"), "SetProcessInformation");
				if (l_set == NULL) return -2;
				ZeroMemory (&l_state, sizeof (l_state));
				l_state.Version = 1;
				l_state.ControlMask = 1;
				l_state.StateMask = $a_on ? 1 : 0;
				return l_set ((HANDLE) $a_handle, 4, &l_state, sizeof (l_state)) ? 1 : 0;
			]"
		end

end
