note
	description: "[
		Timeline ticks (UTC, 100 ns since 1601) shown as this machine's local
		clock time, for people: "10/06 14:05:09". Uses the system's current
		time-zone rules (FileTimeToLocalFileTime).
	]"
	author: "Larry Rix"

class
	TM_LOCAL_TIME

feature -- Access

	text (a_ticks: INTEGER_64): STRING_32
			-- `a_ticks' as local "MM/DD HH:MM:SS"; "--" when it is not a time.
		local
			l_parts: MANAGED_POINTER
		do
			create l_parts.make (5 * 4)
			if a_ticks > 0 and then c_local_parts (a_ticks, l_parts.item) then
				Result := two (l_parts.read_integer_32 (12)) + {STRING_32} "/" + two (l_parts.read_integer_32 (16))
					+ {STRING_32} " " + two (l_parts.read_integer_32 (0)) + {STRING_32} ":" + two (l_parts.read_integer_32 (4))
					+ {STRING_32} ":" + two (l_parts.read_integer_32 (8))
			else
				create Result.make_from_string ({STRING_32} "--")
			end
		ensure
			fixed_or_dashes: Result.count = 14 or Result.same_string ({STRING_32} "--")
		end

feature {NONE} -- Implementation

	two (a_value: INTEGER): STRING_32
			-- `a_value' as at least two digits.
		do
			Result := a_value.out.to_string_32
			if Result.count < 2 then
				Result.prepend_character ('0')
			end
		end

	c_local_parts (a_ticks: INTEGER_64; a_out: POINTER): BOOLEAN
			-- Hour, minute, second, month, day of local time into five 32-bit integers.
		external
			"C inline use <windows.h>"
		alias
			"[
				FILETIME l_utc, l_local;
				SYSTEMTIME l_time;
				int *l_out = (int *) $a_out;
				l_utc.dwLowDateTime = (DWORD) ($a_ticks & 0xFFFFFFFF);
				l_utc.dwHighDateTime = (DWORD) ($a_ticks >> 32);
				if (!FileTimeToLocalFileTime (&l_utc, &l_local) || !FileTimeToSystemTime (&l_local, &l_time)) return EIF_FALSE;
				l_out [0] = l_time.wHour; l_out [1] = l_time.wMinute; l_out [2] = l_time.wSecond;
				l_out [3] = l_time.wMonth; l_out [4] = l_time.wDay;
				return EIF_TRUE;
			]"
		end

end
