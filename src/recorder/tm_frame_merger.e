note
	description: "[
		Pure engine that shrinks frames for the recording (FR-NEW-012, FR-021).

		`reduced' keeps a live frame's readings and only its significant
		processes, at most `max_processes' of them, chosen in turn from the
		top of the CPU, disk, and memory rankings; the rest are counted as
		omitted.

		`merged' turns a run of consecutive live frames into one frame for a
		coarser tier. A reading takes the duration-weighted mean of the
		frames where it was available (peak metrics take the maximum),
		clamped to the range of those values so rounding cannot push it out
		of its metric's range; when it was never available it keeps the most
		useful reason. A process takes the duration-weighted mean of its
		rates over the frames where they were measured, and its latest
		memory, then the result is reduced like a live frame. An identity
		that ran in the bucket and exited in it keeps its activity; the exit
		shows as its absence from later frames.
	]"
	author: "Larry Rix"

class
	TM_FRAME_MERGER

inherit
	TM_SHARED_METRICS

create
	make

feature {NONE} -- Initialization

	make (a_policy: TM_RETENTION_POLICY)
			-- Merger using `a_policy' for significance and the process limit.
		do
			policy := a_policy
		ensure
			policy_kept: policy = a_policy
		end

feature -- Access

	policy: TM_RETENTION_POLICY
			-- Significance thresholds and the per-frame process limit.

