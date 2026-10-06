note
	description: "[
		One recorder per user session (intent Q2, R-3): a named mutex in the
		session namespace. The first holder records; anyone else opens the
		recording read-only. The mutex is released by closing its handle, so
		the processor that releases it need not be the one that created it.
		When the owner exits, Windows destroys the mutex with its last handle.
	]"
	author: "Larry Rix"

class
	TM_SINGLE_WRITER

inherit
	DISPOSABLE

create
	make

feature {NONE} -- Initialization

	make (a_name: READABLE_STRING_32)
			-- Try to become the one writer named `a_name' in this session.
		require
			plain_name: is_plain_name (a_name)
		local
			l_full: NATIVE_STRING
			l_error: MANAGED_POINTER
			l_handle: POINTER
		do
			create name.make_from_string (a_name)
			create l_full.make ({STRING_32} "Local\" + a_name)
			create l_error.make (4)
			l_handle := c_create_mutex (l_full.item, l_error.item)
			last_error_code := l_error.read_integer_32 (0)
			if l_handle /= default_pointer and last_error_code = 0 then
				handle := l_handle
				is_owner := True
			elseif l_handle /= default_pointer then
				c_close (l_handle)
			end
		ensure
			name_kept: name.same_string (a_name)
			owner_or_said_why: is_owner xor last_error_code /= 0
		end

feature -- Access

	name: STRING_32
			-- Mutex name, without the "Local\" prefix.

	last_error_code: INTEGER
			-- Win32 error from the attempt; 0 when it became the owner, 183 when another holds it.

	Default_name: STRING_32 = "simple_taskman.recorder"

feature -- Status report

	is_owner: BOOLEAN
			-- Is this the session's one writer?

	is_plain_name (a_name: READABLE_STRING_32): BOOLEAN
			-- Letters, digits, dot, dash, underscore only, 1 to 64 characters?
		do
			Result := not a_name.is_empty and a_name.count <= 64 and then
				across a_name as ic all
					(ic >= 'a' and ic <= 'z') or (ic >= 'A' and ic <= 'Z') or (ic >= '0' and ic <= '9')
						or ic = '.' or ic = '-' or ic = '_' end
		end

feature -- Element change

	release
			-- Stop being the writer.
		do
			if handle /= default_pointer then
				c_close (handle)
				handle := default_pointer
			end
			is_owner := False
		ensure
			released: not is_owner
		end

feature {NONE} -- Removal

	dispose
			-- Release when collected.
		do
			release
		end

feature {NONE} -- Implementation

	handle: POINTER
			-- The mutex handle while owner.

	c_create_mutex (a_name, a_error: POINTER): POINTER
			-- CreateMutexW in the session namespace; GetLastError (183 when it already existed) into `a_error'.
		external
			"C inline use <windows.h>"
		alias
			"[
				HANDLE l_handle = CreateMutexW (NULL, TRUE, (LPCWSTR) $a_name);
				*((DWORD *) $a_error) = (l_handle == NULL || GetLastError () == ERROR_ALREADY_EXISTS) ? GetLastError () : 0;
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

invariant
	owner_has_handle: is_owner = (handle /= default_pointer)
	name_plain: is_plain_name (name)

end
