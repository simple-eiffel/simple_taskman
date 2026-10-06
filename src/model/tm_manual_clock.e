note
	description: "[
		A clock that moves only when told: for tests and replay. `sleep_ms'
		advances both counters, so a scripted sampler sees time pass. UTC may
		be set backward (to test A-109); the monotonic counter never moves back.
	]"
	author: "Larry Rix"

class
	TM_MANUAL_CLOCK

inherit
	TM_CLOCK

create
	make

feature {NONE} -- Initialization

	make (a_utc_ticks, a_monotonic_ticks: INTEGER_64)
			-- Clock reading `a_utc_ticks' and `a_monotonic_ticks'.
		require
			utc_positive: a_utc_ticks > 0
			monotonic_non_negative: a_monotonic_ticks >= 0
		do
			current_utc := a_utc_ticks
			current_monotonic := a_monotonic_ticks
		ensure
			utc_kept: utc_ticks = a_utc_ticks
			monotonic_kept: monotonic_ticks = a_monotonic_ticks
		end

feature -- Access

	utc_ticks: INTEGER_64
			-- Current UTC reading.
		do
			Result := current_utc
		end

	monotonic_ticks: INTEGER_64
			-- Current monotonic reading.
		do
			Result := current_monotonic
		end

feature -- Element change

	advance (a_ticks: INTEGER_64)
			-- Move both counters forward by `a_ticks'.
		require
			non_negative: a_ticks >= 0
		do
			current_utc := current_utc + a_ticks
			current_monotonic := current_monotonic + a_ticks
		ensure
			utc_moved: utc_ticks = old utc_ticks + a_ticks
			monotonic_moved: monotonic_ticks = old monotonic_ticks + a_ticks
		end

	set_utc (a_ticks: INTEGER_64)
			-- Set the wall clock alone, possibly backward (A-109).
		require
			positive: a_ticks > 0
		do
			current_utc := a_ticks
		ensure
			utc_set: utc_ticks = a_ticks
			monotonic_unchanged: monotonic_ticks = old monotonic_ticks
		end

feature -- Basic operations

	sleep_ms (a_ms: INTEGER)
			-- Advance both counters by `a_ms' milliseconds; returns at once.
		do
			advance (a_ms.to_integer_64 * (Ticks_per_second // 1000))
		ensure then
			monotonic_moved: monotonic_ticks = old monotonic_ticks + a_ms.to_integer_64 * (Ticks_per_second // 1000)
		end

feature {NONE} -- Implementation

	current_utc: INTEGER_64
	current_monotonic: INTEGER_64

invariant
	utc_positive: current_utc > 0
	monotonic_non_negative: current_monotonic >= 0

end