feature -- Basic operations

	reduced (a_frame: TM_FRAME): TM_FRAME
			-- `a_frame' with its readings and only its significant processes.
		require
			not_before_epoch: a_frame.start_ticks >= 0
		local
			l_candidates, l_kept: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			l_kept_ids: HASH_TABLE [BOOLEAN, TM_PROCESS_ID]
			l_born: ARRAYED_LIST [TM_PROCESS_ID]
			l_memory_pass: BOOLEAN
		do
			create l_candidates.make (a_frame.activity_count)
			l_memory_pass := policy.is_memory_pass (a_frame)
			across a_frame.activities as ic loop
				if policy.is_significant (ic, l_memory_pass) then
					l_candidates.extend (ic)
				end
			end
			l_kept := chosen (l_candidates)
			create l_kept_ids.make (l_kept.count)
			across l_kept as ic loop
				l_kept_ids.force (True, ic.id)
			end
			create l_born.make (4)
			across a_frame.born as ic loop
				if l_kept_ids.has (ic) then
					l_born.extend (ic)
				end
			end
			create Result.make_decoded (a_frame.start_ticks, a_frame.end_ticks, a_frame.duration, a_frame.logical_processors,
				a_frame.is_discontinuity, a_frame.is_clock_adjusted,
				a_frame.omitted_processes + a_frame.activity_count - l_kept.count,
				a_frame.readings, l_kept, l_born, a_frame.exited)
		ensure
			same_span: Result.start_ticks = a_frame.start_ticks and Result.end_ticks = a_frame.end_ticks
				and Result.duration = a_frame.duration
			same_flags: Result.is_discontinuity = a_frame.is_discontinuity
				and Result.is_clock_adjusted = a_frame.is_clock_adjusted
			same_processors: Result.logical_processors = a_frame.logical_processors
			readings_shared: Result.readings = a_frame.readings
			bounded: Result.activity_count <= policy.max_processes
			only_significant: across Result.activities as ic all policy.is_significant (ic, policy.is_memory_pass (a_frame)) end
			from_frame: across Result.activities as ic all a_frame.has_activity (ic.id) end
			omitted_counted: Result.omitted_processes = a_frame.omitted_processes + a_frame.activity_count - Result.activity_count
			exits_kept: Result.exited.count = a_frame.exited.count
			born_kept_when_recorded: across Result.born as ic all Result.has_activity (ic) end
			recorded: not Result.is_complete
		end

	merged (a_frames: ARRAYED_LIST [TM_FRAME]): TM_FRAME
			-- One frame covering the consecutive live frames `a_frames'.
		require
			not_empty: not a_frames.is_empty
			consecutive: across 2 |..| a_frames.count as ic all a_frames [ic].start_ticks >= a_frames [ic - 1].end_ticks end
			live: across a_frames as ic all not ic.is_discontinuity end
			same_processors: across a_frames as ic all ic.logical_processors = a_frames.first.logical_processors end
		local
			l_activities: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			l_active: HASH_TABLE [BOOLEAN, TM_PROCESS_ID]
			l_born: ARRAYED_LIST [TM_PROCESS_ID]
			l_exited: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			l_omitted: INTEGER
			l_adjusted: BOOLEAN
			l_whole: TM_FRAME
		do
			l_activities := merged_activities (a_frames)
			create l_active.make (l_activities.count)
			across l_activities as ic loop
				l_active.force (True, ic.id)
			end
			create l_born.make (8)
			create l_exited.make (8)
			across a_frames as f loop
				l_omitted := l_omitted.max (f.omitted_processes)
				l_adjusted := l_adjusted or f.is_clock_adjusted
				across f.born as ic loop
					if l_active.has (ic) and then not l_born.has (ic) then
						l_born.extend (ic)
					end
				end
				across f.exited as ic loop
					if not l_active.has (ic.id) then
						l_exited.extend (ic)
					end
				end
			end
			create l_whole.make_decoded (a_frames.first.start_ticks, a_frames.last.end_ticks, total_duration (a_frames),
				a_frames.first.logical_processors, False, l_adjusted, l_omitted,
				merged_readings (a_frames), l_activities, l_born, l_exited)
			Result := reduced (l_whole)
		ensure
			span: Result.start_ticks = a_frames.first.start_ticks and Result.end_ticks = a_frames.last.end_ticks
			duration_summed: Result.duration = total_duration (a_frames)
			live: not Result.is_discontinuity
			adjusted_if_any: Result.is_clock_adjusted = across a_frames as ic some ic.is_clock_adjusted end
			same_processors: Result.logical_processors = a_frames.first.logical_processors
			bounded: Result.activity_count <= policy.max_processes
			omitted_at_least: across a_frames as ic all Result.omitted_processes >= ic.omitted_processes end
			every_key: across a_frames as ic all every_key_present (ic.readings, Result.readings) end
			available_only_from_available: across keys_of (Result.readings, {TM_METRICS}.Cpu_busy_pct) as ic all
				Result.readings.reading ({TM_METRICS}.Cpu_busy_pct, ic).is_available implies
					across a_frames as f some f.readings.reading ({TM_METRICS}.Cpu_busy_pct, ic).is_available end end
			recorded: not Result.is_complete
		end

feature -- Contract support

	total_duration (a_frames: ITERABLE [TM_FRAME]): INTEGER_64
			-- Sum of the frames' monotonic durations.
		do
			across a_frames as ic loop
				Result := Result + ic.duration
			end
		ensure
			positive_if_any: (across a_frames as ic some True end) implies Result > 0
		end

	every_key_present (a_part, a_whole: TM_READINGS): BOOLEAN
			-- Does `a_whole' hold a reading for every metric and instance that `a_part' holds?
		do
			Result := across 1 |..| metrics.Last_code as c all
				across keys_of (a_part, c) as ic all a_whole.has (c, ic) end end
		end

	keys_of (a_readings: TM_READINGS; a_code: INTEGER): ARRAYED_LIST [STRING_32]
			-- Instance names `a_readings' holds for `a_code'; the empty name for a stored non-instanced metric.
		require
			known_metric: metrics.has_code (a_code)
		do
			if metrics.metric (a_code).is_instanced then
				Result := a_readings.instances (a_code)
			else
				create Result.make (1)
				if a_readings.has (a_code, {STRING_32} "") then
					Result.extend ({STRING_32} "")
				end
			end
		ensure
			instance_rule: across Result as ic all metrics.metric (a_code).is_instanced = not ic.is_empty end
			all_held: across Result as ic all a_readings.has (a_code, ic) end
		end

