note
	description: "[
		Frame to text and back, lossless and versioned (TMF1). One record per
		line, tab-separated. Integers are decimal; reals are 16 hexadecimal
		digits of their IEEE 754 bits, so encode then decode is exact (DR-018).
		Text is UTF-8 with tab, newline, carriage return, and backslash escaped.

		    TMF1  start end duration processors discontinuity clock_adjusted complete omitted
		    R     metric_code instance status value_bits
		    A     pid creation name parent session threads handles new
		          cpu_status cores_bits memory_status working_set private_bytes
		          io_status read_bps_bits write_bps_bits
		    B     pid creation
		    X     pid creation name

		Capabilities use TMC1 with one M line per metric (code, status, reason)
		and S lines for the process source (kind) and why native was refused
		(fallback).

		Decoding rejects unknown headers, wrong field counts, and unknown
		metric codes, naming the line. Every value goes back through
		TM_READING.make_measured or the activity's own checks, so a damaged
		recording can produce an invalid reading but never an impossible value.
	]"
	author: "Larry Rix"

class
	TM_FRAME_CODEC

inherit
	TM_SHARED_METRICS

create
	make

feature {NONE} -- Initialization

	make
			-- Codec with nothing decoded.
		do
			create last_error.make_empty
			create last_capabilities_error.make_empty
			create line_failure.make_empty
		ensure
			nothing_decoded: not has_frame and not has_capabilities
		end

feature -- Constants

	Header: STRING_8 = "TMF1"
			-- First field of a frame's first line.

	Capabilities_header: STRING_8 = "TMC1"
			-- First field of a capability report's first line.

feature -- Encoding

	encode (a_frame: TM_FRAME): STRING_8
			-- `a_frame' as TMF1 text.
		do
			create Result.make (4096)
			Result.append (Header)
			append_field (Result, a_frame.start_ticks.out)
			append_field (Result, a_frame.end_ticks.out)
			append_field (Result, a_frame.duration.out)
			append_field (Result, a_frame.logical_processors.out)
			append_field (Result, flag (a_frame.is_discontinuity))
			append_field (Result, flag (a_frame.is_clock_adjusted))
			append_field (Result, flag (a_frame.is_complete))
			append_field (Result, a_frame.omitted_processes.out)
			Result.append_character ('%N')
			across metrics.codes as ic loop
				if metrics.metric (ic).is_instanced then
					across a_frame.readings.instances (ic) as ic_instance loop
						append_reading (Result, ic, ic_instance, a_frame.readings.reading (ic, ic_instance))
					end
				elseif a_frame.readings.has (ic, {STRING_32} "") then
					append_reading (Result, ic, {STRING_32} "", a_frame.readings.reading (ic, {STRING_32} ""))
				end
			end
			across a_frame.activities as ic loop
				append_activity (Result, ic)
			end
			across a_frame.born as ic loop
				Result.append ("B")
				append_field (Result, ic.pid.out)
				append_field (Result, ic.creation_ticks.out)
				Result.append_character ('%N')
			end
			across a_frame.exited as ic loop
				Result.append ("X")
				append_field (Result, ic.id.pid.out)
				append_field (Result, ic.id.creation_ticks.out)
				append_field (Result, escaped (ic.name))
				Result.append_character ('%N')
			end
		ensure
			versioned: Result.starts_with (Header)
			decodable: is_well_formed (Result)
			every_activity: activity_count_in (Result) = a_frame.activity_count
		end

	encode_capabilities (a_capabilities: TM_CAPABILITIES): STRING_8
			-- `a_capabilities' as TMC1 text.
		do
			create Result.make (2048)
			Result.append (Capabilities_header)
			Result.append_character ('%N')
			across metrics.codes as ic loop
				if a_capabilities.has (ic) then
					Result.append ("M")
					append_field (Result, ic.out)
					append_field (Result, a_capabilities.support_of (ic).out)
					append_field (Result, escaped (a_capabilities.reason_of (ic)))
					Result.append_character ('%N')
				end
			end
			Result.append ("S%Tkind")
			append_field (Result, escaped (a_capabilities.process_source_kind.to_string_32))
			Result.append ("%NS%Tfallback")
			append_field (Result, escaped (a_capabilities.fallback_reason))
			Result.append_character ('%N')
		ensure
			versioned: Result.starts_with (Capabilities_header)
		end

