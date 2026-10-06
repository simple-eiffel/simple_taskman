note
	description: "[
		An aggregate over a window, with its coverage: the share of the
		window's span in which the metric was actually measured. A
		discontinuity adds span but never coverage, so an aggregate over a
		sleeping laptop says how little it saw.
	]"
	author: "Larry Rix"

class
	TM_AGGREGATE

create
	make

feature {NONE} -- Initialization

	make (a_kind: INTEGER; a_reading: TM_READING; a_coverage, a_measured_seconds: REAL_64)
			-- Aggregate of `a_kind' with result `a_reading', measured over `a_coverage' of the span.
		require
			known_kind: a_kind = Weighted_mean or a_kind = Peak
			coverage_bounded: a_coverage >= 0.0 and a_coverage <= 1.0
			seconds_non_negative: a_measured_seconds >= 0.0
			unavailable_when_unmeasured: a_coverage = 0.0 implies not a_reading.is_available
		do
			kind := a_kind
			reading := a_reading
			coverage := a_coverage
			measured_seconds := a_measured_seconds
		ensure
			kept: kind = a_kind and reading = a_reading and coverage = a_coverage and measured_seconds = a_measured_seconds
		end

feature -- Kinds

	Weighted_mean: INTEGER = 1
			-- Duration-weighted mean.

	Peak: INTEGER = 2
			-- Maximum.

feature -- Access

	kind: INTEGER
			-- `Weighted_mean' or `Peak'.

	reading: TM_READING
			-- The aggregate value, or why there is none.

	coverage: REAL_64
			-- Measured duration over window span, 0..1.

	measured_seconds: REAL_64
			-- Seconds in which the metric was measured.

invariant
	known_kind: kind = Weighted_mean or kind = Peak
	coverage_bounded: coverage >= 0.0 and coverage <= 1.0
	seconds_non_negative: measured_seconds >= 0.0
	unavailable_when_unmeasured: coverage = 0.0 implies not reading.is_available

end
