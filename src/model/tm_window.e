note
	description: "[
		A time-ordered run of frames over which a question is asked. The
		rules see nothing else: no source, no clock, no store (NFR-010).
		Aggregates report their coverage, so a window with holes says so.
	]"
	author: "Larry Rix"

class
	TM_WINDOW

inherit
	TM_SHARED_METRICS

create
	make

feature {NONE} -- Initialization

	make
			-- Empty window.
		do
			create frame_list.make (64)
		ensure
			empty: is_empty
		end

feature -- Access

	start_ticks: INTEGER_64
			-- UTC start of the first frame; 0 when empty.

	end_ticks: INTEGER_64
			-- UTC end of the last frame; 0 when empty.

	count: INTEGER
			-- Number of frames.
		do
			Result := frame_list.count
		end

	frame (i: INTEGER): TM_FRAME
			-- Frame `i', oldest first.
		require
			in_range: i >= 1 and i <= count
		do
			Result := frame_list [i]
		end

	last_frame: TM_FRAME
			-- Newest frame.
		require
			not_empty: not is_empty
		do
			Result := frame_list.last
		end

	aggregate (a_code: INTEGER; a_instance: READABLE_STRING_32): TM_AGGREGATE
			-- Aggregate of metric `a_code' over the window: peak or duration-weighted mean, with coverage.
		require
			not_empty: not is_empty
			known_metric: metrics.has_code (a_code)
			instance_rule: metrics.metric (a_code).is_instanced = not a_instance.is_empty
		local
			l_metric: TM_METRIC
			l_kind: INTEGER
			l_reading: TM_READING
			l_measured: INTEGER_64
			l_weighted, l_peak, l_value, l_seconds: REAL_64
			l_result: TM_READING
		do
			l_metric := metrics.metric (a_code)
			if l_metric.is_peak then
				l_kind := {TM_AGGREGATE}.Peak
			else
				l_kind := {TM_AGGREGATE}.Weighted_mean
			end
			l_peak := l_metric.minimum
			across frame_list as ic loop
				l_reading := ic.readings.reading (a_code, a_instance)
				if l_reading.is_available then
					l_measured := l_measured + ic.duration
					l_weighted := l_weighted + l_reading.value * ic.duration
					l_peak := l_peak.max (l_reading.value)
				end
			end
			if l_measured = 0 then
				create Result.make (l_kind, create {TM_READING}.make_unavailable, 0.0, 0.0)
			else
				if l_kind = {TM_AGGREGATE}.Peak then
					l_value := l_peak
				else
						-- A mean of accepted values lies in range; clamp only floating-point rounding.
					l_value := (l_weighted / l_measured).max (l_metric.minimum).min (l_metric.maximum)
				end
				create l_result.make_measured (l_value, l_metric)
				l_seconds := (l_measured / {TM_CLOCK}.Ticks_per_second).min (span_seconds)
				Result := create {TM_AGGREGATE}.make (l_kind, l_result, coverage_of (l_measured), l_seconds)
			end
		ensure
			coverage_bounded: Result.coverage >= 0.0 and Result.coverage <= 1.0
			unavailable_when_unmeasured: Result.coverage = 0.0 implies not Result.reading.is_available
			peak_rule: metrics.metric (a_code).is_peak implies Result.kind = {TM_AGGREGATE}.Peak
			mean_rule: not metrics.metric (a_code).is_peak implies Result.kind = {TM_AGGREGATE}.Weighted_mean
			seconds_within_span: Result.measured_seconds <= span_seconds + Epsilon
			pure: count = old count and last_frame = old last_frame
		end

	ranked (a_resource: INTEGER; a_count: INTEGER): ARRAYED_LIST [TM_PROCESS_TOTAL]
			-- At most `a_count' identities by total use of `a_resource' over the window, largest first.
		require
			not_empty: not is_empty
			known_resource: a_resource >= {TM_RESOURCE}.Cpu and a_resource <= {TM_RESOURCE}.Io_total
			positive: a_count > 0
		local
			l_totals: HASH_TABLE [REAL_64, TM_PROCESS_ID]
			l_names: HASH_TABLE [STRING_32, TM_PROCESS_ID]
			l_frames: HASH_TABLE [INTEGER, TM_PROCESS_ID]
			l_seconds, l_amount: REAL_64
			l_total: TM_PROCESS_TOTAL
			i: INTEGER
		do
			create l_totals.make (256)
			create l_names.make (256)
			create l_frames.make (256)
			across frame_list as ic_frame loop
				l_seconds := ic_frame.duration / {TM_CLOCK}.Ticks_per_second
				across ic_frame.activities as ic loop
					if ic.has_resource (a_resource) then
						if a_resource = {TM_RESOURCE}.Memory then
							l_amount := ic.amount_of (a_resource).max (l_totals [ic.id])
						else
							l_amount := l_totals [ic.id] + ic.amount_of (a_resource) * l_seconds
						end
						l_totals.force (l_amount, ic.id)
						l_names.force (ic.name, ic.id)
						l_frames.force (l_frames [ic.id] + 1, ic.id)
					end
				end
			end
			create Result.make (a_count + 1)
			across l_totals as ic loop
				if attached l_names.item (@ic.key) as al_name then
					create l_total.make (@ic.key, al_name, a_resource, ic, l_frames [@ic.key])
					from
						i := 1
					until
						i > Result.count or else Result [i].total < l_total.total
					loop
						i := i + 1
					end
					if i <= a_count then
						if i > Result.count then
							Result.extend (l_total)
						else
							Result.go_i_th (i)
							Result.put_left (l_total)
						end
						if Result.count > a_count then
							Result.finish
							Result.remove
						end
					end
				end
			end
		ensure
			bounded: Result.count <= a_count
			resource_kept: across Result as ic all ic.resource = a_resource end
			descending: across 2 |..| Result.count as ic all Result [ic - 1].total >= Result [ic].total end
			pure: count = old count and last_frame = old last_frame
		end

	measured_seconds: REAL_64
			-- Seconds covered by frames that are not discontinuities.
		local
			l_ticks: INTEGER_64
		do
			across frame_list as ic loop
				if not ic.is_discontinuity then
					l_ticks := l_ticks + ic.duration
				end
			end
				-- Durations are monotonic and the span is wall time; they drift by parts per
				-- million, so measured time is capped at the span it lies in.
			Result := (l_ticks / {TM_CLOCK}.Ticks_per_second).min (span_seconds)
		ensure
			non_negative: Result >= 0.0
			within_span: Result <= span_seconds + Epsilon
		end

	span_seconds: REAL_64
			-- Seconds from `start_ticks' to `end_ticks'.
		do
			Result := (end_ticks - start_ticks) / {TM_CLOCK}.Ticks_per_second
		ensure
			non_negative: Result >= 0.0
		end

	Epsilon: REAL_64 = 0.000_001
			-- Tolerance for comparing sums of seconds.

	coverage_of (a_measured_ticks: INTEGER_64): REAL_64
			-- Share of the window's span covered by `a_measured_ticks', at most 1.
		require
			not_empty: not is_empty
			non_negative: a_measured_ticks >= 0
		do
			Result := (a_measured_ticks / (end_ticks - start_ticks)).min (1.0)
		ensure
			bounded: Result >= 0.0 and Result <= 1.0
		end

