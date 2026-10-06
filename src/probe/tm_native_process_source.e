note
	description: "[
		Every process in one call: ntdll!NtQuerySystemInformation with
		SystemProcessInformation (class 5), reached through GetProcAddress as
		Microsoft asks. Some of the fields used sit where Microsoft's header
		says "Reserved", so the layout is checked against documented calls on
		this very process before the source is trusted. Untrusted, it is never
		read, and the facade falls back to TM_DOCUMENTED_PROCESS_SOURCE.
	]"
	author: "Larry Rix"

class
	TM_NATIVE_PROCESS_SOURCE

inherit
	TM_PROCESS_SOURCE

create
	make,
	make_with_layout_fault

feature {NONE} -- Initialization

	make
			-- Locate the native call and run the layout self-check.
		do
			create buffer.make (Initial_buffer_bytes)
			create last_error.make_empty
			create samples.make (0)
			create last_self_check.make_not_run
			create_time_offset := Offset_create_time
			query_function := c_locate_query_function
			if {PLATFORM}.is_64_bits and query_function /= default_pointer then
				run_self_check
			else
				last_self_check.fail ({STRING_32} "native table needs 64-bit Windows and ntdll!NtQuerySystemInformation")
			end
		ensure
			checked: last_self_check.has_run
			trusted_only_if_passed: is_trusted = last_self_check.passed
			reason_when_untrusted: not is_trusted implies not last_self_check.failure.is_empty
			not_64_bit_never_trusted: not {PLATFORM}.is_64_bits implies not is_trusted
			located_or_untrusted: query_function = default_pointer implies not is_trusted
			open: not is_closed
		end

	make_with_layout_fault
			-- As `make', but reading the creation time 8 bytes off, as a changed
			-- layout would: for proving the self-check refuses a wrong layout.
		do
			create buffer.make (Initial_buffer_bytes)
			create last_error.make_empty
			create samples.make (0)
			create last_self_check.make_not_run
			create_time_offset := Offset_create_time + 8
			query_function := c_locate_query_function
			if {PLATFORM}.is_64_bits and query_function /= default_pointer then
				run_self_check
			else
				last_self_check.fail ({STRING_32} "native table needs 64-bit Windows and ntdll!NtQuerySystemInformation")
			end
		ensure
			checked: last_self_check.has_run
			refused: not is_trusted and not last_self_check.failure.is_empty
		end

feature -- Access

	kind_name: STRING_8
			-- "native".
		once
			Result := "native"
		end

	last_self_check: TM_SELF_CHECK
			-- Outcome of the layout check made at creation.

feature -- Status report

	is_trusted: BOOLEAN
			-- Did the layout self-check pass?
		do
			Result := last_self_check.passed
		end

	is_native: BOOLEAN = True
			-- The native table lists the idle pseudo-process.

feature -- Basic operations

	read_all
			-- One call returns every process. Grow the buffer and retry on
			-- STATUS_INFO_LENGTH_MISMATCH (0xC0000004), at most three times.
		do
			read_table
		end

	close
			-- Nothing native is held between reads.
		do
			is_closed := True
		end

feature {NONE} -- Reading the table

	read_table
			-- Fill `samples' from one native call, or say why not. No trust needed:
			-- the self-check calls this before the source is trusted.
		local
			l_status, l_returned, l_attempt: INTEGER
		do
			from
				l_status := Status_info_length_mismatch
				l_attempt := 0
			until
				l_status /= Status_info_length_mismatch or l_attempt > 3
			loop
				l_status := c_query (query_function, buffer.item, buffer.count, $l_returned)
				if l_status = Status_info_length_mismatch then
					buffer.resize ((l_returned + l_returned // 4).max (buffer.count * 2))
				end
				l_attempt := l_attempt + 1
			end
			if l_status /= 0 then
				last_read_succeeded := False
				create last_error.make_from_string ({STRING_32} "NtQuerySystemInformation returned status " + l_status.out.to_string_32)
			else
				parse_table (l_returned)
			end
		ensure
			succeeded_or_said_why: last_read_succeeded xor not last_error.is_empty
		end

	parse_table (a_bytes: INTEGER)
			-- Walk the entries in the first `a_bytes' of `buffer'.
		local
			l_list: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			l_offset, l_next: INTEGER
			l_problem: STRING_32
		do
			create l_list.make (512)
			create l_problem.make_empty
			from
				l_next := -1
			until
				l_next = 0 or not l_problem.is_empty
			loop
				if l_offset < 0 or l_offset + Entry_minimum_bytes > a_bytes then
					l_problem := {STRING_32} "native entry runs past the returned table"
				else
					l_next := buffer.read_natural_32 (l_offset + Offset_next).to_integer_32
					if attached entry_sample (l_offset, a_bytes) as al_sample then
						l_list.extend (al_sample)
						l_offset := l_offset + l_next
					else
						l_problem := {STRING_32} "native image name lies outside the returned table"
					end
				end
			end
			if l_problem.is_empty then
				samples := l_list
				last_read_succeeded := True
				create last_error.make_empty
			else
				last_read_succeeded := False
				last_error := l_problem
			end
		end

	entry_sample (a_offset, a_bytes: INTEGER): detachable TM_PROCESS_SAMPLE
			-- The sample of the entry at `a_offset'; Void when its name pointer is outside the table.
		local
			l_pid, l_create, l_user, l_kernel, l_ws, l_private, l_read, l_write: INTEGER_64
			l_name: STRING_32
			l_name_bytes: INTEGER
			l_name_at: INTEGER_64
		do
			l_pid := buffer.read_integer_64 (a_offset + Offset_pid)
			l_create := buffer.read_integer_64 (a_offset + create_time_offset)
			l_user := buffer.read_integer_64 (a_offset + Offset_user_time)
			l_kernel := buffer.read_integer_64 (a_offset + Offset_kernel_time)
			l_ws := buffer.read_integer_64 (a_offset + Offset_working_set)
			l_private := buffer.read_integer_64 (a_offset + Offset_private_bytes)
			l_read := buffer.read_integer_64 (a_offset + Offset_read_transfer)
			l_write := buffer.read_integer_64 (a_offset + Offset_write_transfer)
			l_name_bytes := buffer.read_natural_16 (a_offset + Offset_name_length).to_integer_32
			l_name_at := c_distance (buffer.item, buffer.read_pointer (a_offset + Offset_name_buffer))
			if l_name_bytes = 0 then
				l_name := {STRING_32} "System Idle Process"
			elseif l_name_at >= 0 and then l_name_at + l_name_bytes <= a_bytes then
				l_name := utf_16_text (l_name_at.to_integer_32, l_name_bytes)
			end
			if attached l_name as al_name and l_pid >= 0 then
				create Result.make (create {TM_PROCESS_ID}.make (l_pid, l_create.max (0)), al_name,
					buffer.read_integer_64 (a_offset + Offset_parent_pid).max (0),
					buffer.read_natural_32 (a_offset + Offset_session).to_integer_32.max (0),
					buffer.read_natural_32 (a_offset + Offset_threads).to_integer_32.max (0))
				if l_user >= 0 and l_kernel >= 0 then
					Result.set_cpu (l_user, l_kernel)
				else
					Result.deny_cpu ({TM_READING_STATUS}.Invalid)
				end
				if l_ws >= 0 and l_private >= 0 then
					Result.set_memory (l_ws, l_private, buffer.read_natural_32 (a_offset + Offset_handles).to_integer_32.max (0))
				else
					Result.deny_memory ({TM_READING_STATUS}.Invalid)
				end
				if l_read >= 0 and l_write >= 0 then
					Result.set_io (l_read, l_write)
				else
					Result.deny_io ({TM_READING_STATUS}.Invalid)
				end
			end
		end

	utf_16_text (a_at, a_bytes: INTEGER): STRING_32
			-- UTF-16 text of `a_bytes' bytes at offset `a_at' of `buffer'.
		local
			l_units: SPECIAL [NATURAL_16]
			l_utf: UTF_CONVERTER
			i: INTEGER
		do
			create l_units.make_filled (0, a_bytes // 2)
			from
				i := 0
			until
				i = a_bytes // 2
			loop
				l_units [i] := buffer.read_natural_16 (a_at + i * 2)
				i := i + 1
			end
			Result := l_utf.utf_16_to_string_32 (l_units)
		end

feature {NONE} -- Self-check

	run_self_check
			-- Documented reads A, native read, documented reads B; pass when every
			-- field lies between A and B or within its stated slack (spec 07, "Self-check").
		require
			not_decided: not last_self_check.has_run
			located: query_function /= default_pointer
		local
			l_before, l_after: MANAGED_POINTER
			l_own: detachable TM_PROCESS_SAMPLE
			l_pid: INTEGER_64
		do
			create l_before.make (Self_slots * 8)
			create l_after.make (Self_slots * 8)
			l_pid := c_current_pid
			if not c_self_reads (l_before.item) then
				last_self_check.fail ({STRING_32} "documented reads of this process failed")
			else
				read_table
				if c_self_reads (l_after.item) and last_read_succeeded then
					across samples as ic until attached l_own loop
						if ic.id.pid = l_pid then
							l_own := ic
						end
					end
					if attached l_own as al_own then
						compare (al_own, l_before, l_after)
					else
						last_self_check.fail ({STRING_32} "this process is not in the native table")
					end
				elseif not last_read_succeeded then
					last_self_check.fail (last_error)
				else
					last_self_check.fail ({STRING_32} "documented reads of this process failed")
				end
			end
			last_read_succeeded := False
			create samples.make (0)
			create last_error.make_empty
		ensure
			decided: last_self_check.has_run
		end

	compare (a_own: TM_PROCESS_SAMPLE; a_before, a_after: MANAGED_POINTER)
			-- Decide the self-check from this process's native row and its two documented reads.
		require
			not_decided: not last_self_check.has_run
		local
			b, a: INTEGER_64
		do
			b := a_before.read_integer_64 (0)
			a := a_after.read_integer_64 (0)
			if a_own.id.creation_ticks /= b or b /= a then
				last_self_check.fail_field ("create_time", b, a_own.id.creation_ticks, a)
			elseif a_own.cpu_status /= {TM_READING_STATUS}.Available or a_own.memory_status /= {TM_READING_STATUS}.Available
					or a_own.io_status /= {TM_READING_STATUS}.Available then
				last_self_check.fail ({STRING_32} "this process's native row carries an impossible value")
			elseif not between (a_own.user_ticks, a_before.read_integer_64 (8), a_after.read_integer_64 (8), 0) then
				last_self_check.fail_field ("user_time", a_before.read_integer_64 (8), a_own.user_ticks, a_after.read_integer_64 (8))
			elseif not between (a_own.kernel_ticks, a_before.read_integer_64 (16), a_after.read_integer_64 (16), 0) then
				last_self_check.fail_field ("kernel_time", a_before.read_integer_64 (16), a_own.kernel_ticks, a_after.read_integer_64 (16))
			elseif not between (a_own.working_set, a_before.read_integer_64 (24), a_after.read_integer_64 (24), Memory_slack) then
				last_self_check.fail_field ("working_set", a_before.read_integer_64 (24), a_own.working_set, a_after.read_integer_64 (24))
			elseif not between (a_own.private_bytes, a_before.read_integer_64 (32), a_after.read_integer_64 (32), Memory_slack) then
				last_self_check.fail_field ("private_bytes", a_before.read_integer_64 (32), a_own.private_bytes, a_after.read_integer_64 (32))
			elseif not between (a_own.read_bytes, a_before.read_integer_64 (40), a_after.read_integer_64 (40), 0) then
				last_self_check.fail_field ("read_transfer", a_before.read_integer_64 (40), a_own.read_bytes, a_after.read_integer_64 (40))
			elseif not between (a_own.write_bytes, a_before.read_integer_64 (48), a_after.read_integer_64 (48), 0) then
				last_self_check.fail_field ("write_transfer", a_before.read_integer_64 (48), a_own.write_bytes, a_after.read_integer_64 (48))
			elseif not between (a_own.handles.to_integer_64, a_before.read_integer_64 (56), a_after.read_integer_64 (56), Handle_slack) then
				last_self_check.fail_field ("handles", a_before.read_integer_64 (56), a_own.handles, a_after.read_integer_64 (56))
			elseif a_own.session /= c_current_session then
				last_self_check.fail_field ("session", c_current_session, a_own.session, c_current_session)
			elseif not a_own.name.as_lower.same_string (own_image_name.as_lower) then
				last_self_check.fail ({STRING_32} "native image name " + a_own.name + {STRING_32} " is not " + own_image_name)
			else
				last_self_check.pass
			end
		ensure
			decided: last_self_check.has_run
		end

	between (a_value, a_first, a_second, a_slack: INTEGER_64): BOOLEAN
			-- Does `a_value' lie in [min - slack, max + slack] of the two documented reads?
		do
			Result := a_value >= a_first.min (a_second) - a_slack and a_value <= a_first.max (a_second) + a_slack
		end

	own_image_name: STRING_32
			-- File name of this process's executable, without its folder.
		local
			l_path: MANAGED_POINTER
			l_full: STRING_32
			l_slash: INTEGER
		do
			create l_path.make (Path_units * 2)
			c_own_path (l_path.item, Path_units)
			l_full := (create {NATIVE_STRING}.make_from_pointer (l_path.item)).string
			l_slash := l_full.last_index_of ({CHARACTER_32} '\', l_full.count)
			Result := l_full.substring (l_slash + 1, l_full.count)
		end

	create_time_offset: INTEGER
			-- Where creation time is read; `Offset_create_time' unless a fault is injected.

	Self_slots: INTEGER = 8
			-- creation, user, kernel, working set, private, read, write, handles.

	Memory_slack: INTEGER_64 = 4_194_304
			-- 4 MB: memory may move between the reads.

	Handle_slack: INTEGER_64 = 16

	Path_units: INTEGER = 1024

feature {NONE} -- Layout (x64; see 04-CLASS-DESIGN, "Native process table layout")

	Offset_next: INTEGER = 0x00
	Offset_threads: INTEGER = 0x04
	Offset_create_time: INTEGER = 0x20
	Offset_user_time: INTEGER = 0x28
	Offset_kernel_time: INTEGER = 0x30
	Offset_name_length: INTEGER = 0x38
	Offset_name_buffer: INTEGER = 0x40
	Offset_pid: INTEGER = 0x50
	Offset_parent_pid: INTEGER = 0x58
	Offset_handles: INTEGER = 0x60
	Offset_session: INTEGER = 0x64
	Offset_working_set: INTEGER = 0x90
	Offset_private_bytes: INTEGER = 0xB8
	Offset_read_transfer: INTEGER = 0xE8
	Offset_write_transfer: INTEGER = 0xF0

	Entry_minimum_bytes: INTEGER = 0xF8
			-- Bytes up to and including the last field read.

	Initial_buffer_bytes: INTEGER = 1_048_576
			-- 1 MB; the 2026-10-03 spike needed 0.94 MB for about 350 processes.

	Minimum_buffer_bytes: INTEGER = 65_536

	Status_info_length_mismatch: INTEGER = -1073741820
			-- NTSTATUS 0xC0000004 as a signed 32-bit value: the buffer is too small.

feature {NONE} -- Implementation

	buffer: MANAGED_POINTER
			-- Receives the process table.

	query_function: POINTER
			-- ntdll!NtQuerySystemInformation, or null.

feature {NONE} -- Externals

	c_locate_query_function: POINTER
		external
			"C inline use <windows.h>"
		alias
			"[
				HMODULE h = GetModuleHandleW (L"ntdll.dll");
				return (h == NULL) ? NULL : (EIF_POINTER) GetProcAddress (h, "NtQuerySystemInformation");
			]"
		end

	c_query (a_function, a_buffer: POINTER; a_length: INTEGER; a_returned: TYPED_POINTER [INTEGER]): INTEGER
			-- NTSTATUS of SystemProcessInformation (class 5). Blocking (C-015).
		external
			"C blocking inline use <windows.h>"
		alias
			"[
				typedef LONG (WINAPI *tm_query_fn) (ULONG, PVOID, ULONG, PULONG);
				return (EIF_INTEGER) ((tm_query_fn) $a_function) (5, $a_buffer, (ULONG) $a_length, (PULONG) $a_returned);
			]"
		end

	c_distance (a_base, a_pointer: POINTER): INTEGER_64
			-- Bytes from `a_base' to `a_pointer'.
		external
			"C inline"
		alias
			"return (EIF_INTEGER_64) ((char *) $a_pointer - (char *) $a_base);"
		end

	c_current_pid: INTEGER_64
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_INTEGER_64) GetCurrentProcessId ();"
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

	c_own_path (a_buffer: POINTER; a_units: INTEGER)
		external
			"C inline use <windows.h>"
		alias
			"[
				DWORD l_length = GetModuleFileNameW (NULL, (LPWSTR) $a_buffer, (DWORD) $a_units);
				if (l_length >= (DWORD) $a_units) l_length = (DWORD) $a_units - 1;
				((LPWSTR) $a_buffer) [l_length] = 0;
			]"
		end

	c_self_reads (a_out: POINTER): BOOLEAN
			-- This process, documented: creation, user, kernel, working set, private,
			-- read transfer, write transfer, handles, into eight 64-bit slots.
		external
			"C inline use <windows.h>, <psapi.h>"
		alias
			"[
				#if _WIN32_WINNT < 0x0602
				#error "simple_taskman needs _WIN32_WINNT >= 0x0602 (Windows 8 API): keep the external_cflag of simple_taskman.ecf"
				#endif
				FILETIME l_creation, l_exit, l_kernel, l_user;
				PROCESS_MEMORY_COUNTERS_EX l_memory;
				IO_COUNTERS l_io;
				DWORD l_handles = 0;
				HANDLE l_self = GetCurrentProcess ();
				EIF_INTEGER_64 *l_out = (EIF_INTEGER_64 *) $a_out;
				if (!GetProcessTimes (l_self, &l_creation, &l_exit, &l_kernel, &l_user)) return EIF_FALSE;
				if (!K32GetProcessMemoryInfo (l_self, (PPROCESS_MEMORY_COUNTERS) &l_memory, sizeof (l_memory))) return EIF_FALSE;
				if (!GetProcessIoCounters (l_self, &l_io)) return EIF_FALSE;
				if (!GetProcessHandleCount (l_self, &l_handles)) return EIF_FALSE;
				l_out [0] = (EIF_INTEGER_64) (((ULONGLONG) l_creation.dwHighDateTime << 32) | l_creation.dwLowDateTime);
				l_out [1] = (EIF_INTEGER_64) (((ULONGLONG) l_user.dwHighDateTime << 32) | l_user.dwLowDateTime);
				l_out [2] = (EIF_INTEGER_64) (((ULONGLONG) l_kernel.dwHighDateTime << 32) | l_kernel.dwLowDateTime);
				l_out [3] = (EIF_INTEGER_64) l_memory.WorkingSetSize;
				l_out [4] = (EIF_INTEGER_64) l_memory.PrivateUsage;
				l_out [5] = (EIF_INTEGER_64) l_io.ReadTransferCount;
				l_out [6] = (EIF_INTEGER_64) l_io.WriteTransferCount;
				l_out [7] = (EIF_INTEGER_64) l_handles;
				return EIF_TRUE;
			]"
		end

invariant
	buffer_present: buffer.count >= Minimum_buffer_bytes
	trusted_has_function: is_trusted implies query_function /= default_pointer
	trusted_only_on_64_bit: is_trusted implies {PLATFORM}.is_64_bits

end
