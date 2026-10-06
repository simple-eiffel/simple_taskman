note
	description: "[
		The fallback: a Toolhelp snapshot for the process list, then documented
		per-process calls for times, memory, IO, and handles. Slower, and a
		process we may not open reports access denied for that group, which
		the sample's statuses already express. Always trusted.

		A process that cannot be opened at all has no readable creation time;
		its identity then carries creation time 0, which is weaker against pid
		reuse. Only a few protected processes are in that position.
	]"
	author: "Larry Rix"

class
	TM_DOCUMENTED_PROCESS_SOURCE

inherit
	TM_PROCESS_SOURCE

create
	make

feature {NONE} -- Initialization

	make
			-- Ready to read.
		do
			create last_error.make_empty
			create samples.make (0)
		ensure
			open: not is_closed
			trusted: is_trusted
		end

feature -- Access

	kind_name: STRING_8
			-- "documented".
		once
			Result := "documented"
		end

feature -- Status report

	is_trusted: BOOLEAN = True
			-- Documented calls need no layout check.

	is_native: BOOLEAN = False
			-- Toolhelp does not list the idle pseudo-process with times.

feature -- Basic operations

	read_all
			-- CreateToolhelp32Snapshot, then per process OpenProcess with
			-- PROCESS_QUERY_LIMITED_INFORMATION and the documented reads.
		local
			l_snapshot: POINTER
			l_entry, l_values: MANAGED_POINTER
			l_list: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			l_more: BOOLEAN
		do
			l_snapshot := c_snapshot
			if l_snapshot = default_pointer then
				last_read_succeeded := False
				create last_error.make_from_string ({STRING_32} "CreateToolhelp32Snapshot failed")
			else
				create l_entry.make (c_entry_bytes)
				create l_values.make (8 * 4)
				create l_list.make (512)
				from
					l_more := c_first (l_snapshot, l_entry.item)
				until
					not l_more
				loop
					extend_sample (l_list, l_entry, l_values)
					l_more := c_next (l_snapshot, l_entry.item)
				end
				c_close (l_snapshot)
				samples := l_list
				last_read_succeeded := True
				create last_error.make_empty
			end
		end

	close
			-- Nothing is held between reads.
		do
			is_closed := True
		end

