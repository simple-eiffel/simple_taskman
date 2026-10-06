note
	description: "[
		What a metric is: stable name, unit, valid range, and how it
		aggregates. Names are part of the trace format, so a name, once
		recorded, is never reused for something else.
	]"
	author: "Larry Rix"

class
	TM_METRIC

create
	make

feature {NONE} -- Initialization

	make (a_code: INTEGER; a_name, a_unit: STRING_8; a_label: STRING_32;
			a_minimum, a_maximum: REAL_64; a_is_instanced, a_is_peak: BOOLEAN)
			-- Metric `a_code' named `a_name', measured in `a_unit', valid in [`a_minimum', `a_maximum'].
		require
			code_positive: a_code > 0
			name_valid: is_valid_name (a_name)
			unit_given: not a_unit.is_empty
			label_given: not a_label.is_empty
			ordered_range: a_minimum <= a_maximum
		do
			code := a_code
			name := a_name.twin
			unit := a_unit.twin
			label := a_label.twin
			minimum := a_minimum
			maximum := a_maximum
			is_instanced := a_is_instanced
			is_peak := a_is_peak
		ensure
			kept: code = a_code and name.same_string (a_name) and minimum = a_minimum and maximum = a_maximum
			text_kept: unit.same_string (a_unit) and label.same_string (a_label)
			flags_kept: is_instanced = a_is_instanced and is_peak = a_is_peak
		end

feature -- Access

	code: INTEGER
			-- Registry code; never reused.

	name: STRING_8
			-- Dotted lowercase, for example "cpu.package_watts". Persistent: part of the trace format.

	unit: STRING_8
			-- Unit symbol, for example "W" or "B/s".

	label: STRING_32
			-- Human label for views.

	minimum: REAL_64
			-- Smallest value this metric can truly take.

	maximum: REAL_64
			-- Largest value this metric can truly take.

	is_instanced: BOOLEAN
			-- Per core, per disk, per volume?

	is_peak: BOOLEAN
			-- Aggregate by maximum rather than duration-weighted mean?

feature -- Status report

	accepts (a_value: REAL_64): BOOLEAN
			-- Is `a_value' a value this metric can truly take?
		do
			Result := not (a_value.is_nan or a_value.is_positive_infinity or a_value.is_negative_infinity)
				and then a_value >= minimum and then a_value <= maximum
		ensure
			definition: Result = (not (a_value.is_nan or a_value.is_positive_infinity or a_value.is_negative_infinity)
				and then (a_value >= minimum and a_value <= maximum))
		end

	is_valid_name (a_name: READABLE_STRING_8): BOOLEAN
			-- Lowercase letters, digits, underscores, and single dots; no leading or trailing dot.
		local
			i: INTEGER
			c, l_previous: CHARACTER_8
		do
			Result := not a_name.is_empty and then a_name [1] /= '.' and then a_name [a_name.count] /= '.'
			from
				i := 1
			until
				not Result or i > a_name.count
			loop
				c := a_name [i]
				if c = '.' then
					Result := l_previous /= '.'
				else
					Result := (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c = '_'
				end
				l_previous := c
				i := i + 1
			end
		ensure
			empty_refused: a_name.is_empty implies not Result
		end

invariant
	code_positive: code > 0
	ordered_range: minimum <= maximum
	unit_given: not unit.is_empty

end
