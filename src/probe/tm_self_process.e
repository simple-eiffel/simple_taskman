note
	description: "[
		This process's identity, read through documented calls. Lives in probe
		because probe is the only cluster with externals; the facade asks this
		class instead of calling Win32 itself.
	]"
	author: "Larry Rix"

class
	TM_SELF_PROCESS

create
	make

feature {NONE} -- Initialization

	make
			-- Read this process's pid and creation time.
		do
			create id.make (c_current_pid, c_current_creation_ticks)
		ensure
			real_process: id.pid > 0 and id.creation_ticks > 0
		end

feature -- Access

	id: TM_PROCESS_ID
			-- This process.

feature {NONE} -- Externals

	c_current_pid: INTEGER_64
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_INTEGER_64) GetCurrentProcessId ();"
		end

	c_current_creation_ticks: INTEGER_64
			-- Creation time from GetProcessTimes, UTC ticks since 1601.
		external
			"C inline use <windows.h>"
		alias
			"[
				FILETIME c, e, k, u;
				ULARGE_INTEGER v;
				GetProcessTimes (GetCurrentProcess (), &c, &e, &k, &u);
				v.LowPart = c.dwLowDateTime;
				v.HighPart = c.dwHighDateTime;
				return (EIF_INTEGER_64) v.QuadPart;
			]"
		end

end
