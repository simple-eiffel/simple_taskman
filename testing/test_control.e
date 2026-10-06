note
	description: "[
		Phase 3 slice 1: process details, the window index, and the actions.
		Every action test spawns its own harmless child (ping.exe with no
		window) and acts only on it; protected processes are only asked about,
		and the protection check runs before any open.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_CONTROL

inherit
	TM_TEST_SET

feature -- Tests: values

	test_priority_classes
		local
			l_priority: TM_PRIORITY
		do
			create l_priority
			assert_true ("normal known", l_priority.is_known ({TM_PRIORITY}.Normal))
			assert_false ("realtime never set", l_priority.is_settable ({TM_PRIORITY}.Realtime))
			assert_strings_equal_case_insensitive ("Task Manager's word", "Low", l_priority.name ({TM_PRIORITY}.Idle))
			assert_integers_equal ("five offered", 5, l_priority.settable_classes.count)
		end

	test_action_results
		local
			l_done, l_refused: TM_ACTION_RESULT
		do
			create l_done.make_done ({STRING_32} "End process", 0)
			create l_refused.make_refused ({STRING_32} "End process", {STRING_32} "access denied")
			assert_true ("done", l_done.succeeded and l_done.reason.is_empty)
			assert_string_contains ("summary says why", l_refused.summary, "refused, access denied")
		end

