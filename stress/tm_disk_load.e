note
	description: "[
		Disk load that reaches the disk: a file written and reread through
		CreateFileW with FILE_FLAG_NO_BUFFERING and FILE_FLAG_WRITE_THROUGH,
		in 1 MB chunks from a page-aligned buffer, until a deadline; then the
		file is deleted. Its own inline C (R-8): simple_file writes byte by
		byte and cannot bypass the cache.
	]"
	author: "Larry Rix"

class
	TM_DISK_LOAD

create
	make

feature {NONE} -- Initialization

	make (a_folder: READABLE_STRING_32; a_mb: INTEGER)
			-- Load of an `a_mb' MB file in `a_folder'.
		require
			folder_given: not a_folder.is_empty
			size_sane: a_mb >= 1 and a_mb <= 65_536
		do
			create path.make_from_string (a_folder)
			if not path.ends_with ({STRING_32} "\") then
				path.append ({STRING_32} "\")
			end
			path.append ({STRING_32} "taskman_stress.bin")
			megabytes := a_mb
			create last_error.make_empty
		ensure
			sized: megabytes = a_mb
			nothing_done: bytes_written = 0 and bytes_read = 0
		end

feature -- Access

	path: STRING_32
			-- The scratch file.

	megabytes: INTEGER
			-- File size in MB.

	bytes_written, bytes_read: INTEGER_64
			-- Bytes moved by the last `run'.

	passes: INTEGER
			-- Write-then-read passes completed.

	last_error: STRING_32
			-- Why the last `run' stopped early; empty when it did not.

feature -- Execution

	run (a_seconds: INTEGER)
			-- Write and reread the file until `a_seconds' have passed, then delete it.
		require
			positive: a_seconds > 0
		local
			l_clock: TM_SYSTEM_CLOCK
			l_deadline: INTEGER_64
			l_buffer, l_handle: POINTER
			l_path: NATIVE_STRING
			i: INTEGER
		do
			bytes_written := 0
			bytes_read := 0
			passes := 0
			create last_error.make_empty
			create l_clock.make
			create l_path.make (path)
			l_deadline := l_clock.monotonic_ticks + a_seconds.to_integer_64 * 10_000_000
			l_buffer := c_alloc (Chunk_bytes)
			if l_buffer = default_pointer then
				last_error := {STRING_32} "could not allocate an aligned buffer"
			else
				c_fill (l_buffer, Chunk_bytes)
				l_handle := c_open (l_path.item)
				if l_handle = default_pointer then
					last_error := {STRING_32} "could not create " + path
				else
					from
					until
						not last_error.is_empty or l_clock.monotonic_ticks >= l_deadline
					loop
						c_rewind (l_handle)
						from i := 1 until i > megabytes or not last_error.is_empty loop
							if c_write (l_handle, l_buffer, Chunk_bytes) then
								bytes_written := bytes_written + Chunk_bytes
							else
								last_error := {STRING_32} "write failed"
							end
							i := i + 1
						end
						c_rewind (l_handle)
						from i := 1 until i > megabytes or not last_error.is_empty loop
							if c_read (l_handle, l_buffer, Chunk_bytes) then
								bytes_read := bytes_read + Chunk_bytes
							else
								last_error := {STRING_32} "read failed"
							end
							i := i + 1
						end
						if last_error.is_empty then
							passes := passes + 1
						end
					end
					c_close (l_handle)
					c_delete (l_path.item)
				end
				c_free (l_buffer)
			end
		ensure
			moved_or_said_why: last_error.is_empty implies (passes > 0 and bytes_read = bytes_written)
		end

feature -- Constants

	Chunk_bytes: INTEGER = 1_048_576
			-- One write: a multiple of every sector size.

feature {NONE} -- Externals

	c_alloc (a_bytes: INTEGER): POINTER
			-- Page-aligned memory, as unbuffered IO requires.
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_POINTER) VirtualAlloc (NULL, (SIZE_T) $a_bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);"
		end

	c_free (a_buffer: POINTER)
		external
			"C inline use <windows.h>"
		alias
			"VirtualFree ((LPVOID) $a_buffer, 0, MEM_RELEASE);"
		end

	c_fill (a_buffer: POINTER; a_bytes: INTEGER)
			-- Something other than zeros, so nothing compresses it away.
		external
			"C inline use <windows.h>"
		alias
			"[
				unsigned char *l_at = (unsigned char *) $a_buffer;
				int i;
				for (i = 0; i < (int) $a_bytes; i++) l_at [i] = (unsigned char) ((i * 131) ^ (i >> 7));
			]"
		end

	c_open (a_path: POINTER): POINTER
		external
			"C inline use <windows.h>"
		alias
			"[
				HANDLE l_file = CreateFileW ((LPCWSTR) $a_path, GENERIC_READ | GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
					FILE_ATTRIBUTE_NORMAL | FILE_FLAG_NO_BUFFERING | FILE_FLAG_WRITE_THROUGH, NULL);
				return (l_file == INVALID_HANDLE_VALUE) ? NULL : (EIF_POINTER) l_file;
			]"
		end

	c_rewind (a_handle: POINTER)
		external
			"C inline use <windows.h>"
		alias
			"[
				LARGE_INTEGER l_zero;
				l_zero.QuadPart = 0;
				SetFilePointerEx ((HANDLE) $a_handle, l_zero, NULL, FILE_BEGIN);
			]"
		end

	c_write (a_handle, a_buffer: POINTER; a_bytes: INTEGER): BOOLEAN
			-- Blocking: the disk decides how long this takes (C-015).
		external
			"C blocking inline use <windows.h>"
		alias
			"[
				DWORD l_done = 0;
				return (WriteFile ((HANDLE) $a_handle, (LPCVOID) $a_buffer, (DWORD) $a_bytes, &l_done, NULL)
					&& l_done == (DWORD) $a_bytes) ? EIF_TRUE : EIF_FALSE;
			]"
		end

	c_read (a_handle, a_buffer: POINTER; a_bytes: INTEGER): BOOLEAN
			-- Blocking (C-015).
		external
			"C blocking inline use <windows.h>"
		alias
			"[
				DWORD l_done = 0;
				return (ReadFile ((HANDLE) $a_handle, (LPVOID) $a_buffer, (DWORD) $a_bytes, &l_done, NULL)
					&& l_done == (DWORD) $a_bytes) ? EIF_TRUE : EIF_FALSE;
			]"
		end

	c_close (a_handle: POINTER)
		external
			"C inline use <windows.h>"
		alias
			"CloseHandle ((HANDLE) $a_handle);"
		end

	c_delete (a_path: POINTER)
		external
			"C inline use <windows.h>"
		alias
			"DeleteFileW ((LPCWSTR) $a_path);"
		end

invariant
	size_sane: megabytes >= 1 and megabytes <= 65_536

end
