note
	description: "[
		One processor's worth of CPU load: spins on arithmetic until a
		monotonic deadline. Created as a separate object, so each spinner
		runs on its own SCOOP processor.
	]"
	author: "Larry Rix"

class
	TM_SPINNER

create
	make

feature {NONE} -- Initialization

	make
			-- Idle spinner.
		do
		ensure
			idle: iterations = 0 and not is_done
		end

feature -- Access

	iterations: INTEGER_64
			-- Arithmetic rounds completed.

	checksum: INTEGER_64
			-- Result of the arithmetic, kept so the work cannot be optimized away.

feature -- Status report

	is_done: BOOLEAN
			-- Has `spin' finished?

feature -- Execution

	spin (a_ms: INTEGER)
			-- Keep one logical processor busy for `a_ms' milliseconds.
		require
			positive: a_ms > 0
		local
			l_clock: TM_SYSTEM_CLOCK
			l_deadline: INTEGER_64
			i: INTEGER
		do
			create l_clock.make
			l_deadline := l_clock.monotonic_ticks + a_ms.to_integer_64 * 10_000
			from
			until
				l_clock.monotonic_ticks >= l_deadline
			loop
				from
					i := 1
				until
					i > 100_000
				loop
					checksum := (checksum * 31 + i) \\ 1_000_000_007
					i := i + 1
				end
				iterations := iterations + 1
			end
			is_done := True
		ensure
			done: is_done
			worked: iterations > 0
		end

end