feature {NONE} -- Readings

	merged_readings (a_frames: ARRAYED_LIST [TM_FRAME]): TM_READINGS
			-- Every metric and instance any frame holds, merged over the frames.
		local
			l_names: ARRAYED_LIST [STRING_32]
			c: INTEGER
		do
			create Result.make
			from c := 1 until c > metrics.Last_code loop
				create l_names.make (4)
				across a_frames as f loop
					across keys_of (f.readings, c) as ic loop
						if not across l_names as n some n.same_string (ic) end then
							l_names.extend (ic)
						end
					end
				end
				across l_names as ic loop
					Result.put (c, ic, merged_reading (a_frames, c, ic))
				end
				c := c + 1
			end
		end

	merged_reading (a_frames: ARRAYED_LIST [TM_FRAME]; a_code: INTEGER; a_instance: STRING_32): TM_READING
			-- Metric `a_code' at `a_instance' over the frames that hold it.
		require
			instance_rule: metrics.metric (a_code).is_instanced = not a_instance.is_empty
		local
			l_reading: TM_READING
			l_metric: TM_METRIC
			l_sum, l_seconds, l_low, l_high, l_value: REAL_64
			l_any: BOOLEAN
			l_reason: INTEGER
		do
			l_metric := metrics.metric (a_code)
			l_reason := {TM_READING_STATUS}.Unavailable
			across a_frames as f loop
				if f.readings.has (a_code, a_instance) then
					l_reading := f.readings.reading (a_code, a_instance)
					if l_reading.is_available then
						if not l_any then
							l_low := l_reading.value
							l_high := l_reading.value
							l_any := True
						else
							l_low := l_low.min (l_reading.value)
							l_high := l_high.max (l_reading.value)
						end
						l_sum := l_sum + l_reading.value * f.duration.to_double
						l_seconds := l_seconds + f.duration.to_double
					else
						l_reason := more_useful (l_reason, l_reading.status)
					end
				end
			end
			if l_any then
				if l_metric.is_peak then
					l_value := l_high
				else
					l_value := (l_sum / l_seconds).max (l_low).min (l_high)
				end
				create Result.make_measured (l_value, l_metric)
			else
				Result := reading_with_status (l_reason)
			end
		end

	reading_with_status (a_status: INTEGER): TM_READING
			-- A reading that is not available, for the reason `a_status'.
		do
			inspect a_status
			when {TM_READING_STATUS}.Not_supported then
				create Result.make_not_supported
			when {TM_READING_STATUS}.Access_denied then
				create Result.make_access_denied
			when {TM_READING_STATUS}.Invalid then
				create Result.make_invalid
			else
				create Result.make_unavailable
			end
		ensure
			not_available: not Result.is_available
		end

	more_useful (a_first, a_second: INTEGER): INTEGER
			-- The more useful reason of two statuses: access denied, then not
			-- supported, then invalid, then unavailable (as TM_PROCESS_ACTIVITY.worse_of).
		do
			if reason_rank (a_first) >= reason_rank (a_second) then
				Result := a_first
			else
				Result := a_second
			end
		ensure
			one_of_them: Result = a_first or Result = a_second
		end

	reason_rank (a_status: INTEGER): INTEGER
			-- Usefulness of `a_status' as an explanation.
		do
			inspect a_status
			when {TM_READING_STATUS}.Access_denied then
				Result := 4
			when {TM_READING_STATUS}.Not_supported then
				Result := 3
			when {TM_READING_STATUS}.Invalid then
				Result := 2
			when {TM_READING_STATUS}.Unavailable then
				Result := 1
			else
				Result := 0
			end
		end

