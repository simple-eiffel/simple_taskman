note
	description: "[
		`taskman_cli clockwatch': answers spike O-2's open question (spec 10):
		does the monotonic counter (QueryPerformanceCounter) keep counting
		while the machine sleeps? Reads both clocks once a second; any second
		in which wall time and monotonic time part by more than 2 s is shown,
		with which one jumped. Put the machine to sleep for a minute while it
		runs, then wake it.

		- Wall jumped, monotonic did not: the counter stops during sleep, so a
		  sleep looks like a forward clock change rather than a gap.
		- Both jumped together: the counter keeps counting, so a sleep is a
		  monotonic gap and becomes a discontinuity frame (A-110).
	]"
	author: "Larry Rix"

class
	TM_CLOCK_WATCH_COMMAND

create
	make

feature {NONE} -- Initialization

	make (a_seconds: INTEGER)
			-- Watch for `a_seconds'.
		require
			sane: a_seconds >= 2 and a_seconds <= 86_400
		do
			seconds := a_seconds
			create output.make_empty
		ensure
			kept: seconds = a_seconds
		end

feature -- Access

	seconds: INTEGER
	output: STRING_32
	exit_code: INTEGER
	jumps: INTEGER
			-- Seconds in which the clocks parted by more than 2 s.

feature -- Execution

	execute
			-- Watch both clocks; describe every jump.
		local
			l_clock: TM_SYSTEM_CLOCK
			l_utc, l_mono, l_last_utc, l_last_mono, l_wall, l_monotonic: INTEGER_64
			l_start: INTEGER_64
			l_format: TM_FORMAT
		do
			create l_clock.make
			create l_format
			create output.make (1024)
			l_last_utc := l_clock.utc_ticks
			l_last_mono := l_clock.monotonic_ticks
			l_start := l_last_mono
			from
			until
				l_clock.monotonic_ticks - l_start >= seconds.to_integer_64 * Tps
			loop
				l_clock.sleep_ms (1000)
				l_utc := l_clock.utc_ticks
				l_mono := l_clock.monotonic_ticks
				l_wall := l_utc - l_last_utc
				l_monotonic := l_mono - l_last_mono
				if (l_wall - l_monotonic).abs > 2 * Tps then
					jumps := jumps + 1
					output.append ({STRING_32} "jump: wall advanced " + l_format.one_decimal (l_wall / Tps)
						+ {STRING_32} " s, monotonic advanced " + l_format.one_decimal (l_monotonic / Tps) + {STRING_32} " s -> ")
					if l_monotonic < 3 * Tps then
						output.append ({STRING_32} "the monotonic counter STOPPED (sleep looks like a clock change)%N")
					else
						output.append ({STRING_32} "both moved: the wall clock was changed%N")
					end
				elseif l_monotonic > 5 * Tps then
					jumps := jumps + 1
					output.append ({STRING_32} "gap: both advanced " + l_format.one_decimal (l_monotonic / Tps)
						+ {STRING_32} " s together -> the monotonic counter KEPT COUNTING (sleep is a discontinuity)%N")
				end
				l_last_utc := l_utc
				l_last_mono := l_mono
			end
			output.append ({STRING_32} "watched " + seconds.out.to_string_32 + {STRING_32} " s of monotonic time; jumps or gaps: "
				+ jumps.out.to_string_32 + {STRING_32} "%N")
			exit_code := 0
		ensure
			reported: not output.is_empty
		end

feature {NONE} -- Implementation

	Tps: INTEGER_64 = 10_000_000

end
