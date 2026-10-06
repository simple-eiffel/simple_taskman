note
	description: "[
		The machine's clocks: GetSystemTimePreciseAsFileTime for UTC,
		QueryPerformanceCounter for monotonic time, and a blocking Sleep, so
		the collector may run while this processor waits (C-015, A-103).
	]"
	author: "Larry Rix"

class
	TM_SYSTEM_CLOCK

inherit
	TM_CLOCK

create
	make

feature {NONE} -- Initialization

	make
			-- Read the performance counter frequency once.
		do
			frequency := c_qpc_frequency
		ensure
			frequency_known: frequency > 0
		end

feature -- Access

	utc_ticks: INTEGER_64
			-- Now, UTC ticks since 1601.
		do
			Result := c_precise_utc_ticks
		end

	monotonic_ticks: INTEGER_64
			-- Split so that counter * 10^7 cannot overflow: a 10 MHz counter would
			-- overflow the naive product after about 10 days of uptime.
		local
			l_count: INTEGER_64
		do
			l_count := c_qpc_count
			Result := (l_count // frequency) * Ticks_per_second
				+ ((l_count \\ frequency) * Ticks_per_second) // frequency
		end

feature -- Basic operations

	sleep_ms (a_ms: INTEGER)
			-- Block this processor for `a_ms' milliseconds.
		do
			c_sleep (a_ms)
		end

feature {NONE} -- Implementation

	frequency: INTEGER_64
			-- Performance counter ticks per second.

	c_precise_utc_ticks: INTEGER_64
		external
			"C inline use <windows.h>"
		alias
			"[
				#if _WIN32_WINNT < 0x0602
				#error "simple_taskman needs _WIN32_WINNT >= 0x0602 (Windows 8 API): keep the external_cflag of simple_taskman.ecf"
				#endif
				FILETIME ft;
				ULARGE_INTEGER u;
				GetSystemTimePreciseAsFileTime (&ft);
				u.LowPart = ft.dwLowDateTime;
				u.HighPart = ft.dwHighDateTime;
				return (EIF_INTEGER_64) u.QuadPart;
			]"
		end

	c_qpc_count: INTEGER_64
		external
			"C inline use <windows.h>"
		alias
			"[
				LARGE_INTEGER c;
				QueryPerformanceCounter (&c);
				return (EIF_INTEGER_64) c.QuadPart;
			]"
		end

	c_qpc_frequency: INTEGER_64
		external
			"C inline use <windows.h>"
		alias
			"[
				LARGE_INTEGER f;
				QueryPerformanceFrequency (&f);
				return (EIF_INTEGER_64) f.QuadPart;
			]"
		end

	c_sleep (a_ms: INTEGER)
			-- Blocking: the collector may run while this thread sleeps (C-015, A-103).
		external
			"C blocking inline use <windows.h>"
		alias
			"Sleep ((DWORD) $a_ms);"
		end

invariant
	frequency_known: frequency > 0

end