feature -- Status report

	is_empty: BOOLEAN
			-- No frames yet?
		do
			Result := frame_list.is_empty
		end

	contains_span (a_from, a_to: INTEGER_64): BOOLEAN
			-- Does the window cover the whole of [`a_from', `a_to']?
		do
			Result := not is_empty and then a_from <= a_to and then a_from >= start_ticks and then a_to <= end_ticks
		end

feature -- Element change

	extend (a_frame: TM_FRAME)
			-- Append `a_frame', which must not start before the last one ends (DR-006).
		require
			in_order: not is_empty implies a_frame.start_ticks >= end_ticks
		do
			if frame_list.is_empty then
				start_ticks := a_frame.start_ticks
			end
			end_ticks := a_frame.end_ticks
			frame_list.extend (a_frame)
		ensure
			appended: count = old count + 1 and last_frame = a_frame
			earlier_kept: across 1 |..| (old count) as ic all frame (ic) = (old frame_list.twin).i_th (ic) end
				-- O(n); the MML form frames_model |=| ((old frames_model) & a_frame) is checked in a test.
			new_end: end_ticks = a_frame.end_ticks
			first_sets_start: old is_empty implies start_ticks = a_frame.start_ticks
			start_kept: not old is_empty implies start_ticks = old start_ticks
		end

feature -- Model

	frames_model: MML_SEQUENCE [TM_FRAME]
			-- Frames, oldest first.
		do
			create Result
			across frame_list as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = count
		end

feature {NONE} -- Implementation

	frame_list: ARRAYED_LIST [TM_FRAME]
			-- Frames, oldest first.

invariant
	empty_has_no_span: is_empty implies (start_ticks = 0 and end_ticks = 0)
	span_ordered: not is_empty implies end_ticks > start_ticks
	count_matches: count = frame_list.count

end
