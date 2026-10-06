note
	description: "[
		Reads the sources on request, keeps the previous snapshot, and makes
		frames: sysinfo's model, one long-lived object with explicit refresh.
		A monotonic gap longer than Gap_factor nominal intervals (sleep, a
		stalled machine) yields a discontinuity frame, never a rate (A-110).
		A failed process read is not an exception: that snapshot carries no
		processes and the frame says so through its readings.

		Timeline (review issue 2). Frames are continuous: each starts where
		the last ended, and ends at wall time plus `utc_offset'. When the wall
		clock is changed, `clock_change' is non-zero, the frame is flagged,
		and the offset becomes max (0, offset - change): a backward change is
		absorbed so frames stay ordered; a forward change pays the offset back
		down, so labels return to wall time as soon as order allows.
	]"
	author: "Larry Rix"

class
	TM_SAMPLER

create
	make

feature {NONE} -- Initialization

	make (a_processes: TM_PROCESS_SOURCE; a_system: TM_SYSTEM_SOURCE; a_clock: TM_CLOCK)
			-- Sampler over `a_processes', `a_system', and `a_clock', at a 1 s nominal interval.
		require
			trusted: a_processes.is_trusted
			open_sources: not a_processes.is_closed and not a_system.is_closed
		do
			process_source := a_processes
			system_source := a_system
			clock := a_clock
			create builder
			nominal_interval := Default_interval
		ensure
			sources_kept: process_source = a_processes and system_source = a_system and clock = a_clock
			nothing_yet: not has_snapshot and not has_frame
			counters_zero: snapshots_taken = 0 and frames_made = 0 and discontinuities = 0
			default_interval: nominal_interval = Default_interval
			no_self: self_id = Void
			wall_time: utc_offset = 0 and last_end_ticks = 0
		end

feature -- Access

	last_snapshot: TM_SNAPSHOT
			-- Snapshot of the last `sample'.
		require
			has_snapshot: has_snapshot
		do
			check attached last_snapshot_cell as al_snapshot then
				Result := al_snapshot
			end
		end

	previous_snapshot: TM_SNAPSHOT
			-- Snapshot of the `sample' before the last one.
		require
			has_previous: has_previous_snapshot
		do
			check attached previous_snapshot_cell as al_snapshot then
				Result := al_snapshot
			end
		end

	last_frame: TM_FRAME
			-- Frame made by the last `sample'.
		require
			has_frame: has_frame
		do
			check attached last_frame_cell as al_frame then
				Result := al_frame
			end
		end

	last_tick_cost: INTEGER_64
			-- Monotonic ticks spent in the last `sample'; what the self-budget governs (R-1).

	nominal_interval: INTEGER_64
			-- Expected ticks between samples; drives discontinuity detection.

	utc_offset: INTEGER_64
			-- Ticks the timeline runs ahead of wall time, after a backward clock change.

	last_end_ticks: INTEGER_64
			-- End of the last frame on the timeline; 0 before the first frame.

	snapshots_taken: INTEGER
	frames_made: INTEGER
	discontinuities: INTEGER

	self_id: detachable TM_PROCESS_ID
			-- This tool's identity, for its own readings; Void when unknown (review issue 5).

	process_source: TM_PROCESS_SOURCE
	system_source: TM_SYSTEM_SOURCE
	clock: TM_CLOCK