feature -- Tests: details

	test_details_of_this_process
		local
			l_details: TM_PROCESS_DETAILS
		do
			l_details := inspector.details (self_id)
			assert_false ("not gone", l_details.is_gone)
			assert_string_ends_with ("image path", l_details.image_path.as_lower, "simple_taskman.exe")
			assert_string_contains ("command line names the exe", l_details.command_line.as_lower, "simple_taskman")
			assert_string_contains ("user DOMAIN\\name", l_details.user_name, "\")
			assert_true ("x64 build", l_details.architecture.same_string ({STRING_32} "x64"))
			assert_true ("priority read", l_details.priority_status = {TM_READING_STATUS}.Available)
			assert_true ("not critical", l_details.critical_status = {TM_READING_STATUS}.Available and not l_details.is_critical)
		end

	test_a_reused_pid_reads_as_gone
		local
			l_details: TM_PROCESS_DETAILS
		do
			l_details := inspector.details (create {TM_PROCESS_ID}.make (self_id.pid, self_id.creation_ticks + 1))
			assert_true ("gone, not this process", l_details.is_gone)
			assert_string_empty ("nothing borrowed", l_details.image_path)
		end

	test_system_is_protected
		do
			assert_true ("pid 4", control.is_protected (create {TM_PROCESS_ID}.make (4, 1), {STRING_32} "System"))
			assert_true ("by name, any case", control.is_protected (create {TM_PROCESS_ID}.make (999_999, 1), {STRING_32} "CSRSS.EXE"))
			assert_false ("this test is not", control.is_protected (self_id, {STRING_32} "simple_taskman.exe"))
		end

	test_window_index_finds_windows
		local
			l_index: TM_WINDOW_INDEX
		do
			create l_index.make
			l_index.refresh
			assert_true ("an interactive session has windows: " + l_index.window_count.out, l_index.window_count > 0)
		end

feature -- Tests: actions on our own child

	test_priority_and_efficiency_round_trip
		local
			l_child: TM_PROCESS_ID
			l_result: TM_ACTION_RESULT
			l_details: TM_PROCESS_DETAILS
		do
			l_child := spawned ({STRING_32} "ping.exe -n 60 127.0.0.1")
			l_result := control.set_priority (l_child, {STRING_32} "PING.EXE", {TM_PRIORITY}.Below_normal)
			assert_true (l_result.summary, l_result.succeeded)
			assert_integers_equal ("prior kept for undo", {TM_PRIORITY}.Normal, l_result.prior_priority)
			assert_integers_equal ("now below normal", {TM_PRIORITY}.Below_normal, inspector.details (l_child).priority_class)
			l_result := control.set_efficiency_mode (l_child, {STRING_32} "PING.EXE", True, 0)
			assert_true (l_result.summary, l_result.succeeded)
			l_details := inspector.details (l_child)
			assert_true ("efficiency on", l_details.efficiency_status = {TM_READING_STATUS}.Available and l_details.is_efficiency_mode)
			assert_integers_equal ("low priority with it", {TM_PRIORITY}.Idle, l_details.priority_class)
			l_result := control.set_efficiency_mode (l_child, {STRING_32} "PING.EXE", False, {TM_PRIORITY}.Below_normal)
			assert_true (l_result.summary, l_result.succeeded)
			l_details := inspector.details (l_child)
			assert_false ("efficiency off", l_details.is_efficiency_mode)
			assert_integers_equal ("priority restored", {TM_PRIORITY}.Below_normal, l_details.priority_class)
			l_result := control.end_process (l_child, {STRING_32} "PING.EXE")
			assert_true (l_result.summary, l_result.succeeded)
			assert_true ("gone", ended_within (l_child, 3_000))
		end

	test_end_task_needs_a_window
		local
			l_child: TM_PROCESS_ID
			l_index: TM_WINDOW_INDEX
			l_result: TM_ACTION_RESULT
		do
			l_child := spawned ({STRING_32} "ping.exe -n 60 127.0.0.1")
			create l_index.make
			l_index.refresh
			l_result := control.end_task (l_child, {STRING_32} "PING.EXE", l_index)
			assert_false ("no window, no end task", l_result.succeeded)
			assert_string_contains ("says to use End process", l_result.reason, "End process")
			l_result := control.end_process (l_child, {STRING_32} "PING.EXE")
			assert_true ("cleaned up", l_result.succeeded and ended_within (l_child, 3_000))
		end

	test_end_tree_ends_parent_and_child
		local
			l_parent: TM_PROCESS_ID
			l_tm: SIMPLE_TASKMAN
			l_children: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			l_result: TM_ACTION_RESULT
			l_clock: TM_SYSTEM_CLOCK
		do
			create l_clock.make
			l_parent := spawned ({STRING_32} "cmd.exe /c " + system_ping + {STRING_32} " -n 60 127.0.0.1")
			l_clock.sleep_ms (700)
			create l_tm.make
			l_tm.sample
			l_clock.sleep_ms (300)
			l_tm.sample
			l_children := control.descendants (l_parent, l_tm.last_frame)
			assert_true ("ping found under cmd", across l_children as ic some ic.name.as_lower.same_string ({STRING_32} "ping.exe") end)
			l_result := control.end_tree (l_parent, {STRING_32} "cmd.exe", l_tm.last_frame)
			assert_true (l_result.summary, l_result.succeeded)
			assert_true ("parent gone", ended_within (l_parent, 3_000))
			across l_children as ic loop
				assert_true ({STRING_32} "child gone: " + ic.name, ended_within (ic.id, 3_000))
			end
			l_tm.close
		end

	test_actions_on_an_ended_process_are_refused
		local
			l_child: TM_PROCESS_ID
			l_result: TM_ACTION_RESULT
		do
			l_child := spawned ({STRING_32} "ping.exe -n 60 127.0.0.1")
			l_result := control.end_process (l_child, {STRING_32} "PING.EXE")
			assert_true ("ended", l_result.succeeded and ended_within (l_child, 3_000))
			l_result := control.set_priority (l_child, {STRING_32} "PING.EXE", {TM_PRIORITY}.High)
			assert_false ("refused", l_result.succeeded)
			assert_string_contains ("says it ended", l_result.reason, "already ended")
		end

feature {NONE} -- Fixtures

	inspector: TM_PROCESS_INSPECTOR
		once
			create Result.make
		end

	control: TM_PROCESS_CONTROL
		once
			create Result.make (inspector)
		end

	system_ping: STRING_32
			-- Full path of ping.exe, so cmd.exe finds it whatever PATH holds.
		local
			l_env: SIMPLE_ENV
		do
			create l_env
			if attached l_env.item ("SystemRoot") as al_root then
				Result := al_root + {STRING_32} "\System32\ping.exe"
			else
				Result := {STRING_32} "ping.exe"
			end
		end

	self_id: TM_PROCESS_ID
			-- This test process.
		once
			Result := (create {TM_SELF_PROCESS}.make).id
		end

	spawned (a_command: STRING_32): TM_PROCESS_ID
			-- Identity of a new windowless child running `a_command'.
		local
			l_command: NATIVE_STRING
			l_out: MANAGED_POINTER
		do
			create l_command.make (a_command)
			create l_out.make (16)
			if c_spawn (l_command.item, l_out.item) then
				create Result.make (l_out.read_integer_64 (0), l_out.read_integer_64 (8))
			else
				create Result.make (999_999, 1)
			end
		end

	ended_within (a_id: TM_PROCESS_ID; a_ms: INTEGER): BOOLEAN
			-- Has `a_id' ended, waiting up to `a_ms'?
		local
			l_waited: INTEGER
			l_clock: TM_SYSTEM_CLOCK
		do
			create l_clock.make
			from
				Result := inspector.details (a_id).is_gone
			until
				Result or l_waited >= a_ms
			loop
				l_clock.sleep_ms (50)
				l_waited := l_waited + 50
				Result := inspector.details (a_id).is_gone
			end
		end

	c_spawn (a_command, a_out: POINTER): BOOLEAN
			-- CreateProcessW with no window; pid and creation ticks into `a_out'.
		external
			"C inline use <windows.h>"
		alias
			"[
				STARTUPINFOW l_startup;
				PROCESS_INFORMATION l_info;
				FILETIME l_creation, l_exit, l_kernel, l_user;
				ZeroMemory (&l_startup, sizeof (l_startup));
				l_startup.cb = sizeof (l_startup);
				if (!CreateProcessW (NULL, (LPWSTR) $a_command, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &l_startup, &l_info)) return EIF_FALSE;
				GetProcessTimes (l_info.hProcess, &l_creation, &l_exit, &l_kernel, &l_user);
				((EIF_INTEGER_64 *) $a_out) [0] = (EIF_INTEGER_64) l_info.dwProcessId;
				((EIF_INTEGER_64 *) $a_out) [1] = (((EIF_INTEGER_64) l_creation.dwHighDateTime) << 32) | l_creation.dwLowDateTime;
				CloseHandle (l_info.hThread);
				CloseHandle (l_info.hProcess);
				return EIF_TRUE;
			]"
		end

end
