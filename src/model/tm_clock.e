note
	description: "[
		The source of "now", injected so tests and replay control time.
		Ticks are 100 ns. UTC ticks count from 1601-01-01 (Windows file time);
		monotonic ticks count from an arbitrary origin.

		"Never runs backward" is a property of a sequence of calls. Stating it
		as a postcondition would force the query to remember its last answer,
		a side effect in a query, so it is enforced where it matters: the
		precondition `ordered' of TM_FRAME_BUILDER.build.
	]"
	author: "Larry Rix"

deferred class
	TM_CLOCK

feature -- Constants

	Ticks_per_second: INTEGER_64 = 10_000_000
			-- 100 ns ticks in one second; defined once, here.

feature -- Access

	utc_ticks: INTEGER_64
			-- Now, in 100 ns ticks since 1601-01-01 UTC.
		deferred
		ensure
			after_1601: Result > 0
		end

	monotonic_ticks: INTEGER_64
			-- A counter that never runs backward, in 100 ns ticks.
		deferred
		ensure
			non_negative: Result >= 0
		end

feature -- Basic operations

	sleep_ms (a_ms: INTEGER)
			-- Wait `a_ms' milliseconds.
		require
			non_negative: a_ms >= 0
		deferred
		end

end