feature -- Decoding

	decode (a_text: READABLE_STRING_8)
			-- Rebuild a frame from `a_text', or say which line failed.
		local
			l_lines: LIST [STRING_8]
			l_fields: LIST [STRING_8]
			l_problem: STRING_32
			l_line_number, l_processors, l_omitted: INTEGER
			l_start, l_end, l_duration: INTEGER_64
			l_discontinuity, l_adjusted: BOOLEAN
			l_readings: TM_READINGS
			l_activities: HASH_TABLE [TM_PROCESS_ACTIVITY, TM_PROCESS_ID]
			l_born: ARRAYED_LIST [TM_PROCESS_ID]
			l_exited: ARRAYED_LIST [TM_PROCESS_SAMPLE]
		do
			last_frame_cell := Void
			create l_problem.make_empty
			l_line_number := first_bad_line (a_text)
			if l_line_number > 0 then
				l_problem := line_problem (l_line_number, {STRING_32} "unknown header or record, or wrong field count")
			else
				l_lines := a_text.to_string_8.split ('%N')
				l_fields := l_lines.first.split ('%T')
				if not (is_int64 (l_fields [2]) and is_int64 (l_fields [3]) and is_int64 (l_fields [4])
						and is_count (l_fields [5]) and is_flag (l_fields [6]) and is_flag (l_fields [7])
						and is_flag (l_fields [8]) and is_count (l_fields [9])) then
					l_problem := line_problem (1, {STRING_32} "header field is not a number or flag")
				else
					l_start := l_fields [2].to_integer_64
					l_end := l_fields [3].to_integer_64
					l_duration := l_fields [4].to_integer_64
					l_processors := l_fields [5].to_integer
					l_discontinuity := l_fields [6].same_string ("1")
					l_adjusted := l_fields [7].same_string ("1")
					l_omitted := l_fields [9].to_integer
					if not (l_end > l_start and l_duration > 0 and l_processors > 0) then
						l_problem := line_problem (1, {STRING_32} "span, duration, or processor count impossible")
					end
				end
				create l_readings.make
				create l_activities.make (64)
				create l_born.make (8)
				create l_exited.make (8)
				from
					l_line_number := 2
				until
					not l_problem.is_empty or l_line_number > l_lines.count
				loop
					l_fields := l_lines [l_line_number].split ('%T')
					if l_lines [l_line_number].is_empty then
							-- the final newline
					elseif l_fields.first.same_string ("R") then
						decode_reading (l_fields, l_line_number, l_readings)
						l_problem := line_failure
					elseif l_fields.first.same_string ("A") then
						decode_activity (l_fields, l_line_number, l_processors, l_activities)
						l_problem := line_failure
					elseif l_fields.first.same_string ("B") then
						if is_count64 (l_fields [2]) and is_count64 (l_fields [3]) then
							l_born.extend (create {TM_PROCESS_ID}.make (l_fields [2].to_integer_64, l_fields [3].to_integer_64))
						else
							l_problem := line_problem (l_line_number, {STRING_32} "bad identity")
						end
					else
						if is_count64 (l_fields [2]) and is_count64 (l_fields [3]) and is_valid_escaped (l_fields [4]) then
							l_exited.extend (create {TM_PROCESS_SAMPLE}.make (
								create {TM_PROCESS_ID}.make (l_fields [2].to_integer_64, l_fields [3].to_integer_64),
								unescaped (l_fields [4]), 0, 0, 0))
						else
							l_problem := line_problem (l_line_number, {STRING_32} "bad exited process")
						end
					end
					l_line_number := l_line_number + 1
				end
				if l_problem.is_empty and l_discontinuity and (not l_activities.is_empty or not l_born.is_empty) then
					l_problem := line_problem (1, {STRING_32} "a discontinuity frame carries processes")
				end
				if l_problem.is_empty and then across l_exited as ic some l_activities.has (ic.id) end then
					l_problem := {STRING_32} "an exited process also has an activity"
				end
				if l_problem.is_empty then
					last_frame_cell := create {TM_FRAME}.make_decoded (l_start, l_end, l_duration, l_processors,
						l_discontinuity, l_adjusted, l_omitted, l_readings, l_activities, l_born, l_exited)
				end
			end
			last_error := l_problem
		ensure
			decoded_or_said_why: has_frame xor not last_error.is_empty
			round_trip_shape: has_frame implies last_frame.activity_count = activity_count_in (a_text)
			refused_when_malformed: not is_well_formed (a_text) implies not has_frame
		end

	decode_capabilities (a_text: READABLE_STRING_8)
			-- Rebuild a capability report from `a_text', or say why not.
		local
			l_lines: LIST [STRING_8]
			l_fields: LIST [STRING_8]
			l_problem: STRING_32
			l_caps: TM_CAPABILITIES
			l_kind: STRING_8
			l_fallback: STRING_32
			l_line_number, l_code, l_status: INTEGER
		do
			last_capabilities_cell := Void
			create l_problem.make_empty
			create l_kind.make_empty
			create l_fallback.make_empty
			create l_caps.make_empty
			l_lines := a_text.to_string_8.split ('%N')
			if not l_lines.first.same_string (Capabilities_header) then
				l_problem := line_problem (1, {STRING_32} "not a TMC1 capability report")
			end
			from
				l_line_number := 2
			until
				not l_problem.is_empty or l_line_number > l_lines.count
			loop
				l_fields := l_lines [l_line_number].split ('%T')
				if l_lines [l_line_number].is_empty then
						-- the final newline
				elseif l_fields.first.same_string ("M") and l_fields.count = 4 then
					if l_fields [2].is_integer and l_fields [3].is_integer and is_valid_escaped (l_fields [4]) then
						l_code := l_fields [2].to_integer
						l_status := l_fields [3].to_integer
						if metrics.has_code (l_code) and then not l_caps.has (l_code)
								and then l_status >= {TM_READING_STATUS}.Available and l_status <= {TM_READING_STATUS}.Invalid then
							l_caps.put (l_code, l_status, unescaped (l_fields [4]))
						else
							l_problem := line_problem (l_line_number, {STRING_32} "unknown or repeated metric, or bad status")
						end
					else
						l_problem := line_problem (l_line_number, {STRING_32} "bad metric line")
					end
				elseif l_fields.first.same_string ("S") and l_fields.count = 3 and then is_valid_escaped (l_fields [3]) then
					if l_fields [2].same_string ("kind") then
						l_kind := utf.string_32_to_utf_8_string_8 (unescaped (l_fields [3]))
					elseif l_fields [2].same_string ("fallback") then
						l_fallback := unescaped (l_fields [3])
					else
						l_problem := line_problem (l_line_number, {STRING_32} "unknown source line")
					end
				else
					l_problem := line_problem (l_line_number, {STRING_32} "unknown record or wrong field count")
				end
				l_line_number := l_line_number + 1
			end
			if l_problem.is_empty and l_kind.is_empty then
				l_problem := {STRING_32} "no process source kind"
			end
			if l_problem.is_empty then
				l_caps.set_process_source (l_kind, l_fallback)
				last_capabilities_cell := l_caps
			end
			last_capabilities_error := l_problem
		ensure
			decoded_or_said_why: has_capabilities xor not last_capabilities_error.is_empty
			frame_error_untouched: last_error ~ old last_error
		end

	frame_texts_in (a_text: READABLE_STRING_8): ARRAYED_LIST [STRING_8]
			-- The frames of a replay file, each beginning with its TMF1 line, in order.
		local
			l_current: detachable STRING_8
		do
			create Result.make (16)
			across a_text.to_string_8.split ('%N') as ic loop
				if ic.starts_with (Header + "%T") then
					if attached l_current as al_current then
						Result.extend (al_current)
					end
					create l_current.make_from_string (ic)
					l_current.append_character ('%N')
				elseif attached l_current as al_current and then not ic.is_empty then
					al_current.append (ic)
					al_current.append_character ('%N')
				end
			end
			if attached l_current as al_current then
				Result.extend (al_current)
			end
		ensure
			each_versioned: across Result as ic all ic.starts_with (Header) end
		end

