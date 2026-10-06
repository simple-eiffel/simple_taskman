note
	description: "[
		The one place a reading or a rate becomes text, used by the window,
		the CLI, and the verdict sentences alike (DR-017). A missing value
		becomes its status words, never a number.
	]"
	author: "Larry Rix"

class
	TM_FORMAT

feature -- Readings

	reading_text (a_reading: TM_READING; a_metric: TM_METRIC): STRING_32
			-- "61.2 W", "23%", "1.2 GB", or the status words. Never a number for a missing value.
		do
			if a_reading.is_available then
				Result := value_text (a_reading.value, a_metric.unit)
			else
				Result := a_reading.status_name.to_string_32
			end
		ensure
			words_when_missing: not a_reading.is_available implies Result.same_string_general (a_reading.status_name)
			number_when_available: a_reading.is_available implies Result.same_string (value_text (a_reading.value, a_metric.unit))
		end

	value_text (a_value: REAL_64; a_unit: READABLE_STRING_8): STRING_32
			-- `a_value' with `a_unit': bytes scaled to KB, MB, GB, TB; percent with no space; others with one space.
		require
			finite: not (a_value.is_nan or a_value.is_positive_infinity or a_value.is_negative_infinity)
			unit_given: not a_unit.is_empty
		do
			if a_unit.same_string ("B") then
				Result := bytes (rounded_count (a_value))
			elseif a_unit.same_string ("B/s") then
				Result := bytes_per_second (a_value.max (0.0))
			elseif a_unit.same_string ("%%") then
				Result := one_decimal (a_value) + {STRING_32} "%%"
			elseif a_unit [1] = '/' then
				Result := one_decimal (a_value) + a_unit.to_string_32
			else
				Result := one_decimal (a_value) + {STRING_32} " " + a_unit.to_string_32
			end
		ensure
			not_empty: not Result.is_empty
			ends_with_unit: Result.ends_with (a_unit.to_string_32)
		end

feature -- Process columns

	cores (a_cores: REAL_64): STRING_32
			-- "2.4 cores", "1 core", "0.0 cores".
		require
			non_negative: a_cores >= 0.0
		do
			if a_cores = 1.0 then
				Result := {STRING_32} "1 core"
			else
				Result := one_decimal (a_cores) + {STRING_32} " cores"
			end
		ensure
			not_empty: not Result.is_empty
		end

	percent (a_percent: REAL_64): STRING_32
			-- "4.1%"; one decimal.
		require
			non_negative: a_percent >= 0.0
		do
			Result := one_decimal (a_percent) + {STRING_32} "%%"
		ensure
			not_empty: not Result.is_empty
			percent_sign: Result.ends_with ({STRING_32} "%%")
		end

	bytes (a_bytes: INTEGER_64): STRING_32
			-- "812 MB"; binary multiples, labelled KB, MB, GB, TB as Task Manager does.
		require
			non_negative: a_bytes >= 0
		do
			if a_bytes < 1024 then
				Result := a_bytes.out.to_string_32 + {STRING_32} " B"
			else
				Result := scaled (a_bytes.to_double)
			end
		ensure
			not_empty: not Result.is_empty
			ends_in_b: Result.ends_with ({STRING_32} "B")
		end

	bytes_per_second (a_rate: REAL_64): STRING_32
			-- "1.2 MB/s".
		require
			non_negative: a_rate >= 0.0
		do
			Result := bytes (rounded_count (a_rate)) + {STRING_32} "/s"
		ensure
			not_empty: not Result.is_empty
			per_second: Result.ends_with ({STRING_32} "/s")
		end

	one_decimal (a_value: REAL_64): STRING_32
			-- `a_value' rounded half away from zero to one decimal: "61.2", "-3.5", "0.0".
			-- The only rounding rule in the library, so every view rounds alike.
		require
			finite: not (a_value.is_nan or a_value.is_positive_infinity or a_value.is_negative_infinity)
		local
			l_tenths: INTEGER_64
		do
			l_tenths := (a_value.abs * 10.0 + 0.5).floor_real_64.truncated_to_integer_64
			create Result.make (12)
			if a_value < 0.0 and l_tenths > 0 then
				Result.append_character ('-')
			end
			Result.append_string_general ((l_tenths // 10).out)
			Result.append_character ('.')
			Result.append_string_general ((l_tenths \\ 10).out)
		ensure
			one_decimal_place: Result.count >= 3 and then Result [Result.count - 1] = '.'
		end

	status_word (a_status: INTEGER): STRING_32
			-- Short word for a grid cell whose group is not available.
		require
			not_available: a_status >= {TM_READING_STATUS}.Unavailable and a_status <= {TM_READING_STATUS}.Invalid
		do
			inspect a_status
			when {TM_READING_STATUS}.Unavailable then
				Result := {STRING_32} "n/a"
			when {TM_READING_STATUS}.Not_supported then
				Result := {STRING_32} "not supported"
			when {TM_READING_STATUS}.Access_denied then
				Result := {STRING_32} "denied"
			else
				Result := {STRING_32} "invalid"
			end
		ensure
			not_empty: not Result.is_empty
			not_a_number: not Result.is_integer and not Result.is_double
		end

feature {NONE} -- Implementation

	rounded_count (a_value: REAL_64): INTEGER_64
			-- `a_value' rounded to a whole, non-negative count.
		require
			finite: not (a_value.is_nan or a_value.is_positive_infinity or a_value.is_negative_infinity)
		do
			Result := (a_value.max (0.0) + 0.5).floor_real_64.truncated_to_integer_64
		ensure
			non_negative: Result >= 0
		end

	scaled (a_bytes: REAL_64): STRING_32
			-- `a_bytes' (at least 1024) in KB, MB, GB, or TB, one decimal.
		require
			at_least_a_kilobyte: a_bytes >= 1024.0
		local
			l_value: REAL_64
			l_unit: INTEGER
		do
			from
				l_value := a_bytes / 1024.0
				l_unit := 1
			until
				l_value < 1024.0 or l_unit = 4
			loop
				l_value := l_value / 1024.0
				l_unit := l_unit + 1
			end
			Result := one_decimal (l_value) + {STRING_32} " " + Unit_names [l_unit]
		ensure
			ends_in_b: Result.ends_with ({STRING_32} "B")
		end

	Unit_names: ARRAY [STRING_32]
			-- Binary multiples, labelled as Task Manager labels them.
		once
			Result := <<{STRING_32} "KB", {STRING_32} "MB", {STRING_32} "GB", {STRING_32} "TB">>
		end

end