feature {NONE} -- Implementation

	extend_sample (a_list: ARRAYED_LIST [TM_PROCESS_SAMPLE]; a_entry, a_values: MANAGED_POINTER)
			-- Append to `a_list' the sample for the Toolhelp entry in `a_entry', read
			-- through documented calls; `a_values' is scratch space.
		local
			l_pid, l_creation: INTEGER_64
			l_handle: POINTER
			l_session: INTEGER
			l_times_read: BOOLEAN
			l_sample: TM_PROCESS_SAMPLE
		do
			l_pid := c_entry_pid (a_entry.item)
			if l_pid /= 0 then
				l_handle := c_open (l_pid)
			end
			if l_handle /= default_pointer then
				l_times_read := c_times (l_handle, a_values.item)
				if l_times_read then
					l_creation := a_values.read_integer_64 (0).max (0)
				end
			end
			if c_session (l_pid, a_values.item + 24) then
				l_session := a_values.read_integer_32 (24).max (0)
			end
			create l_sample.make (create {TM_PROCESS_ID}.make (l_pid, l_creation),
				(create {NATIVE_STRING}.make_from_pointer (c_entry_name (a_entry.item))).string,
				c_entry_parent (a_entry.item).max (0), l_session, c_entry_threads (a_entry.item).max (0))
			if l_handle = default_pointer then
				l_sample.deny_cpu (refusal (l_pid))
				l_sample.deny_memory (refusal (l_pid))
				l_sample.deny_io (refusal (l_pid))
			else
				if l_times_read and then a_values.read_integer_64 (8) >= 0 and then a_values.read_integer_64 (16) >= 0 then
					l_sample.set_cpu (a_values.read_integer_64 (16), a_values.read_integer_64 (8))
				else
					l_sample.deny_cpu ({TM_READING_STATUS}.Access_denied)
				end
				if c_memory_info (l_handle, a_values.item) and then a_values.read_integer_64 (0) >= 0
						and then a_values.read_integer_64 (8) >= 0 and then a_values.read_integer_64 (16) >= 0 then
					l_sample.set_memory (a_values.read_integer_64 (0), a_values.read_integer_64 (8), a_values.read_integer_64 (16).to_integer_32)
				else
					l_sample.deny_memory ({TM_READING_STATUS}.Access_denied)
				end
				if c_io (l_handle, a_values.item) and then a_values.read_integer_64 (0) >= 0 and then a_values.read_integer_64 (8) >= 0 then
					l_sample.set_io (a_values.read_integer_64 (0), a_values.read_integer_64 (8))
				else
					l_sample.deny_io ({TM_READING_STATUS}.Access_denied)
				end
				c_close (l_handle)
			end
			a_list.extend (l_sample)
		end

	refusal (a_pid: INTEGER_64): INTEGER
			-- Why a process that could not be opened has no group: the idle entry has no
			-- documented source; any other was refused.
		do
			if a_pid = 0 then
				Result := {TM_READING_STATUS}.Not_supported
			else
				Result := {TM_READING_STATUS}.Access_denied
			end
		end

feature {NONE} -- Externals

	c_snapshot: POINTER
			-- Blocking: the snapshot walks every process (C-015).
		external
			"C blocking inline use <windows.h>, <tlhelp32.h>"
		alias
			"[
				HANDLE l_snapshot = CreateToolhelp32Snapshot (TH32CS_SNAPPROCESS, 0);
				return (l_snapshot == INVALID_HANDLE_VALUE) ? NULL : (EIF_POINTER) l_snapshot;
			]"
		end

	c_entry_bytes: INTEGER
		external
			"C inline use <windows.h>, <tlhelp32.h>"
		alias
			"return (EIF_INTEGER) sizeof (PROCESSENTRY32W);"
		end

	c_first (a_snapshot, a_entry: POINTER): BOOLEAN
		external
			"C inline use <windows.h>, <tlhelp32.h>"
		alias
			"[
				((PROCESSENTRY32W *) $a_entry)->dwSize = sizeof (PROCESSENTRY32W);
				return Process32FirstW ((HANDLE) $a_snapshot, (PROCESSENTRY32W *) $a_entry) ? EIF_TRUE : EIF_FALSE;
			]"
		end

	c_next (a_snapshot, a_entry: POINTER): BOOLEAN
		external
			"C inline use <windows.h>, <tlhelp32.h>"
		alias
			"return Process32NextW ((HANDLE) $a_snapshot, (PROCESSENTRY32W *) $a_entry) ? EIF_TRUE : EIF_FALSE;"
		end

	c_entry_pid (a_entry: POINTER): INTEGER_64
		external
			"C inline use <windows.h>, <tlhelp32.h>"
		alias
			"return (EIF_INTEGER_64) ((PROCESSENTRY32W *) $a_entry)->th32ProcessID;"
		end

	c_entry_parent (a_entry: POINTER): INTEGER_64
		external
			"C inline use <windows.h>, <tlhelp32.h>"
		alias
			"return (EIF_INTEGER_64) ((PROCESSENTRY32W *) $a_entry)->th32ParentProcessID;"
		end

	c_entry_threads (a_entry: POINTER): INTEGER
		external
			"C inline use <windows.h>, <tlhelp32.h>"
		alias
			"return (EIF_INTEGER) ((PROCESSENTRY32W *) $a_entry)->cntThreads;"
		end

	c_entry_name (a_entry: POINTER): POINTER
		external
			"C inline use <windows.h>, <tlhelp32.h>"
		alias
			"return (EIF_POINTER) ((PROCESSENTRY32W *) $a_entry)->szExeFile;"
		end

	c_open (a_pid: INTEGER_64): POINTER
		external
			"C inline use <windows.h>"
		alias
			"[
				#if _WIN32_WINNT < 0x0602
				#error "simple_taskman needs _WIN32_WINNT >= 0x0602 (Windows 8 API): keep the external_cflag of simple_taskman.ecf"
				#endif
				return (EIF_POINTER) OpenProcess (PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD) $a_pid);
			]"
		end

	c_close (a_handle: POINTER)
		external
			"C inline use <windows.h>"
		alias
			"CloseHandle ((HANDLE) $a_handle);"
		end

	c_times (a_handle, a_out: POINTER): BOOLEAN
			-- Creation, kernel, and user time into three 64-bit slots.
		external
			"C inline use <windows.h>"
		alias
			"[
				FILETIME l_creation, l_exit, l_kernel, l_user;
				EIF_INTEGER_64 *l_out = (EIF_INTEGER_64 *) $a_out;
				if (!GetProcessTimes ((HANDLE) $a_handle, &l_creation, &l_exit, &l_kernel, &l_user)) return EIF_FALSE;
				l_out [0] = (EIF_INTEGER_64) (((ULONGLONG) l_creation.dwHighDateTime << 32) | l_creation.dwLowDateTime);
				l_out [1] = (EIF_INTEGER_64) (((ULONGLONG) l_kernel.dwHighDateTime << 32) | l_kernel.dwLowDateTime);
				l_out [2] = (EIF_INTEGER_64) (((ULONGLONG) l_user.dwHighDateTime << 32) | l_user.dwLowDateTime);
				return EIF_TRUE;
			]"
		end

	c_memory_info (a_handle, a_out: POINTER): BOOLEAN
			-- Working set, private bytes, and handle count into three 64-bit slots.
		external
			"C inline use <windows.h>, <psapi.h>"
		alias
			"[
				#if _WIN32_WINNT < 0x0602
				#error "simple_taskman needs _WIN32_WINNT >= 0x0602 (Windows 8 API): keep the external_cflag of simple_taskman.ecf"
				#endif
				PROCESS_MEMORY_COUNTERS_EX l_memory;
				DWORD l_handles = 0;
				EIF_INTEGER_64 *l_out = (EIF_INTEGER_64 *) $a_out;
				if (!K32GetProcessMemoryInfo ((HANDLE) $a_handle, (PPROCESS_MEMORY_COUNTERS) &l_memory, sizeof (l_memory))) return EIF_FALSE;
				if (!GetProcessHandleCount ((HANDLE) $a_handle, &l_handles)) return EIF_FALSE;
				l_out [0] = (EIF_INTEGER_64) l_memory.WorkingSetSize;
				l_out [1] = (EIF_INTEGER_64) l_memory.PrivateUsage;
				l_out [2] = (EIF_INTEGER_64) l_handles;
				return EIF_TRUE;
			]"
		end

	c_io (a_handle, a_out: POINTER): BOOLEAN
			-- Bytes read and written (all IO) into two 64-bit slots.
		external
			"C inline use <windows.h>"
		alias
			"[
				IO_COUNTERS l_io;
				EIF_INTEGER_64 *l_out = (EIF_INTEGER_64 *) $a_out;
				if (!GetProcessIoCounters ((HANDLE) $a_handle, &l_io)) return EIF_FALSE;
				l_out [0] = (EIF_INTEGER_64) l_io.ReadTransferCount;
				l_out [1] = (EIF_INTEGER_64) l_io.WriteTransferCount;
				return EIF_TRUE;
			]"
		end

	c_session (a_pid: INTEGER_64; a_out: POINTER): BOOLEAN
			-- Session of `a_pid' into one 32-bit slot.
		external
			"C inline use <windows.h>"
		alias
			"return ProcessIdToSessionId ((DWORD) $a_pid, (DWORD *) $a_out) ? EIF_TRUE : EIF_FALSE;"
		end

end
