note
	description: "[
		What the machine did between two consecutive snapshots: system
		readings, process activities, identities born, identities that exited.
		The unit that is displayed, recorded, handed between processors, and
		diagnosed. Immutable once made: its readings are sealed.
	]"
	author: "Larry Rix"

class
	TM_FRAME

inherit
	TM_SHARED_METRICS

create
	make,
	make_discontinuity,
	make_decoded

feature {NONE} -- Initialization

	make (a_start, a_end, a_duration: INTEGER_64; a_logical_processors: INTEGER; a_clock_adjusted: BOOLEAN;
			a_readings: TM_READINGS; a_activities: ITERABLE [TM_PROCESS_ACTIVITY];
			a_born: ITERABLE [TM_PROCESS_ID]; a_exited: ITERABLE [TM_PROCESS_SAMPLE])
			-- Live frame from `a_start' to `a_end' (timeline ticks), `a_duration' monotonic ticks long.
			-- `a_clock_adjusted': the wall clock was changed during this interval.
		require
			ordered: a_end > a_start
			positive_duration: a_duration > 0
			processors: a_logical_processors > 0
			no_idle: across a_activities as ic all not ic.id.is_idle_pseudo_process end
		do
			start_ticks := a_start
			end_ticks := a_end
			duration := a_duration
			logical_processors := a_logical_processors
			is_clock_adjusted := a_clock_adjusted
			is_complete := True
			readings := a_readings
			create activity_table.make (512)
			create born_list.make (8)
			create exited_list.make (8)
			if not a_readings.is_sealed then
				a_readings.seal
			end
			across a_activities as ic loop
				activity_table.force (ic, ic.id)
			end
			across a_born as ic loop
				born_list.extend (ic)
			end
			across a_exited as ic loop
				exited_list.extend (ic)
			end
		ensure
			times_kept: start_ticks = a_start and end_ticks = a_end and duration = a_duration
			readings_kept: readings = a_readings
			sealed: readings.is_sealed
			complete: is_complete and omitted_processes = 0
			live: not is_discontinuity
			adjusted_kept: is_clock_adjusted = a_clock_adjusted
			every_activity: across a_activities as ic all has_activity (ic.id) end
			born_are_new_activities: across born_list as ic all has_activity (ic) and then activity (ic).is_new end
			exited_not_active: across exited_list as ic all not has_activity (ic.id) end
		end

	make_discontinuity (a_start, a_end, a_duration: INTEGER_64; a_logical_processors: INTEGER; a_clock_adjusted: BOOLEAN;
			a_supported: ITERABLE [INTEGER])
			-- Gap frame: the tool was not measuring (sleep, stall). No activities;
			-- every supported metric reads unavailable, not "not supported".
		require
			ordered: a_end > a_start
			positive_duration: a_duration > 0
			processors: a_logical_processors > 0
			known_metrics: across a_supported as ic all metrics.has_code (ic) end
		local
			l_readings: TM_READINGS
		do
			start_ticks := a_start
			end_ticks := a_end
			duration := a_duration
			logical_processors := a_logical_processors
			is_clock_adjusted := a_clock_adjusted
			is_discontinuity := True
			is_complete := True
			create l_readings.make
			across a_supported as ic loop
				if not metrics.metric (ic).is_instanced then
					l_readings.put (ic, {STRING_32} "", create {TM_READING}.make_unavailable)
				end
			end
			l_readings.seal
			readings := l_readings
			create activity_table.make (0)
			create born_list.make (0)
			create exited_list.make (0)
		ensure
			times_kept: start_ticks = a_start and end_ticks = a_end and duration = a_duration
			flagged: is_discontinuity
			adjusted_kept: is_clock_adjusted = a_clock_adjusted
			empty: activity_count = 0 and born_list.is_empty and exited_list.is_empty
			sealed: readings.is_sealed
			all_unavailable: across a_supported as ic all
				not metrics.metric (ic).is_instanced implies readings.reading (ic, {STRING_32} "").is_unavailable end
		end

	make_decoded (a_start, a_end, a_duration: INTEGER_64; a_logical_processors: INTEGER;
			a_is_discontinuity, a_clock_adjusted: BOOLEAN; a_omitted: INTEGER;
			a_readings: TM_READINGS; a_activities: ITERABLE [TM_PROCESS_ACTIVITY];
			a_born: ITERABLE [TM_PROCESS_ID]; a_exited: ITERABLE [TM_PROCESS_SAMPLE])
			-- Frame rebuilt from a recording; may hold only the significant processes.
		require
			ordered: a_end > a_start
			positive_duration: a_duration > 0
			processors: a_logical_processors > 0
			omitted_non_negative: a_omitted >= 0
			no_idle: across a_activities as ic all not ic.id.is_idle_pseudo_process end
			discontinuity_empty: a_is_discontinuity implies
				not (across a_activities as ic some True end or across a_born as ic some True end)
		do
			start_ticks := a_start
			end_ticks := a_end
			duration := a_duration
			logical_processors := a_logical_processors
			is_discontinuity := a_is_discontinuity
			is_clock_adjusted := a_clock_adjusted
			omitted_processes := a_omitted
			is_complete := False
			readings := a_readings
			create activity_table.make (64)
			create born_list.make (8)
			create exited_list.make (8)
			if not a_readings.is_sealed then
				a_readings.seal
			end
			across a_activities as ic loop
				activity_table.force (ic, ic.id)
			end
			across a_born as ic loop
				born_list.extend (ic)
			end
			across a_exited as ic loop
				exited_list.extend (ic)
			end
		ensure
			times_kept: start_ticks = a_start and end_ticks = a_end and duration = a_duration
			flags_kept: is_discontinuity = a_is_discontinuity and is_clock_adjusted = a_clock_adjusted
				and omitted_processes = a_omitted
			exited_not_active: across exited_list as ic all not has_activity (ic.id) end
			recorded: not is_complete
			sealed: readings.is_sealed
		end

feature -- Access

	start_ticks: INTEGER_64
			-- UTC ticks at the earlier snapshot.

	end_ticks: INTEGER_64
			-- UTC ticks at the later snapshot.

	duration: INTEGER_64
			-- Monotonic ticks between the snapshots.

	logical_processors: INTEGER
			-- Logical processors of the machine.

	omitted_processes: INTEGER
			-- Processes below the recording threshold, not stored (FR-NEW-012).

	readings: TM_READINGS
			-- System readings; sealed.

	activity_count: INTEGER
			-- Number of activities.
		do
			Result := activity_table.count
		end

	activity (a_id: TM_PROCESS_ID): TM_PROCESS_ACTIVITY
			-- The activity of `a_id'.
		require
			present: has_activity (a_id)
		do
			check attached activity_table.item (a_id) as al_activity then
					-- `has_activity' guarantees presence.
				Result := al_activity
			end
		ensure
			matches: Result.id ~ a_id
		end

	activities: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			-- All activities in arbitrary order; a fresh list each call (FR-057).
		do
			create Result.make (activity_count)
			across activity_table as ic loop
				Result.extend (ic)
			end
		ensure
			fresh_each_call: Result /= activities
			complete: Result.count = activity_count
		end

	self_activity (a_self: TM_PROCESS_ID): detachable TM_PROCESS_ACTIVITY
			-- This tool's own activity, when present.
		do
			Result := activity_table.item (a_self)
		ensure
			present_iff_known: attached Result = has_activity (a_self)
		end

	top_by (a_resource, a_count: INTEGER): ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			-- At most `a_count' activities with `a_resource' measured, largest first.
		require
			known_resource: a_resource >= {TM_RESOURCE}.Cpu and a_resource <= {TM_RESOURCE}.Io_total
			positive: a_count > 0
		local
			l_amount: REAL_64
			i: INTEGER
		do
			create Result.make (a_count + 1)
			across activity_table as ic loop
				if ic.has_resource (a_resource) then
					l_amount := ic.amount_of (a_resource)
					from
						i := 1
					until
						i > Result.count or else Result [i].amount_of (a_resource) < l_amount
					loop
						i := i + 1
					end
					if i <= a_count then
						if i > Result.count then
							Result.extend (ic)
						else
							Result.go_i_th (i)
							Result.put_left (ic)
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
			measured_only: across Result as ic all ic.has_resource (a_resource) end
			descending: across 2 |..| Result.count as ic all
				Result [ic - 1].amount_of (a_resource) >= Result [ic].amount_of (a_resource) end
			as_many_as_possible: Result.count = a_count.min (measured_count (a_resource))
		end

	born: ARRAYED_LIST [TM_PROCESS_ID]
			-- Identities born during the interval; a fresh list.
		do
			create Result.make (born_list.count)
			Result.append (born_list)
		ensure
			fresh: Result /= born_list
		end

	exited: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			-- Last samples of identities that exited during the interval; a fresh list.
		do
			create Result.make (exited_list.count)
			Result.append (exited_list)
		ensure
			fresh: Result /= exited_list
		end

	measured_count (a_resource: INTEGER): INTEGER
			-- Number of activities with `a_resource' measured.
		require
			known_resource: a_resource >= {TM_RESOURCE}.Cpu and a_resource <= {TM_RESOURCE}.Io_total
		do
			across activity_table as ic loop
				if ic.has_resource (a_resource) then
					Result := Result + 1
				end
			end
		ensure
			bounded: Result >= 0 and Result <= activity_count
		end

feature -- Status report

	is_discontinuity: BOOLEAN
			-- Was the tool not measuring during this interval?

	is_complete: BOOLEAN
			-- Does this frame hold every process? False when decoded from a recording.

	is_clock_adjusted: BOOLEAN
			-- Was the wall clock changed during this interval? Then the span follows
			-- the tool's continuous timeline, not the new wall time (review issue 2).

	has_activity (a_id: TM_PROCESS_ID): BOOLEAN
			-- Is there an activity for `a_id'?
		do
			Result := activity_table.has (a_id)
		end

feature -- Model

	identities_model: MML_SET [TM_PROCESS_ID]
			-- Identities with an activity.
		do
			create Result
			across activity_table as ic loop
				Result := Result & @ic.key
			end
		ensure
			same_count: Result.count = activity_count
		end

	born_model: MML_SET [TM_PROCESS_ID]
			-- Identities born during the interval.
		do
			create Result
			across born_list as ic loop
				Result := Result & ic
			end
		end

feature {NONE} -- Implementation

	activity_table: HASH_TABLE [TM_PROCESS_ACTIVITY, TM_PROCESS_ID]
			-- Activities by identity.

	born_list: ARRAYED_LIST [TM_PROCESS_ID]
			-- Born identities.

	exited_list: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			-- Last samples of exited identities.

invariant
	ordered: end_ticks > start_ticks
	positive_duration: duration > 0
	processors: logical_processors > 0
	readings_sealed: readings.is_sealed
	discontinuity_is_empty: is_discontinuity implies (activity_count = 0 and born_list.is_empty)
	recorded_subset: is_complete implies omitted_processes = 0
	omitted_non_negative: omitted_processes >= 0

end
