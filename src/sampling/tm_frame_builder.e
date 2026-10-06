note
	description: "[
		Two snapshots into one frame. Pure: it reads its arguments and makes a
		new frame. Rates are formed only between two samples of the same
		identity; a recycled pid is born, never given its predecessor's rate
		(FR-003). The idle pseudo-process is left out (A-111). Before sealing,
		three readings about the tool itself are added (I-008, FR-053).

		The frame's span comes from the sampler, which keeps the timeline
		continuous across wall-clock changes (review issue 2). Every
		postcondition here is O(n) through hash lookups: an MML model of a
		process list is cubic to build with contracts on (review issue 1).
	]"
	author: "Larry Rix"

class
	TM_FRAME_BUILDER

inherit
	TM_SHARED_METRICS

feature -- Basic operations

	build (a_previous, a_current: TM_SNAPSHOT; a_start_ticks, a_end_ticks: INTEGER_64; a_clock_adjusted: BOOLEAN;
			a_logical_processors: INTEGER; a_self: detachable TM_PROCESS_ID; a_previous_cost: INTEGER_64): TM_FRAME
			-- What happened between `a_previous' and `a_current', spanning [`a_start_ticks', `a_end_ticks'].
			-- `a_self' is this tool, or Void when unknown; `a_previous_cost' the monotonic ticks the last tick took.
		require
			ordered: a_current.monotonic_ticks > a_previous.monotonic_ticks
			span_ordered: a_end_ticks > a_start_ticks
			processors: a_logical_processors > 0
			cost_non_negative: a_previous_cost >= 0
			self_not_idle: attached a_self as al_self implies not al_self.is_idle_pseudo_process
		local
			l_seconds: REAL_64
			l_activities: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			l_born: ARRAYED_LIST [TM_PROCESS_ID]
			l_exited: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			l_activity: TM_PROCESS_ACTIVITY
			l_self_activity: detachable TM_PROCESS_ACTIVITY
			l_readings: TM_READINGS
		do
			l_seconds := (a_current.monotonic_ticks - a_previous.monotonic_ticks) / {TM_CLOCK}.Ticks_per_second
			create l_activities.make (a_current.count)
			create l_born.make (8)
			create l_exited.make (8)
			across a_current.samples as ic loop
				if not ic.id.is_idle_pseudo_process then
					if a_previous.has (ic.id) then
						create l_activity.make_from_pair (a_previous.sample (ic.id), ic, l_seconds, a_logical_processors)
					else
						create l_activity.make_born (ic, a_logical_processors)
						l_born.extend (ic.id)
					end
					l_activities.extend (l_activity)
					if attached a_self as al_self and then ic.id ~ al_self then
						l_self_activity := l_activity
					end
				end
			end
			across a_previous.samples as ic loop
				if not ic.id.is_idle_pseudo_process and then not a_current.has (ic.id) then
					l_exited.extend (ic)
				end
			end
			create l_readings.make_from (a_current.readings)
			put_self_readings (l_readings, l_self_activity, a_previous_cost)
			create Result.make (a_start_ticks, a_end_ticks,
				a_current.monotonic_ticks - a_previous.monotonic_ticks, a_logical_processors, a_clock_adjusted,
				l_readings, l_activities, l_born, l_exited)
		ensure
			span: Result.start_ticks = a_start_ticks and Result.end_ticks = a_end_ticks
			duration: Result.duration = a_current.monotonic_ticks - a_previous.monotonic_ticks
			adjusted_kept: Result.is_clock_adjusted = a_clock_adjusted
			live: not Result.is_discontinuity and Result.is_complete
			every_current_process: Result.activity_count = a_current.count - idle_count (a_current)
				and across a_current.samples as ic all ic.id.is_idle_pseudo_process or else Result.has_activity (ic.id) end
			no_rate_across_identities: across Result.activities as ic all ic.is_new = not a_previous.has (ic.id) end
			born_are_the_new_ones: Result.born.count = new_count (Result)
			exited_exactly: Result.exited.count = exited_count (a_previous, a_current)
				and across Result.exited as ic all a_previous.has (ic.id) and not a_current.has (ic.id) end
			system_readings_kept: Result.readings.includes (a_current.readings)
			self_cost_recorded: Result.readings.has ({TM_METRICS}.Sample_cost_ms, {STRING_32} "")
			self_cpu_recorded: Result.readings.has ({TM_METRICS}.Self_cpu_pct, {STRING_32} "")
			self_memory_recorded: Result.readings.has ({TM_METRICS}.Self_private_bytes, {STRING_32} "")
			self_unavailable_when_absent: not (attached a_self as al_self and then a_current.has (al_self)) implies
				Result.readings.reading ({TM_METRICS}.Self_cpu_pct, {STRING_32} "").is_unavailable
		end

	discontinuity (a_previous, a_current: TM_SNAPSHOT; a_start_ticks, a_end_ticks: INTEGER_64; a_clock_adjusted: BOOLEAN;
			a_logical_processors: INTEGER; a_supported: ITERABLE [INTEGER]): TM_FRAME
			-- Gap frame between `a_previous' and `a_current' (A-110): no activities,
			-- every metric in `a_supported' unavailable.
		require
			ordered: a_current.monotonic_ticks > a_previous.monotonic_ticks
			span_ordered: a_end_ticks > a_start_ticks
			processors: a_logical_processors > 0
		do
			create Result.make_discontinuity (a_start_ticks, a_end_ticks,
				a_current.monotonic_ticks - a_previous.monotonic_ticks, a_logical_processors, a_clock_adjusted, a_supported)
		ensure
			flagged: Result.is_discontinuity
			empty: Result.activity_count = 0
			span: Result.start_ticks = a_start_ticks and Result.end_ticks = a_end_ticks
			adjusted_kept: Result.is_clock_adjusted = a_clock_adjusted
		end

feature {NONE} -- Implementation

	put_self_readings (a_readings: TM_READINGS; a_self: detachable TM_PROCESS_ACTIVITY; a_previous_cost: INTEGER_64)
			-- The tool's own CPU (percent of one processor) and private bytes from its row,
			-- unavailable without one; and the previous tick's cost in milliseconds (I-008).
		require
			open: not a_readings.is_sealed
			cost_non_negative: a_previous_cost >= 0
		do
			if attached a_self as al_self and then al_self.cpu_status = {TM_READING_STATUS}.Available then
				a_readings.put ({TM_METRICS}.Self_cpu_pct, {STRING_32} "",
					create {TM_READING}.make_measured (al_self.cpu_cores * 100.0, metrics.metric ({TM_METRICS}.Self_cpu_pct)))
			else
				a_readings.put ({TM_METRICS}.Self_cpu_pct, {STRING_32} "", create {TM_READING}.make_unavailable)
			end
			if attached a_self as al_self and then al_self.memory_status = {TM_READING_STATUS}.Available then
				a_readings.put ({TM_METRICS}.Self_private_bytes, {STRING_32} "",
					create {TM_READING}.make_measured (al_self.private_bytes.to_double, metrics.metric ({TM_METRICS}.Self_private_bytes)))
			else
				a_readings.put ({TM_METRICS}.Self_private_bytes, {STRING_32} "", create {TM_READING}.make_unavailable)
			end
			a_readings.put ({TM_METRICS}.Sample_cost_ms, {STRING_32} "",
				create {TM_READING}.make_measured (a_previous_cost / Ticks_per_ms, metrics.metric ({TM_METRICS}.Sample_cost_ms)))
		ensure
			all_three: a_readings.has ({TM_METRICS}.Self_cpu_pct, {STRING_32} "")
				and a_readings.has ({TM_METRICS}.Self_private_bytes, {STRING_32} "")
				and a_readings.has ({TM_METRICS}.Sample_cost_ms, {STRING_32} "")
		end

	Ticks_per_ms: REAL_64 = 10_000.0
			-- 100 ns ticks in one millisecond.

feature -- Contract support (all O(n))

	idle_count (a_snapshot: TM_SNAPSHOT): INTEGER
			-- Idle pseudo-process entries in `a_snapshot'.
		do
			across a_snapshot.samples as ic loop
				if ic.id.is_idle_pseudo_process then
					Result := Result + 1
				end
			end
		ensure
			bounded: Result >= 0 and Result <= a_snapshot.count
		end

	new_count (a_frame: TM_FRAME): INTEGER
			-- Activities of `a_frame' born during its interval.
		do
			across a_frame.activities as ic loop
				if ic.is_new then
					Result := Result + 1
				end
			end
		ensure
			bounded: Result >= 0 and Result <= a_frame.activity_count
		end

	exited_count (a_previous, a_current: TM_SNAPSHOT): INTEGER
			-- Identities in `a_previous', other than idle, absent from `a_current'.
		do
			across a_previous.samples as ic loop
				if not ic.id.is_idle_pseudo_process and then not a_current.has (ic.id) then
					Result := Result + 1
				end
			end
		ensure
			bounded: Result >= 0 and Result <= a_previous.count
		end

end