feature -- Access

	last_frame: TM_FRAME
			-- Frame from the last successful `decode'.
		require
			has_frame: has_frame
		do
			check attached last_frame_cell as al_frame then
				Result := al_frame
			end
		end

	last_capabilities: TM_CAPABILITIES
			-- Report from the last successful `decode_capabilities'.
		require
			has_capabilities: has_capabilities
		do
			check attached last_capabilities_cell as al_capabilities then
				Result := al_capabilities
			end
		end

	last_error: STRING_32
			-- Why the last `decode' failed, naming the line; empty after a success.

	last_capabilities_error: STRING_32
			-- Why the last `decode_capabilities' failed; empty after a success (review issue 16).

feature -- Status report

	has_frame: BOOLEAN
			-- Did the last `decode' succeed?
		do
			Result := attached last_frame_cell
		end

	has_capabilities: BOOLEAN
			-- Did the last `decode_capabilities' succeed?
		do
			Result := attached last_capabilities_cell
		end

	is_well_formed (a_text: READABLE_STRING_8): BOOLEAN
			-- Header, record tags, and field counts are right. Never raises.
		do
			Result := first_bad_line (a_text) = 0
		ensure
			needs_header: Result implies a_text.starts_with (Header)
		end

	activity_count_in (a_text: READABLE_STRING_8): INTEGER
			-- Number of A lines in `a_text'.
		local
			i: INTEGER
		do
			from
				i := 1
			until
				i > a_text.count
			loop
				if (i = 1 or else a_text [i - 1] = '%N') and then i < a_text.count
					and then a_text [i] = 'A' and then a_text [i + 1] = '%T' then
					Result := Result + 1
				end
				i := i + 1
			end
		ensure
			non_negative: Result >= 0
		end

feature {NONE} -- Structure

	first_bad_line (a_text: READABLE_STRING_8): INTEGER
			-- Number of the first line whose tag or field count is wrong; 0 when none is.
			-- Only the last line may be empty (the final newline).
		local
			l_lines: LIST [STRING_8]
			l_fields: LIST [STRING_8]
			i, l_expected: INTEGER
		do
			l_lines := a_text.to_string_8.split ('%N')
			l_fields := l_lines.first.split ('%T')
			if l_fields.count /= 9 or else not l_fields.first.same_string (Header) then
				Result := 1
			end
			from
				i := 2
			until
				Result > 0 or i > l_lines.count
			loop
				if l_lines [i].is_empty then
					if i < l_lines.count then
						Result := i
					end
				else
					l_fields := l_lines [i].split ('%T')
					l_expected := expected_fields (l_fields.first)
					if l_expected = 0 or else l_fields.count /= l_expected then
						Result := i
					end
				end
				i := i + 1
			end
		ensure
			non_negative: Result >= 0
		end

	expected_fields (a_tag: STRING_8): INTEGER
			-- Field count of a record tagged `a_tag'; 0 for an unknown tag.
		do
			if a_tag.same_string ("R") then
				Result := 5
			elseif a_tag.same_string ("A") then
				Result := 17
			elseif a_tag.same_string ("B") then
				Result := 3
			elseif a_tag.same_string ("X") then
				Result := 4
			end
		end

	line_problem (a_line: INTEGER; a_reason: READABLE_STRING_32): STRING_32
			-- "line N: reason".
		do
			Result := {STRING_32} "line " + a_line.out.to_string_32 + {STRING_32} ": " + a_reason
		ensure
			names_the_line: Result.starts_with ({STRING_32} "line ")
		end