feature -- Status report

	has_snapshot: BOOLEAN
			-- Has `sample' run at least once?
		do
			Result := attached last_snapshot_cell
		end

	has_previous_snapshot: BOOLEAN
			-- Has `sample' run at least twice?
		do
			Result := attached previous_snapshot_cell
		end

	has_frame: BOOLEAN
			-- Did the last `sample' make a frame?
		do
			Result := attached last_frame_cell
		end

	is_gap (a_previous, a_current: TM_SNAPSHOT): BOOLEAN
			-- Is the monotonic distance between the two longer than `Gap_factor' nominal intervals?
		do
			Result := a_current.monotonic_ticks - a_previous.monotonic_ticks > Gap_factor * nominal_interval
		end

	clock_change (a_previous, a_current: TM_SNAPSHOT): INTEGER_64
			-- How far the wall clock was moved between the two snapshots (positive:
			-- forward); 0 when wall and monotonic time agree within `Clock_tolerance'
			-- and the wall clock advanced.
		require
			ordered: a_current.monotonic_ticks > a_previous.monotonic_ticks
		local
			l_wall, l_difference: INTEGER_64
		do
			l_wall := a_current.utc_ticks - a_previous.utc_ticks
			l_difference := l_wall - (a_current.monotonic_ticks - a_previous.monotonic_ticks)
			if l_wall <= 0 or l_difference.abs > Clock_tolerance then
				Result := l_difference
			end
		ensure
			zero_means_wall_advanced: Result = 0 implies a_current.utc_ticks > a_previous.utc_ticks
		end

feature -- Element change

	set_nominal_interval (a_ticks: INTEGER_64)
			-- Expect a sample every `a_ticks'.
		require
			sane: a_ticks >= Minimum_interval and a_ticks <= Maximum_interval
		do
			nominal_interval := a_ticks
		ensure
			kept: nominal_interval = a_ticks
		end

	set_self_id (a_id: TM_PROCESS_ID)
			-- This tool is `a_id'.
		require
			not_idle: not a_id.is_idle_pseudo_process
		do
			self_id := a_id
		ensure
			kept: self_id = a_id
		end

feature -- Basic operations

	sample
			-- Read both sources, make a snapshot, and, from the second call on, a frame.
		require
			open_sources: not process_source.is_closed and not system_source.is_closed
		local
			l_start_cost: INTEGER_64
			l_samples: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			l_snapshot: TM_SNAPSHOT
			l_change, l_start, l_end: INTEGER_64
			l_frame: TM_FRAME
		do
			l_start_cost := clock.monotonic_ticks
			process_source.read_all
			if process_source.last_read_succeeded then
				l_samples := process_source.last_samples
			else
				create l_samples.make (0)
			end
			system_source.refresh
			create l_snapshot.make (clock.utc_ticks, clock.monotonic_ticks, l_samples, system_source.last_readings)
			if attached last_snapshot_cell as al_previous then
				l_change := clock_change (al_previous, l_snapshot)
				if last_end_ticks > 0 then
					l_start := last_end_ticks
				else
					l_start := al_previous.utc_ticks
				end
				utc_offset := (utc_offset - l_change).max (0)
				l_end := l_snapshot.utc_ticks + utc_offset
				if is_gap (al_previous, l_snapshot) then
					l_frame := builder.discontinuity (al_previous, l_snapshot, l_start, l_end, l_change /= 0,
						system_source.logical_processors, system_source.supported_codes)
					discontinuities := discontinuities + 1
				else
					l_frame := builder.build (al_previous, l_snapshot, l_start, l_end, l_change /= 0,
						system_source.logical_processors, self_id, last_tick_cost)
				end
				last_frame_cell := l_frame
				frames_made := frames_made + 1
				last_end_ticks := l_end
			end
			previous_snapshot_cell := last_snapshot_cell
			last_snapshot_cell := l_snapshot
			snapshots_taken := snapshots_taken + 1
			last_tick_cost := clock.monotonic_ticks - l_start_cost
		ensure
			snapshot_taken: has_snapshot and snapshots_taken = old snapshots_taken + 1
			previous_kept: previous_snapshot_cell = old last_snapshot_cell
			frame_after_first: (old has_snapshot) = has_frame
			counted: has_frame implies frames_made = old frames_made + 1
			gap_counted: (has_frame and then last_frame.is_discontinuity) implies discontinuities = old discontinuities + 1
			live_not_counted: (has_frame and then not last_frame.is_discontinuity) implies discontinuities = old discontinuities
			gap_rule: has_frame implies last_frame.is_discontinuity = is_gap (previous_snapshot, last_snapshot)
			continuous: (has_frame and old last_end_ticks > 0) implies last_frame.start_ticks = old last_end_ticks
			first_from_wall: (has_frame and old last_end_ticks = 0) implies last_frame.start_ticks = previous_snapshot.utc_ticks
			offset_rule: has_frame implies utc_offset = (old utc_offset - clock_change (previous_snapshot, last_snapshot)).max (0)
			end_rule: has_frame implies last_frame.end_ticks = last_snapshot.utc_ticks + utc_offset
			adjusted_iff_changed: has_frame implies (last_frame.is_clock_adjusted = (clock_change (previous_snapshot, last_snapshot) /= 0))
			end_recorded: has_frame implies last_end_ticks = last_frame.end_ticks
			cost_measured: last_tick_cost >= 0
			interval_unchanged: nominal_interval = old nominal_interval
		end

feature -- Constants

	Default_interval: INTEGER_64 = 10_000_000
			-- One second.

	Minimum_interval: INTEGER_64 = 2_500_000
			-- 250 ms.

	Maximum_interval: INTEGER_64 = 600_000_000
			-- 60 s.

	Gap_factor: INTEGER_64 = 5
			-- Nominal intervals beyond which a gap is a discontinuity (A-110).

	Clock_tolerance: INTEGER_64 = 20_000_000
			-- 2 s: wall and monotonic time may drift this far before it counts as a clock change.

feature {NONE} -- Implementation

	builder: TM_FRAME_BUILDER
	last_snapshot_cell: detachable TM_SNAPSHOT
	previous_snapshot_cell: detachable TM_SNAPSHOT
	last_frame_cell: detachable TM_FRAME

invariant
	frames_bounded: frames_made >= discontinuities
	snapshots_bound_frames: snapshots_taken >= frames_made
	interval_sane: nominal_interval >= Minimum_interval and nominal_interval <= Maximum_interval
	cost_non_negative: last_tick_cost >= 0
	frame_needs_snapshot: has_frame implies has_snapshot
	offset_non_negative: utc_offset >= 0
	timeline_on_wall_plus_offset: has_frame implies last_end_ticks = last_snapshot.utc_ticks + utc_offset
	self_not_idle: attached self_id as al_self implies not al_self.is_idle_pseudo_process

end
