note
	description: "[
		What makes a process the same process: its pid together with its
		creation time. A pid alone is a hotel room number; Windows hands it to
		the next guest as soon as the last one leaves.
	]"
	author: "Larry Rix"

class
	TM_PROCESS_ID

inherit
	HASHABLE
		redefine
			is_equal
		end

create
	make

feature {NONE} -- Initialization

	make (a_pid, a_creation_ticks: INTEGER_64)
			-- Identity of process `a_pid' created at `a_creation_ticks' (UTC, 100 ns since 1601).
		require
			pid_non_negative: a_pid >= 0
			creation_non_negative: a_creation_ticks >= 0
		do
			pid := a_pid
			creation_ticks := a_creation_ticks
		ensure
			kept: pid = a_pid and creation_ticks = a_creation_ticks
		end

feature -- Access

	pid: INTEGER_64
			-- Process id; reused by Windows.

	creation_ticks: INTEGER_64
			-- Creation time in UTC ticks; 0 for the idle pseudo-process.

	hash_code: INTEGER
			-- Hash over both fields.
		do
			Result := (pid * 31 + creation_ticks).bit_and (0x7FFF_FFFF).to_integer_32
		end

feature -- Comparison

	is_equal (other: like Current): BOOLEAN
			-- Same pid and same creation time?
		do
			Result := pid = other.pid and creation_ticks = other.creation_ticks
		ensure then
			both_fields: Result = (pid = other.pid and creation_ticks = other.creation_ticks)
		end

feature -- Status report

	is_idle_pseudo_process: BOOLEAN
			-- The "System Idle Process" entry, whose CPU time is idle time (A-111).
		do
			Result := pid = 0
		end

invariant
	pid_non_negative: pid >= 0
	creation_non_negative: creation_ticks >= 0

end