feature {NONE} -- Records

	append_field (a_text: STRING_8; a_field: READABLE_STRING_8)
			-- Append a tab and `a_field'.
		do
			a_text.append_character ('%T')
			a_text.append (a_field)
		end

	append_reading (a_text: STRING_8; a_code: INTEGER; a_instance: READABLE_STRING_32; a_reading: TM_READING)
			-- Append one R line.
		do
			a_text.append ("R")
			append_field (a_text, a_code.out)
			append_field (a_text, escaped (a_instance))
			append_field (a_text, a_reading.status.out)
			if a_reading.is_available then
				append_field (a_text, bits_text (a_reading.value))
			else
				append_field (a_text, bits_text (0.0))
			end
			a_text.append_character ('%N')
		end

	append_activity (a_text: STRING_8; a_activity: TM_PROCESS_ACTIVITY)
			-- Append one A line; a group that is not available travels as zeros beside its status.
		do
			a_text.append ("A")
			append_field (a_text, a_activity.id.pid.out)
			append_field (a_text, a_activity.id.creation_ticks.out)
			append_field (a_text, escaped (a_activity.name))
			append_field (a_text, a_activity.parent_pid.out)
			append_field (a_text, a_activity.session.out)
			append_field (a_text, a_activity.threads.out)
			if a_activity.memory_status = {TM_READING_STATUS}.Available then
				append_field (a_text, a_activity.handles.out)
			else
				append_field (a_text, "0")
			end
			append_field (a_text, flag (a_activity.is_new))
			append_field (a_text, a_activity.cpu_status.out)
			if a_activity.cpu_status = {TM_READING_STATUS}.Available then
				append_field (a_text, bits_text (a_activity.cpu_cores))
			else
				append_field (a_text, bits_text (0.0))
			end
			append_field (a_text, a_activity.memory_status.out)
			if a_activity.memory_status = {TM_READING_STATUS}.Available then
				append_field (a_text, a_activity.working_set.out)
				append_field (a_text, a_activity.private_bytes.out)
			else
				append_field (a_text, "0")
				append_field (a_text, "0")
			end
			append_field (a_text, a_activity.io_status.out)
			if a_activity.io_status = {TM_READING_STATUS}.Available then
				append_field (a_text, bits_text (a_activity.io_read_bps))
				append_field (a_text, bits_text (a_activity.io_write_bps))
			else
				append_field (a_text, bits_text (0.0))
				append_field (a_text, bits_text (0.0))
			end
			a_text.append_character ('%N')
		end

	decode_reading (a_fields: LIST [STRING_8]; a_line: INTEGER; a_readings: TM_READINGS)
			-- Add the reading of an R line to `a_readings'; leave the problem, or empty, in `line_failure'.
		local
			l_code, l_status: INTEGER
			l_instance: STRING_32
			l_reading: TM_READING
		do
			create line_failure.make_empty
			if not (a_fields [2].is_integer and is_valid_escaped (a_fields [3]) and a_fields [4].is_integer and is_hex16 (a_fields [5])) then
				line_failure := line_problem (a_line, {STRING_32} "bad reading field")
			else
				l_code := a_fields [2].to_integer
				l_instance := unescaped (a_fields [3])
				l_status := a_fields [4].to_integer
				if not metrics.has_code (l_code) then
					line_failure := line_problem (a_line, {STRING_32} "unknown metric code " + l_code.out.to_string_32)
				elseif metrics.metric (l_code).is_instanced = l_instance.is_empty then
					line_failure := line_problem (a_line, {STRING_32} "instance does not fit the metric")
				elseif l_status < {TM_READING_STATUS}.Available or l_status > {TM_READING_STATUS}.Invalid then
					line_failure := line_problem (a_line, {STRING_32} "unknown status")
				else
					if l_status = {TM_READING_STATUS}.Available then
						create l_reading.make_measured (real_of_bits (a_fields [5]), metrics.metric (l_code))
					else
						l_reading := reading_with_status (l_status)
					end
					a_readings.put (l_code, l_instance, l_reading)
				end
			end
		end

	decode_activity (a_fields: LIST [STRING_8]; a_line, a_processors: INTEGER;
			a_activities: HASH_TABLE [TM_PROCESS_ACTIVITY, TM_PROCESS_ID])
			-- Add the activity of an A line to `a_activities'; leave the problem, or empty, in `line_failure'.
		local
			l_id: TM_PROCESS_ID
		do
			create line_failure.make_empty
			if not (is_count64 (a_fields [2]) and is_count64 (a_fields [3]) and is_valid_escaped (a_fields [4])
					and is_count64 (a_fields [5]) and is_count (a_fields [6]) and is_count (a_fields [7])
					and is_count (a_fields [8]) and is_flag (a_fields [9]) and is_status (a_fields [10])
					and is_hex16 (a_fields [11]) and is_status (a_fields [12]) and is_int64 (a_fields [13])
					and is_int64 (a_fields [14]) and is_status (a_fields [15]) and is_hex16 (a_fields [16])
					and is_hex16 (a_fields [17])) then
				line_failure := line_problem (a_line, {STRING_32} "bad activity field (fields must be non-negative numbers)")
			else
				create l_id.make (a_fields [2].to_integer_64, a_fields [3].to_integer_64)
				if l_id.is_idle_pseudo_process then
					line_failure := line_problem (a_line, {STRING_32} "the idle pseudo-process cannot have an activity")
				elseif a_activities.has (l_id) then
					line_failure := line_problem (a_line, {STRING_32} "repeated identity")
				else
					a_activities.put (create {TM_PROCESS_ACTIVITY}.make_decoded (l_id, unescaped (a_fields [4]),
						a_fields [5].to_integer_64, a_fields [6].to_integer, a_fields [7].to_integer, a_fields [8].to_integer,
						a_fields [9].same_string ("1"), a_processors,
						a_fields [10].to_integer, real_of_bits (a_fields [11]),
						a_fields [12].to_integer, a_fields [13].to_integer_64, a_fields [14].to_integer_64,
						a_fields [15].to_integer, real_of_bits (a_fields [16]), real_of_bits (a_fields [17])), l_id)
				end
			end
		end

	reading_with_status (a_status: INTEGER): TM_READING
			-- A reading that carries no value, only `a_status'.
		require
			not_available: a_status >= {TM_READING_STATUS}.Unavailable and a_status <= {TM_READING_STATUS}.Invalid
		do
			inspect a_status
			when {TM_READING_STATUS}.Unavailable then
				create Result.make_unavailable
			when {TM_READING_STATUS}.Not_supported then
				create Result.make_not_supported
			when {TM_READING_STATUS}.Access_denied then
				create Result.make_access_denied
			else
				create Result.make_invalid
			end
		ensure
			status_kept: Result.status = a_status
		end

feature {NONE} -- Fields

	flag (a_value: BOOLEAN): STRING_8
			-- "1" or "0".
		do
			if a_value then
				Result := "1"
			else
				Result := "0"
			end
		end

	is_flag (a_field: STRING_8): BOOLEAN
		do
			Result := a_field.same_string ("0") or a_field.same_string ("1")
		end

	is_int64 (a_field: STRING_8): BOOLEAN
		do
			Result := a_field.is_integer_64
		end

	is_count64 (a_field: STRING_8): BOOLEAN
			-- A non-negative 64-bit integer?
		do
			Result := a_field.is_integer_64 and then a_field.to_integer_64 >= 0
		end

	is_count (a_field: STRING_8): BOOLEAN
			-- A non-negative 32-bit integer?
		do
			Result := a_field.is_integer and then a_field.to_integer >= 0
		end

	is_status (a_field: STRING_8): BOOLEAN
		do
			Result := a_field.is_integer and then (a_field.to_integer >= {TM_READING_STATUS}.Available
				and a_field.to_integer <= {TM_READING_STATUS}.Invalid)
		end

feature {NONE} -- Exact reals

	bits_text (a_value: REAL_64): STRING_8
			-- The 64 bits of `a_value' as 16 upper-case hexadecimal digits.
		local
			l_bits: NATURAL_64
			i: INTEGER
		do
			bits_buffer.put_real_64 (a_value, 0)
			l_bits := bits_buffer.read_natural_64 (0)
			create Result.make_filled ('0', 16)
			from
				i := 16
			until
				i = 0
			loop
				Result [i] := Hex_digits [(l_bits & 0xF).to_integer_32 + 1]
				l_bits := l_bits |>> 4
				i := i - 1
			end
		ensure
			sixteen: Result.count = 16
		end

	is_hex16 (a_field: STRING_8): BOOLEAN
			-- Exactly 16 hexadecimal digits?
		do
			Result := a_field.count = 16 and then across a_field as ic all ic.is_hexa_digit end
		end

	real_of_bits (a_field: STRING_8): REAL_64
			-- The REAL_64 whose bits `a_field' spells.
		require
			hex: is_hex16 (a_field)
		local
			l_bits: NATURAL_64
		do
			across a_field as ic loop
				l_bits := (l_bits |<< 4) | (Hex_digits.index_of (ic.as_upper, 1).to_natural_64 - 1)
			end
			bits_buffer.put_natural_64 (l_bits, 0)
			Result := bits_buffer.read_real_64 (0)
		end

	Hex_digits: STRING_8 = "0123456789ABCDEF"

	bits_buffer: MANAGED_POINTER
			-- Eight bytes for reinterpreting a REAL_64 as a NATURAL_64.
		once
			create Result.make (8)
		end

feature {NONE} -- Text

	escaped (a_text: READABLE_STRING_32): STRING_8
			-- `a_text' in UTF-8 with backslash, tab, newline, and carriage return escaped.
		local
			l_utf: STRING_8
		do
			l_utf := utf.string_32_to_utf_8_string_8 (a_text)
			create Result.make (l_utf.count + 8)
			across l_utf as ic loop
				inspect ic
				when '\' then
					Result.append ("\\")
				when '%T' then
					Result.append ("\t")
				when '%N' then
					Result.append ("\n")
				when '%R' then
					Result.append ("\r")
				else
					Result.append_character (ic)
				end
			end
		ensure
			no_separators: not Result.has ('%T') and not Result.has ('%N')
		end

	is_valid_escaped (a_field: STRING_8): BOOLEAN
			-- Is every backslash in `a_field' followed by one of \ t n r?
		local
			i: INTEGER
		do
			from
				Result := True
				i := 1
			until
				not Result or i > a_field.count
			loop
				if a_field [i] = '\' then
					Result := i < a_field.count and then ("\tnr").has (a_field [i + 1])
					i := i + 2
				else
					i := i + 1
				end
			end
		end

	unescaped (a_field: STRING_8): STRING_32
			-- Text of an escaped UTF-8 field.
		require
			valid: is_valid_escaped (a_field)
		local
			l_utf: STRING_8
			i: INTEGER
		do
			create l_utf.make (a_field.count)
			from
				i := 1
			until
				i > a_field.count
			loop
				if a_field [i] = '\' then
					inspect a_field [i + 1]
					when 't' then
						l_utf.append_character ('%T')
					when 'n' then
						l_utf.append_character ('%N')
					when 'r' then
						l_utf.append_character ('%R')
					else
						l_utf.append_character ('\')
					end
					i := i + 2
				else
					l_utf.append_character (a_field [i])
					i := i + 1
				end
			end
			Result := utf.utf_8_string_8_to_string_32 (l_utf)
		end

feature {NONE} -- Implementation

	utf: UTF_CONVERTER
			-- Encoding conversions.

	line_failure: STRING_32
			-- Problem found by the last `decode_reading' or `decode_activity'; empty when none.

	last_frame_cell: detachable TM_FRAME
	last_capabilities_cell: detachable TM_CAPABILITIES

end