feature {NONE} -- Processes

	merged_activities (a_frames: ARRAYED_LIST [TM_FRAME]): ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			-- One activity per identity seen in any frame, first seen first.
		local
			l_ids: ARRAYED_LIST [TM_PROCESS_ID]
			l_seen: HASH_TABLE [BOOLEAN, TM_PROCESS_ID]
		do
			create l_ids.make (64)
			create l_seen.make (64)
			across a_frames as f loop
				across f.activities as ic loop
					if not l_seen.has (ic.id) then
						l_seen.force (True, ic.id)
						l_ids.extend (ic.id)
					end
				end
			end
			create Result.make (l_ids.count)
			across l_ids as ic loop
				Result.extend (merged_activity (a_frames, ic))
			end
		ensure
			every_identity: across a_frames as f all across f.activities as ic all across Result as r some r.id ~ ic.id end end end
		end

	merged_activity (a_frames: ARRAYED_LIST [TM_FRAME]; a_id: TM_PROCESS_ID): TM_PROCESS_ACTIVITY
			-- Identity `a_id' over the frames where it appears.
		require
			seen: across a_frames as f some f.has_activity (a_id) end
		local
			l_latest, l_memory: detachable TM_PROCESS_ACTIVITY
			l_one: TM_PROCESS_ACTIVITY
			l_cores, l_cpu_seconds, l_read, l_write, l_io_seconds, l_cores_high, l_d: REAL_64
			l_cpu_reason, l_io_reason, l_memory_reason: INTEGER
			l_all_new: BOOLEAN
			l_cpu_status, l_io_status, l_memory_status: INTEGER
			l_working_set, l_private: INTEGER_64
			l_handles: INTEGER
		do
			l_all_new := True
			l_cpu_reason := {TM_READING_STATUS}.Unavailable
			l_io_reason := {TM_READING_STATUS}.Unavailable
			l_memory_reason := {TM_READING_STATUS}.Unavailable
			across a_frames as f loop
				if f.has_activity (a_id) then
					l_one := f.activity (a_id)
					l_latest := l_one
					l_all_new := l_all_new and l_one.is_new
					l_d := f.duration.to_double
					if l_one.has_resource ({TM_RESOURCE}.Cpu) then
						l_cores := l_cores + l_one.cpu_cores * l_d
						l_cpu_seconds := l_cpu_seconds + l_d
						l_cores_high := l_cores_high.max (l_one.cpu_cores)
					else
						l_cpu_reason := more_useful (l_cpu_reason, l_one.cpu_status)
					end
					if l_one.has_resource ({TM_RESOURCE}.Io_total) then
						l_read := l_read + l_one.io_read_bps * l_d
						l_write := l_write + l_one.io_write_bps * l_d
						l_io_seconds := l_io_seconds + l_d
					else
						l_io_reason := more_useful (l_io_reason, l_one.io_status)
					end
					if l_one.has_resource ({TM_RESOURCE}.Memory) then
						l_memory := l_one
					else
						l_memory_reason := more_useful (l_memory_reason, l_one.memory_status)
					end
				end
			end
			if attached l_latest as al_latest then
				if l_cpu_seconds > 0.0 and not l_all_new then
					l_cpu_status := {TM_READING_STATUS}.Available
					l_cores := (l_cores / l_cpu_seconds).min (l_cores_high)
				else
					l_cpu_status := l_cpu_reason
					l_cores := 0.0
				end
				if l_io_seconds > 0.0 and not l_all_new then
					l_io_status := {TM_READING_STATUS}.Available
					l_read := l_read / l_io_seconds
					l_write := l_write / l_io_seconds
				else
					l_io_status := l_io_reason
					l_read := 0.0
					l_write := 0.0
				end
				if attached l_memory as al_memory then
					l_memory_status := {TM_READING_STATUS}.Available
					l_working_set := al_memory.working_set
					l_private := al_memory.private_bytes
					l_handles := al_memory.handles
				else
					l_memory_status := l_memory_reason
				end
				create Result.make_decoded (a_id, al_latest.name, al_latest.parent_pid, al_latest.session, al_latest.threads,
					l_handles, l_all_new, al_latest.logical_processors,
					l_cpu_status, l_cores, l_memory_status, l_working_set, l_private, l_io_status, l_read, l_write)
			else
					-- Not reached: the precondition says some frame holds `a_id'.
				create Result.make_decoded (a_id, {STRING_32} "?", 0, 0, 0, 0, False, a_frames.first.logical_processors,
					{TM_READING_STATUS}.Invalid, 0.0, {TM_READING_STATUS}.Invalid, 0, 0, {TM_READING_STATUS}.Invalid, 0.0, 0.0)
			end
		ensure
			same_identity: Result.id ~ a_id
		end

	chosen (a_candidates: ARRAYED_LIST [TM_PROCESS_ACTIVITY]): ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			-- All of `a_candidates' when they fit; otherwise `max_processes' taken in turn from the top of the
			-- CPU, disk, and memory rankings.
		local
			l_by_cpu, l_by_io, l_by_memory: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			l_taken: HASH_TABLE [BOOLEAN, TM_PROCESS_ID]
			i: INTEGER
		do
			if a_candidates.count <= policy.max_processes then
				create Result.make_from_array (a_candidates.to_array)
			else
				l_by_cpu := ranked (a_candidates, {TM_RESOURCE}.Cpu)
				l_by_io := ranked (a_candidates, {TM_RESOURCE}.Io_total)
				l_by_memory := ranked (a_candidates, {TM_RESOURCE}.Memory)
				create Result.make (policy.max_processes)
				create l_taken.make (policy.max_processes)
				from
					i := 1
				until
					Result.count = policy.max_processes or i > a_candidates.count
				loop
					take (l_by_cpu [i], Result, l_taken)
					take (l_by_io [i], Result, l_taken)
					take (l_by_memory [i], Result, l_taken)
					i := i + 1
				end
			end
		ensure
			bounded: Result.count <= policy.max_processes
			all_when_they_fit: a_candidates.count <= policy.max_processes implies Result.count = a_candidates.count
			full_when_they_do_not: a_candidates.count > policy.max_processes implies Result.count = policy.max_processes
			from_candidates: across Result as ic all a_candidates.has (ic) end
		end

	take (a_activity: TM_PROCESS_ACTIVITY; a_into: ARRAYED_LIST [TM_PROCESS_ACTIVITY]; a_taken: HASH_TABLE [BOOLEAN, TM_PROCESS_ID])
			-- Add `a_activity' to `a_into' unless it is already there or `a_into' is full.
		do
			if a_into.count < policy.max_processes and then not a_taken.has (a_activity.id) then
				a_into.extend (a_activity)
				a_taken.force (True, a_activity.id)
			end
		end

	ranked (a_list: ARRAYED_LIST [TM_PROCESS_ACTIVITY]; a_resource: INTEGER): ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			-- `a_list' heaviest first in `a_resource'; unmeasured last (insertion sort: lists are small).
		local
			i, j: INTEGER
			l_item: TM_PROCESS_ACTIVITY
		do
			create Result.make_from_array (a_list.to_array)
			from i := 2 until i > Result.count loop
				l_item := Result [i]
				from j := i - 1 until j < 1 or else score (Result [j], a_resource) >= score (l_item, a_resource) loop
					Result [j + 1] := Result [j]
					j := j - 1
				end
				Result [j + 1] := l_item
				i := i + 1
			end
		ensure
			same_count: Result.count = a_list.count
		end

	score (a_activity: TM_PROCESS_ACTIVITY; a_resource: INTEGER): REAL_64
			-- How much of `a_resource' `a_activity' used; -1 when unmeasured.
		do
			if a_activity.has_resource (a_resource) then
				Result := a_activity.amount_of (a_resource)
			else
				Result := -1.0
			end
		end

end
